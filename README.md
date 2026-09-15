# riscyC1 — A RISC-V RV32I Core on FPGA

A 5-stage pipelined RISC-V RV32I processor, written from scratch in SystemVerilog and
running on a **Digilent Arty S7-50** (Xilinx Spartan-7 XC7S50). Programs are loaded at
runtime over a serial link; the core executes them and prints results back to a terminal.

**Passes 38/38 of the official `riscv-tests` rv32ui ISA suite on hardware.**

```
> python scripts/send_program.py COM5 programs/hello_test.hex
Loaded 14 instruction words from programs/hello_test.hex
Program sent.  Core released.  Output follows:
----------------------------------------
HI
```

Built module by module, each with a self-checking testbench. The day-by-day reasoning,
design decisions, and bugs hit along the way are in the [build log](docs/devlog.md).

## Results

| Metric | Value |
|---|---|
| Device | Xilinx Spartan-7 XC7S50-1 (Arty S7-50) |
| **Clock** | **70 MHz** — closes with +0.300 ns slack; 75 MHz fails at −0.257 ns |
| **LUT** | 2,255 (6.9%) |
| **LUTRAM** | 812 (8.5%) |
| **FF** | 796 (1.2%) |
| **BRAM** | 1 (1.3%) |
| **IPC / CPI** | **0.834 / 1.199** |
| **MIPS** | **58.4** |
| **ISA compliance** | **38/38 rv32ui** |

The IPC figure decomposes exactly. On a 200-iteration loop mixing dependent ALU
operations, a store, a load-use hazard, and a taken branch:

| | |
|---|---|
| Loop body | 10 instructions × 200 = 2,000 |
| Taken branches | 199 × 2 flushed instructions = 398 cycles |
| Predicted | 2,398 cycles |
| Measured | 2,403 cycles |

**Every non-ideal cycle is a branch flush.** Forwarding covers all data dependencies
including the load-use, so control hazards are the sole penalty.

### Critical path

```
From  EX/MEM register (mem_alu_result)
To    the PC, and the ID/EX register reset pins (fanout 256)
      13.4 ns = 4.1 ns logic + 9.3 ns net,  19 logic levels
```

The branch-redirect route: a value in MEM forwarded backward into EX, through the branch
comparator and decision logic, then to the PC. **Net delay is ~70% of the path** — routing,
not logic depth.

Tried and rejected: `max_fanout` replication on the flush signal (ignored by Vivado for
nets driving control pins) and `-control_set_opt_threshold 16` (broke up the reset groups
but made slack *worse*, −0.716 ns). The bottleneck is architectural, not a synthesis
setting.

**Identified fix:** resolve branches in ID rather than EX. Shortens the path, and halves
the branch penalty — predicted IPC ~0.91. Requires a second forwarding network into ID
plus stall logic for branch-after-ALU dependencies. Scoped, not implemented.

## Instruction support

Complete RV32I base integer ISA except `fence`/`fence.i` and misaligned access:

- **ALU** — add, sub, and, or, xor, sll, srl, sra, slt, sltu, and immediate forms
- **Branches** — beq, bne, blt, bge, bltu, bgeu
- **Jumps** — jal, jalr
- **Memory** — lb, lbu, lh, lhu, lw, sb, sh, sw
- **Upper immediate** — lui, auipc

Not implemented: CSRs, traps/interrupts, `fence_i` (no instruction cache), misaligned
access, the M extension.

## Design

Two cores share the same modules: a single-cycle implementation (`core.sv`) and the
5-stage pipelined version (`core_pipelined.sv`) built from it.

### Single-cycle datapath

Harvard configuration — separate instruction and data memories, so a fetch and a data
access occur in the same cycle. Control flow is a 3-way mux on the PC: `pc+4`, `pc+imm`
(taken branches and JAL), or `rs1+imm` (JALR). Writeback is a 5-way mux: ALU result,
memory data, `pc+4` (jumps), the immediate (LUI), or `pc+imm` (AUIPC). Branch conditions
come from a dedicated comparator rather than the ALU.

**Initial design sketch:**

![Initial design](docs/images/initial_design.PNG)

**Final single-cycle datapath:**

![Single-cycle datapath](docs/images/no_pipeline_final.jpg)

### 5-stage pipeline

IF | ID | EX | MEM | WB, with four pipeline register banks. Five instructions in flight, so
the clock period is set by the slowest *stage* rather than the slowest *instruction*.

**Pipeline components:**

![Pipeline components](docs/images/pipeline_components.jpg)

**Pipeline dataflow:**

![Pipeline dataflow](docs/images/pipeline_dataflow.jpg)

#### Hazard handling

**Data hazards — forwarding.** A unit in EX compares `exe_rs1`/`exe_rs2` against
`mem_rd`/`wb_rd`; two 3-way muxes feed the ALU operands from the register value, MEM, or
WB, with MEM taking priority. The forwarded value is the resolved writeback mux output,
not the raw ALU result, so `jal` return addresses and `lui` immediates bypass correctly.
Store data, the branch comparator, and the JALR target adder all use forwarded operands.

**Control hazards — flushing.** Branches resolve in EX, so two speculatively-fetched
instructions are in flight when the outcome is known. On a taken branch or jump, IF/ID and
ID/EX are cleared: a zeroed register decodes as opcode 0, hits the decoder's default case,
and becomes a bubble. Reuses the reset path.

**Register file write-first.** A read in ID of a register being written in WB that same
cycle returns the incoming data rather than the stale stored value.

