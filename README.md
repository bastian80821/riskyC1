# riscyC1 — A RISC-V RV32I Core on FPGA

A RISC-V RV32I processor written from scratch in SystemVerilog, built module by module
with a self-checking testbench for every component. Target board: **Digilent Arty S7-50**
(Xilinx Spartan-7 XC7S50). Toolchain: **Vivado**.

The repository contains two working cores — a **single-cycle** implementation and a
**5-stage pipelined** version with forwarding and branch flushing — plus a memory-mapped
UART, so the core can execute a program and print its output over serial. The day-by-day
reasoning, design decisions, and bugs hit along the way are in the
[build log](docs/devlog.md).

## Status

| Milestone | State |
|---|---|
| Board bring-up (blink) | Done |
| Register file, ALU, immediate generator, decoder | Done |
| Single-cycle datapath | Done |
| Conditional branches (all 6), JAL/JALR, LW/SW, LUI/AUIPC | Done |
| Programs loaded from hex files | Done |
| Self-checking regression suite | Done |
| 5-stage pipeline: stage split + registers | Done |
| 5-stage pipeline: forwarding | Done |
| 5-stage pipeline: branch flushing | Done |
| **UART transmitter + memory-mapped I/O** | **Done** |
| UART receiver + bootloader (runtime program loading) | Next |
| Synthesis + timing closure (fmax / utilisation) | Blocked on bootloader |
| Verification: riscv-tests, Spike co-simulation | Planned |
| On-hardware demo | Planned |
| Byte/halfword loads and stores | Planned |
| Branch prediction + benchmarks | Planned |

## Instruction support

Implemented: R-type ALU ops (add, sub, and, or, xor, sll, srl, sra, slt, sltu), I-type
immediate ops, all six conditional branches (beq, bne, blt, bge, bltu, bgeu), JAL/JALR,
LW/SW, LUI/AUIPC.

Not yet implemented: byte and halfword memory access (lb, lbu, lh, lhu, sb, sh), CSRs,
traps/interrupts, the M extension.

## Design

Both cores share the same underlying modules — pipelining changes only how they are wired
together and when signals move between stages.

### Single-cycle datapath

Harvard configuration (separate instruction and data memories, so a fetch and a data
access can occur in the same cycle). Control flow is a 3-way mux on the PC input: `pc+4`,
`pc+imm` (taken branches and JAL), or `rs1+imm` (JALR). Writeback is a 5-way mux: ALU
result, memory data, `pc+4` (jumps), the immediate (LUI), or `pc+imm` (AUIPC). Branch
conditions come from a dedicated comparator rather than the ALU.

**Initial design sketch:**

![Initial design](docs/images/initial_design.PNG)

**Final single-cycle datapath:**

![Single-cycle datapath](docs/images/no_pipeline_final.jpg)

### 5-stage pipeline

Split into IF | ID | EX | MEM | WB with four pipeline register banks. Five instructions in
flight, so the clock period is set by the slowest *stage* rather than the slowest
*instruction*.

**Pipeline components:**

![Pipeline components](docs/images/pipeline_components.jpg)

**Pipeline dataflow:**

![Pipeline dataflow](docs/images/pipeline_dataflow.jpg)

#### Hazard handling

**Data hazards — forwarding.** A forwarding unit in EX compares `exe_rs1`/`exe_rs2`
against `mem_rd`/`wb_rd`; two 3-way muxes feed the ALU operands from the register value,
MEM, or WB. MEM takes priority (newer value). The forwarded value is `mem_wb_data` — the
resolved writeback mux output, not the raw ALU result, so `jal` return addresses and `lui`
immediates forward correctly. Store data, the **branch comparator**, and the JALR target
adder all use forwarded operands.

**Control hazards — flushing.** Branches resolve in EX, so two speculatively-fetched
instructions are in flight when the outcome is known. On a taken branch or jump, IF/ID and
ID/EX are cleared: a zeroed register decodes as opcode 0, hits the decoder's default case,
and becomes a bubble. Reuses the reset path.

