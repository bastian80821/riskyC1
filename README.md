# riscyC1 — A RISC-V RV32I Core on FPGA

A 5-stage pipelined RISC-V RV32I processor, written from scratch in SystemVerilog and
running on a **Digilent Arty S7-50** (Xilinx Spartan-7 XC7S50). Programs are loaded at
runtime over a serial link and the core prints its output back to a terminal.

```
> python scripts/send_program.py COM5 programs/hello_test.hex
Loaded 14 instruction words from programs/hello_test.hex
Program sent.  Core released.  Output follows:
----------------------------------------
HI
```

Built module by module with a self-checking testbench for every component. The
day-by-day reasoning, design decisions, and bugs hit along the way are in the
[build log](docs/devlog.md).

## Results

| Metric | Value |
|---|---|
| Device | Xilinx Spartan-7 XC7S50-1 (Arty S7-50) |
| **fmax** | **~94 MHz** (timing closed, zero failing endpoints) |
| **LUT** | **1,120** (3.44%) |
| **FF** | **699** (1.07%) |
| **BRAM** | 0.5 tiles |
| Pipeline | 5-stage, full forwarding, branch flushing |
| Verification | 18/18 core regression checks + per-module testbenches |

Critical path is the branch-redirect route (EX/MEM forwarded into the branch comparator
and back to the PC): 10.6 ns, 21 logic levels, 60% net delay.

## Status

| Milestone | State |
|---|---|
| Single-cycle datapath, all RV32I base instructions | Done |
| 5-stage pipeline: registers, forwarding, branch flushing | Done |
| Memory-mapped UART (TX + RX) | Done |
| Bootloader — runtime program loading over serial | Done |
| Synthesis, timing closure, hardware bring-up | Done |
| Verification: riscv-tests, Spike co-simulation | Next |
| Benchmarks (Dhrystone / CoreMark) | Planned |
| Branch resolution in ID (fmax + IPC optimisation) | Planned |
| Byte/halfword loads and stores | Planned |

## Instruction support

R-type ALU ops (add, sub, and, or, xor, sll, srl, sra, slt, sltu), I-type immediate ops,
all six conditional branches (beq, bne, blt, bge, bltu, bgeu), JAL/JALR, LW/SW, LUI/AUIPC.

Not implemented: byte/halfword memory access (lb, lbu, lh, lhu, sb, sh), CSRs,
traps/interrupts, the M extension.

## Design

Two cores share the same underlying modules: a single-cycle implementation
(`core.sv`) and the 5-stage pipelined version (`core_pipelined.sv`) built from it.
Pipelining changes only how the modules are wired and when signals move between stages.

### Single-cycle datapath

Harvard configuration — separate instruction and data memories, so a fetch and a data
access can occur in the same cycle. Control flow is a 3-way mux on the PC input: `pc+4`,
`pc+imm` (taken branches and JAL), or `rs1+imm` (JALR). Writeback is a 5-way mux: ALU
result, memory data, `pc+4` (jumps), the immediate (LUI), or `pc+imm` (AUIPC). Branch
conditions come from a dedicated comparator rather than the ALU.

**Initial design sketch:**

![Initial design](docs/images/initial_design.PNG)

**Final single-cycle datapath:**

![Single-cycle datapath](docs/images/no_pipeline_final.jpg)

### 5-stage pipeline

IF | ID | EX | MEM | WB, with four pipeline register banks. Five instructions in flight,
so the clock period is set by the slowest *stage* rather than the slowest *instruction*.

**Pipeline components:**

![Pipeline components](docs/images/pipeline_components.jpg)

**Pipeline dataflow:**

![Pipeline dataflow](docs/images/pipeline_dataflow.jpg)

#### Hazard handling

**Data hazards — forwarding.** A forwarding unit in EX compares `exe_rs1`/`exe_rs2`
against `mem_rd`/`wb_rd`; two 3-way muxes feed the ALU operands from the register value,
MEM, or WB, with MEM taking priority (newer value). The forwarded value is the resolved
writeback mux output, not the raw ALU result, so `jal` return addresses and `lui`
immediates forward correctly. Store data, the branch comparator, and the JALR target adder
all use forwarded operands.

**Control hazards — flushing.** Branches resolve in EX, so two speculatively-fetched
instructions are in flight when the outcome is known. On a taken branch or jump, IF/ID and
ID/EX are cleared: a zeroed register decodes as opcode 0, hits the decoder's default case,
and becomes a bubble. Reuses the reset path — no new hardware.

