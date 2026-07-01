\# riscyC1 — A RISC-V RV32I Core on FPGA



A RISC-V RV32I processor written from scratch in SystemVerilog, built module by

module with a self-checking testbench for every component. Target board: \*\*Digilent

Arty S7-50\*\* (Xilinx Spartan-7 XC7S50). Toolchain: \*\*Vivado\*\*.



This repository documents the full journey — from first board bring-up to a working

processor. The day-by-day reasoning, design decisions, and bugs hit along the way are

recorded in the \[build log](docs/devlog.md).



\## Status



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



\## Design



A single-cycle datapath: the program counter feeds instruction memory (fetch), the

decoder splits the instruction and generates control signals, the register file reads

the source operands, a mux selects the ALU's second operand (register or immediate),

the ALU computes, and the result writes back to the register file — all in one cycle.



```

rtl/

&#x20; pc.sv             Program counter

&#x20; imem.sv           Instruction memory

&#x20; decoder.sv        Instruction decoder + control

&#x20; register\_file.sv  32x32 register file (2R1W)

&#x20; imm\_gen.sv        Immediate generator (5 formats)

&#x20; alu.sv            ALU (10 RV32I operations)

&#x20; core.sv           Top-level datapath (wires it all together)

&#x20; blink.sv          Board bring-up test

tb/                 Self-checking testbench per module

```



Every module has a self-checking testbench in `tb/` that reports PASS/FAIL and

exercises edge cases (sign-extension, funct7 decode, x0 handling, etc.).



\## Building



Source-only — Vivado's generated files are not committed. Regenerate the project:



1\. In Vivado's Tcl console:

&#x20;  ```

&#x20;  cd <path-to-repo>

&#x20;  source scripts/build.tcl

&#x20;  ```

2\. Run synthesis, implementation, and generate bitstream — or run a module's

&#x20;  testbench via Run Simulation (set the desired \*\_tb as simulation top).



\## License



MIT — see \[LICENSE](LICENSE).