**Register file write-first.** A read in ID of a register being written in WB that same
cycle returns the incoming data rather than the stale stored value.

**Load-use.** No stall required: dmem's read is combinational and the writeback mux
resolves in MEM, so the loaded value is already in `mem_wb_data` and forwardable in time.
A deliberate tradeoff — it costs a long MEM critical path and prevents BRAM inference. A
regression test guards the assumption.

### Memory-mapped UART

`uart_tx.sv` is a 4-state FSM (IDLE/START/DATA/STOP) with a parameterised baud rate,
framing bytes as start bit + 8 data bits LSB-first + stop bit. At 100 MHz and 115200 baud
that is 868 clock cycles per bit.

An address decoder in the MEM stage routes accesses above `0x1000` to the device instead
of memory:

| Address | Access | Meaning |
|---|---|---|
| `0x1000` | write | transmit the low byte |
| `0x1004` | read | returns the `tx_busy` flag |

There is no hardware stall for I/O — a store while the UART is busy is silently dropped,
so software must poll the busy flag before sending. The core busy-waits at full speed
during the ~8,700 cycles a byte takes.

## Repository layout

```
rtl/
  pc.sv               Program counter
  imem.sv             Instruction memory (loads a hex program)
  dmem.sv             Data memory
  decoder.sv          Instruction decoder + control signal generation
  register_file.sv    32x32 register file (2 read, 1 write; x0 hardwired; write-first)
  imm_gen.sv          Immediate generator (I/S/B/U/J formats)
  alu.sv              ALU (10 RV32I operations)
  uart_tx.sv          UART transmitter (FSM, parameterised baud)
  core.sv             Single-cycle top-level datapath
  core_pipelined.sv   5-stage pipelined datapath + memory-mapped UART
  blink.sv            Board bring-up test
tb/                   Self-checking testbench per module, plus core regression suites
programs/             Test programs as hex files
constraints/          Minimal per-project XDC for the Arty S7-50
boards/               Pristine Digilent master XDC (reference only)
scripts/              build.tcl - regenerates the Vivado project from source
docs/                 Build log and diagrams
```

## Verification

Every module has a self-checking testbench reporting PASS/FAIL and targeting edge cases
(sign-extension, funct7 decode, signed vs unsigned comparison, x0 handling, UART framing
of `0x00` / `0xFF` / alternating patterns).

The core **regression suite** loads each program in `programs/`, runs it, and asserts on
the resulting register and memory state. `tb/core_tb.sv` runs it against the single-cycle
core; `tb/core_pipe_tb.sv` against the pipelined one — which is how hazard handling was
tracked as it was added (11/16 → 15/16 → 16/16 → 18/18).

`tb/uart_hello_tb.sv` is an end-to-end integration test: it loads a program that prints
`"HI\n"`, decodes the serial line exactly as a terminal would, and checks the received
bytes.

**Current results: single-cycle 16/16, pipelined 18/18, UART integration passing.**

## Building

Source-only — Vivado's generated files are not committed. Regenerate the project:

1. In Vivado's Tcl console:
   ```
   cd <path-to-repo>
   source scripts/build.tcl
   ```
2. Run synthesis, implementation, and generate bitstream — or run a testbench via
   Run Simulation (set the desired `*_tb` as simulation top).

### Known limitation: synthesis numbers are not yet meaningful

The program is baked into `imem` by `$readmemh` at synthesis time, so Vivado knows exactly
which instructions exist and specialises the design — constant-folding through the decoder
and deleting logic the program never exercises. Reported utilisation (~300 LUTs) reflects
*a circuit that computes one program's output*, not a general-purpose core.

Honest numbers require the program to be unknown at synthesis, i.e. loaded at runtime via
UART RX and a bootloader. That is the next piece of work.

### Known limitation: hex file paths

`$readmemh` calls currently use **absolute paths** to `programs/*.hex` and must be edited
to match your checkout location. Relative paths resolve against the simulator's working
directory inside the gitignored build folder.

## License

MIT — see [LICENSE](LICENSE).