**Register file write-first.** A read in ID of a register being written in WB that same
cycle returns the incoming data rather than the stale stored value.

**Load-use.** No stall required: dmem's read is combinational and the writeback mux
resolves in MEM, so the loaded value is forwardable in time. A deliberate tradeoff, costing
a longer MEM path; a regression test guards the assumption and will fail if dmem ever
becomes a registered read.

### Memory-mapped UART

`uart_tx` and `uart_rx` are 4-state FSMs with a parameterised baud rate, framing bytes as
start bit + 8 data bits LSB-first + stop bit. The receiver samples the middle of each bit
window and synchronises the asynchronous input through two flip-flops.

An address decoder in MEM routes accesses above `0x1000` to the device instead of memory:

| Address | Access | Meaning |
|---|---|---|
| `0x1000` | write | transmit the low byte |
| `0x1004` | read | returns the `tx_busy` flag |

There is no hardware stall for I/O — a store while the UART is busy is dropped, so
software polls the busy flag before sending.

### Bootloader

A hardware FSM receives a program over UART and writes it into instruction memory, then
releases the core. Protocol (little-endian): 4 bytes of word count, then that many
4-byte instruction words.

The core is held in reset for the entire load, so the bootloader owns imem's write port
and the core owns its read port — no arbitration needed.

This is also what makes the synthesis numbers meaningful: with a write port fed from
outside, the program is unknown at synthesis time, so Vivado must build a general-purpose
core rather than specialising the datapath to one baked-in program. (Before the write port
existed, reported utilisation was 274 LUTs — a circuit computing one program's output, not
a processor.)

## Repository layout

```
rtl/
  pc.sv               Program counter
  imem.sv             Instruction memory (bootloader write port)
  dmem.sv             Data memory
  decoder.sv          Instruction decoder + control signal generation
  register_file.sv    32x32 register file (2R1W, x0 hardwired, write-first)
  imm_gen.sv          Immediate generator (I/S/B/U/J formats)
  alu.sv              ALU (10 RV32I operations)
  uart_tx.sv          UART transmitter
  uart_rx.sv          UART receiver
  bootloader.sv       Serial program loader
  core.sv             Single-cycle datapath
  core_pipelined.sv   5-stage pipelined datapath + memory-mapped UART
  top.sv              Board top level
tb/                   Self-checking testbench per module, core regression suites,
                      and an end-to-end bootloader test
programs/             Test programs as hex files
scripts/
  build.tcl           Regenerates the Vivado project from source
  send_program.py     Sends a hex program over serial and prints the output
constraints/          Pin assignments for the Arty S7-50
boards/               Pristine Digilent master XDC (reference only)
docs/                 Build log and diagrams
```

## Verification

Every module has a self-checking testbench reporting PASS/FAIL and targeting edge cases
(sign-extension, funct7 decode, signed vs unsigned comparison, x0 handling, UART framing
of `0x00` / `0xFF` / alternating patterns).

The core **regression suite** loads each program in `programs/`, runs it, and asserts on
the resulting register and memory state. `tb/core_tb.sv` runs it against the single-cycle
core, `tb/core_pipe_tb.sv` against the pipelined one — which is how hazard handling was
tracked as it was added (11/16 → 15/16 → 16/16 → 18/18). Coverage: ALU ops, store/load
round trip, branches taken and not-taken, function call and return, LUI/AUIPC, and a
load-use hazard guard.

`tb/boot_tb.sv` is a full end-to-end test: it acts as the host, sending a program bit by
bit at real baud timing, waits for the bootloader to release the core, then decodes the
serial output as a terminal would.

## Building and running

Source-only — Vivado's generated files are not committed.

1. Regenerate the project (Vivado Tcl console):
   ```
   cd <path-to-repo>
   source scripts/build.tcl
   ```
2. Set `top` as the design top, generate a bitstream, and program the board.
3. Send a program:
   ```
   pip install pyserial
   python scripts/send_program.py COM5 programs/hello_test.hex
   ```

LD2 indicates the bootloader is waiting; LD3 indicates the core is running.

### Note on the UART pins

Digilent's master XDC names the UART pins from the **USB bridge's** perspective:
`uart_rxd_out` (R12) is the bridge's receive line — i.e. where the **FPGA transmits** —
and `uart_txd_in` (V12) is where the **FPGA receives**. Easy to get backwards.

## License

MIT — see [LICENSE](LICENSE).
