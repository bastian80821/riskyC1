# riscyC1 — A RISC-V RV32I Core on FPGA

A RISC-V RV32I processor written from scratch in SystemVerilog, built module by module
with a self-checking testbench for every component. Target board: **Digilent Arty S7-50**
(Xilinx Spartan-7 XC7S50). Toolchain: **Vivado**.

This repository documents the full journey — from first board bring-up to a working
processor. The day-by-day reasoning, design decisions, and bugs hit along the way are
recorded in the [build log](docs/devlog.md).

## Status

| Milestone | State |
|---|---|
| Board bring-up (blink) | Done |
| Register file (2R1W, x0 hardwired) | Done |
| ALU (10 RV32I ops) | Done |
| Immediate generator (I/S/B/U/J) | Done |
| Instruction decoder | Done |
| Single-cycle datapath | Done |
| Conditional branches (all 6) | Done |
| Jumps (JAL / JALR) | Done |
| Data memory (LW / SW) | Done |
| LUI / AUIPC | Done |
| Programs loaded from hex files | Done |
| Self-checking regression suite | Done |
| Byte/halfword loads and stores | Planned |
| 5-stage pipeline + hazard/forwarding | Next |
| Branch prediction + benchmarks (Dhrystone/CoreMark) | Planned |
| Verification: riscv-tests, Spike co-simulation | Planned |
| UART + on-hardware demo (fmax / utilization numbers) | Planned |

## Instruction support

Currently implemented: R-type ALU ops (add, sub, and, or, xor, sll, srl, sra, slt, sltu),
I-type immediate ops, all six conditional branches (beq, bne, blt, bge, bltu, bgeu),
JAL/JALR, LW/SW, LUI/AUIPC.

Not yet implemented: byte and halfword memory access (lb, lbu, lh, lhu, sb, sh), CSRs,
traps/interrupts, the M extension.

## Design

A single-cycle datapath in a Harvard configuration (separate instruction and data
memories, so an instruction fetch and a data access can occur in the same cycle):

```
pc -> imem -> decoder -> register file -> [operand mux] -> alu -> [writeback mux] -> register file
                      -> imm_gen                                -> dmem
```

Control flow is a 3-way mux on the PC input: `pc+4`, `pc+imm` (taken branches and JAL), or
`rs1+imm` (JALR). Writeback is a 5-way mux: ALU result, memory data, `pc+4` (jumps), the
immediate (LUI), or `pc+imm` (AUIPC). Branch conditions come from a dedicated comparator
rather than the ALU, so the branch decision is decoupled from ALU computation.

```
rtl/
  pc.sv              Program counter
  imem.sv            Instruction memory (loads a hex program)
  dmem.sv            Data memory
  decoder.sv         Instruction decoder + control signal generation
  register_file.sv   32x32 register file (2 read, 1 write; x0 hardwired to 0)
  imm_gen.sv         Immediate generator (I/S/B/U/J formats)
  alu.sv             ALU (10 RV32I operations)
  core.sv            Top-level datapath
  blink.sv           Board bring-up test
tb/                  Self-checking testbench per module, plus a core regression suite
programs/            Test programs as hex files
constraints/         Minimal per-project XDC for the Arty S7-50
boards/              Pristine Digilent master XDC (reference only)
scripts/             build.tcl - regenerates the Vivado project from source
docs/                Build log
```

## Verification

Every module has a self-checking testbench that reports PASS/FAIL and targets edge cases
(sign-extension, funct7 decode, signed vs unsigned comparison, x0 handling).

`tb/core_tb.sv` is a **regression suite**: it loads each program in `programs/`, runs it,
and asserts on the resulting register and memory state. 16 checks across 5 programs
covering ALU ops, store/load round trip, branches, function call/return, and LUI/AUIPC.

## Building

Source-only — Vivado's generated files are not committed. Regenerate the project:

1. In Vivado's Tcl console:
   ```
   cd <path-to-repo>
   source scripts/build.tcl
   ```
2. Run synthesis, implementation, and generate bitstream — or run a testbench via
   Run Simulation (set the desired `*_tb` as simulation top).

### Known limitation: hex file paths

The `$readmemh` calls in `rtl/imem.sv` and `tb/core_tb.sv` currently use **absolute
paths** to `programs/*.hex`, so they must be edited to match your checkout location.

Relative paths resolve against the simulator's working directory
(`build/*.sim/sim_1/behav/xsim/`), which lives inside the gitignored build folder. The
proper fix is to add the hex files to the Vivado project as simulation data files so a
bare filename resolves; this is on the list.

## License

MIT — see [LICENSE](LICENSE).
