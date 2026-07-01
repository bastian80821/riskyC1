# riscyC1 — A RISC-V RV32I Core on FPGA

A RISC-V RV32I processor written from scratch in SystemVerilog, built module by
module with a self-checking testbench for every component. Target board: **Digilent
Arty S7-50** (Xilinx Spartan-7 XC7S50). Toolchain: **Vivado**.

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
| Single-cycle datapath (executes programs) | Done |
| Branches / jumps (computed PC targets) | Next |
| Data memory (loads / stores) | Planned |
| Load program from hex file (readmemh) | Planned |
| 5-stage pipeline + hazard/forwarding | Planned |
| Branch prediction + benchmarks (Dhrystone/CoreMark) | Planned |
| Verification: riscv-tests, CocoTB, Spike co-sim | Planned |

## Design

A single-cycle datapath: the program counter feeds instruction memory (fetch), the
decoder splits the instruction and generates control signals, the register file reads
the source operands, a mux selects the ALU's second operand (register or immediate),
the ALU computes, and the result writes back to the register file — all in one cycle.

```
rtl/
  pc.sv             Program counter
  imem.sv           Instruction memory
  decoder.sv        Instruction decoder + control
  register_file.sv  32x32 register file (2R1W)
  imm_gen.sv        Immediate generator (5 formats)
  alu.sv            ALU (10 RV32I operations)
  core.sv           Top-level datapath (wires it all together)
  blink.sv          Board bring-up test
tb/                 Self-checking testbench per module
```

Every module has a self-checking testbench in `tb/` that reports PASS/FAIL and
exercises edge cases (sign-extension, funct7 decode, x0 handling, etc.).

## Building

Source-only — Vivado's generated files are not committed. Regenerate the project:

1. In Vivado's Tcl console:
   ```
   cd <path-to-repo>
   source scripts/build.tcl
   ```
2. Run synthesis, implementation, and generate bitstream — or run a module's
   testbench via Run Simulation (set the desired *_tb as simulation top).

## License

MIT — see [LICENSE](LICENSE).
