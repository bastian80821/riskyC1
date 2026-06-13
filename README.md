# riscyC1 — A RISC-V RV32I Core on FPGA

A pipelined RISC-V RV32I processor written in SystemVerilog, built from scratch
and verified on hardware. Target board: **Digilent Arty S7-50** (Xilinx
Spartan-7 XC7S50). Toolchain: **Vivado** (synthesis/implementation), with
simulation and ISA-compliance testing added as the core matures.

This repository documents the full journey — from first board bring-up to a
working pipelined CPU. The day-by-day reasoning, design tradeoffs, and bugs hit
along the way are recorded in the [build log](docs/devlog.md).

## Status

| Milestone | State |
|---|---|
| Board bring-up (blink) | ✅ Done |
| Single-cycle RV32I datapath | ⬜ Planned |
| 5-stage pipeline + hazard/forwarding | ⬜ Planned |
| Memory + UART + CSRs | ⬜ Planned |
| Branch prediction + benchmarks (Dhrystone/CoreMark) | ⬜ Planned |
| Verification: riscv-tests, CocoTB, Spike co-sim | ⬜ Planned |

## Repository layout

```
rtl/           SystemVerilog source (the design)
tb/            Testbenches (the verification)
sim/           Simulation scripts and output
constraints/   Minimal per-project XDC for the Arty S7-50
boards/        Pristine Digilent master XDC (reference only)
scripts/       build.tcl — regenerates the Vivado project from source
docs/          Build log, diagrams, and notes
```

## Building

This repo is **source-only** — Vivado's generated files are intentionally not
committed. To build, regenerate the project from source:

1. Open Vivado, then in the Tcl console run:
   ```
   cd <path-to-repo>
   source scripts/build.tcl
   ```
   This creates the project, adds the RTL and constraints, and targets the
   correct part (`xc7s50csga324-1`).
2. Run synthesis → implementation → generate bitstream.
3. Open Hardware Manager, connect the board, and program the device.

## Why source-only?

Everything Vivado generates (`.runs/`, `.cache/`, checkpoints, logs) is
regenerable from the RTL, constraints, and `build.tcl`. Committing only
human-written source keeps the history clean and the repo small.

## License

MIT — see [LICENSE](LICENSE).