**Load-use.** No stall required: dmem's read is combinational and the writeback mux
resolves in MEM, so the loaded value is forwardable in time. A deliberate tradeoff costing
a longer MEM path; a regression test guards the assumption and fails if dmem ever becomes
a registered read.

### Memory-mapped I/O

| Address | Access | Meaning |
|---|---|---|
| `0x1000` | write | transmit the low byte over UART |
| `0x1004` | read | UART transmitter busy flag |
| `0x1008` | read | cycles elapsed since reset |
| `0x100C` | read | instructions retired since reset |

The counters substitute for `mcycle`/`minstret`, which would normally be CSRs. Counting
*retired* instructions uses a valid bit flowing down the pipeline, cleared on flush, so
bubbles are not counted.

There is no hardware stall for I/O — a store while the UART is busy is dropped, so software
polls the busy flag first.

### Bootloader

A hardware FSM receives a program over UART and writes it into both instruction and data
memory, then releases the core. Protocol, little-endian: 4 bytes of word count, then that
many instruction words. It keeps listening afterwards, so a further word count starts a
fresh load — which is how the ISA suite runs 38 programs back to back without a reset.

The image is mirrored into *both* memories because this is a Harvard machine with separate
address spaces: a program's `.data` section would otherwise land in imem where loads could
never reach it.

This is also what makes the synthesis numbers meaningful. With the program baked in by
`$readmemh` at synthesis time, Vivado knew every instruction and **specialised the design**
— constant-folding through the decoder and deleting logic the program never exercised,
reporting 274 LUTs for what was supposedly a processor. A write port fed from outside makes
the contents unknowable, forcing a general-purpose core.

## Repository layout

```
rtl/
  pc.sv               Program counter
  imem.sv             Instruction memory (bootloader write port)
  dmem.sv             Data memory (byte-granular writes)
  mem_access.sv       Byte/halfword lane selection and sign extension
  decoder.sv          Instruction decoder + control signal generation
  register_file.sv    32x32 register file (2R1W, x0 hardwired, write-first)
  imm_gen.sv          Immediate generator (I/S/B/U/J formats)
  alu.sv              ALU (10 RV32I operations)
  uart_tx.sv          UART transmitter
  uart_rx.sv          UART receiver
  bootloader.sv       Serial program loader
  perf_counters.sv    Cycle and retired-instruction counters
  clk_gen.sv          MMCM: 12 MHz -> 70 MHz
  core.sv             Single-cycle datapath
  core_pipelined.sv   5-stage pipelined datapath
  top.sv              Board top level
tb/                   Self-checking testbench per module, core regression suites,
                      and an end-to-end bootloader test
tests/                riscv-tests build environment (custom riscv_test.h, linker
                      script, build and run scripts)
programs/             Test programs and benchmarks as hex files
scripts/
  build.tcl           Regenerates the Vivado project from source
  send_program.py     Sends a hex program over serial
  run_bench.py        Runs the IPC benchmark and reports results
constraints/          Pin assignments for the Arty S7-50
boards/               Pristine Digilent master XDC (reference only)
docs/                 Build log and diagrams
```

## Verification

**Per-module testbenches.** Every module has one, reporting PASS/FAIL and targeting edge
cases: sign-extension, funct7 decode, signed vs unsigned comparison, x0 handling, UART
framing of `0x00` / `0xFF` / alternating patterns, and all byte lanes and extension modes
for memory access.

**Core regression suite.** Loads each program in `programs/`, runs it, and asserts on the
resulting register and memory state. `tb/core_tb.sv` targets the single-cycle core,
`tb/core_pipe_tb.sv` the pipelined one — which is how hazard handling was tracked as it was
added (11/16 → 15/16 → 16/16 → 18/18).

**End-to-end bootloader test.** Acts as the host, sending a program bit by bit at real baud
timing, then decodes the serial output as a terminal would.

**Official ISA suite.** 38 rv32ui tests from `riscv-tests`, built against a custom test
environment that reports pass/fail over UART, run on hardware.

```
> python tests/run_tests.py COM5 tests/tests/
  ...
  38 passed, 0 failed, 0 no response
```

## Building and running

Source-only — Vivado's generated files are not committed.

1. Regenerate the project (Vivado Tcl console):
   ```
   cd <path-to-repo>
   source scripts/build.tcl
   ```
2. Set `top` as the design top, generate a bitstream, program the board.
3. Send a program:
   ```
   pip install pyserial
   python scripts/send_program.py COM5 programs/hello_test.hex
   ```

LD2 indicates the bootloader is waiting, LD3 that the core is running, LD4 that the MMCM
has locked.

### Building the ISA test suite

Needs the RISC-V GNU toolchain (WSL on Windows):

```
cd tests
./build_tests.sh ~/riscv-tests
python run_tests.py COM5 tests/
```

### Notes

**UART pins.** Digilent's master XDC names them from the **USB bridge's** perspective:
`uart_rxd_out` (R12) is the bridge's receive line — where the **FPGA transmits** — and
`uart_txd_in` (V12) is where the **FPGA receives**. Easy to get backwards.

**MMCM parameters.** `CLKFBOUT_MULT_F` must be a multiple of 0.125 and the VCO must stay
within 600–1200 MHz. `CLK_FREQ` in `top.sv` must match the actual clock or UART baud
timing breaks.

**Hex file paths.** The `$readmemh` calls in the testbenches use absolute paths and must be
edited to match your checkout location.

## License

MIT — see [LICENSE](LICENSE).
