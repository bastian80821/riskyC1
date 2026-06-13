# Build Log — riscyC1

A running record of what was built, why each decision was made, and the bugs hit
and fixed along the way. Newest entries at the bottom.

---

## Day 1 — Board bring-up: blinking the LEDs

**Goal:** confirm the full toolchain path (RTL → synthesis → implementation →
bitstream → hardware) by getting an LED to blink on the Arty S7-50. This
de-risks everything before any real CPU work starts.

### What I learned

**The build flow has three distinct stages.**
- *Synthesis* translates RTL into a technology-mapped netlist of FPGA primitives
  (flip-flops, LUTs, adders, comparators). It decides *what logic exists*, not
  where it sits on the chip.
- *Implementation* does *place* (assign each netlist element to a physical site
  on the die) and *route* (program the interconnect to wire them together),
  optimizing to meet timing. This is the compute-heavy step.
- *Bitstream generation* serializes the placed-and-routed design into the binary
  the FPGA loads to configure itself. The configuration is volatile — it's held
  in SRAM and lost on power-off (reloaded from flash on boot).

**Clocks on the Arty S7-50.** The board has multiple clock sources. The 12 MHz
oscillator (pin F14) is the general-purpose user clock for the fabric; the
100 MHz source (pin R2) is tied to the DDR3 memory and uses the SSTL135 I/O
standard, so it is *not* a general-purpose logic clock. The 12 MHz is just a
*source* — faster fabric clocks can be synthesized from it later using the
PLL/MMCM. I am not stuck at 12 MHz for the core.

**The blink itself is a frequency divider.** At 12 MHz, toggling an LED every
clock edge would be a 6 MHz flicker — invisible. A 23-bit counter divides the
clock down: count 6,000,000 cycles (0.5 s) then toggle → ~1 Hz blink. 23 bits
because 2^23 = 8.4M is the smallest power of two above 6M.

**Constraints (XDC).** The XDC binds the design's logical ports to physical
package pins and declares the clock(s) for timing analysis. It is the
board-specific layer that keeps the RTL itself portable — move to a different
board and only the XDC changes.
- Best practice: keep the Digilent master XDC pristine as a reference, and copy
  only the needed lines into a minimal per-project XDC.
- Design signal names are canonical: rename the master XDC's *placeholder* port
  names (e.g. `CLK12MHZ`) to match the design's own names (`clk`), not the
  reverse. The constraint adapts to the design.

**SystemVerilog vs Verilog.** `logic`, `always_ff`, and the `'0` fill literal are
SystemVerilog. Vivado parses a `.v` file as plain Verilog and rejects `'0`. The
file must be `.sv` (or have its file type set to SystemVerilog) for these to work.

### Bugs hit & fixed

1. **`'0` failed synthesis** — `[Synth 8-11587] invalid assignment pattern`. Cause:
   the file was `blink.v`, parsed as Verilog, which has no `'0` literal. Fix: set
   the file type to SystemVerilog (or rename to `.sv`).
2. **Wrong bus declaration** — wrote `output logic led[3:0]`, which is an *unpacked
   array* (four separate scalars), not a bus. Fix: `output logic [3:0] led` —
   the dimension goes *before* the name for a packed vector.
3. **Typo cascade** — `clc` instead of `clk` in the XDC produced 3 errors + 2
   critical warnings (unmatched port → empty `set_property` → no clock created →
   downstream DRC failures at bitstream). Lesson: when a build throws many
   messages, fix the *earliest* one in the flow; the rest are often just
   consequences of it.
4. **Missing config voltage** — `[DRC CFGBVS-1]`. Added
   `set_property CFGBVS VCCO [current_design]` and
   `set_property CONFIG_VOLTAGE 3.3 [current_design]` to the XDC (3.3 V is correct
   for this board). These live in the master XDC but weren't in the copied subset.

### Result

Clean bitstream, programmed over JTAG, LD2 blinks at ~1 Hz. Toolchain path
confirmed end to end. Bus output (`led[3:0]`) wired so any of the four LEDs can
be driven, and multiple LEDs can be driven independently.

---

## Day 2 — Register File

**Goal:** build the RV32I register file, the CPU's fast 32-register scratchpad,
and verify it with a self-checking testbench in simulation.

### What I learned

- RV32I has **32 registers, each 32 bits**. Most logical to build this component
  first — nearly every instruction reads and/or writes it, so the ALU, decoder,
  and datapath all plug into it. (It is a *component*, not one of the 5 pipeline
  stages: it is read in the Decode stage and written in the Writeback stage.)

- **Structure: two read ports, one write port (2R1W).** Dictated by what a typical
  instruction needs — `add x3, x1, x2` reads two source registers (rs1, rs2) and
  writes one destination (rd) in a single cycle. So: 2 read ports + 1 write port.

- **Reads are asynchronous (combinational); writes are synchronous (clocked).**
  This asymmetry is the core idea:
  - Writes commit on the rising clock edge, gated by a write-enable, so state
    changes only at a controlled, predictable moment.
  - Reads return data immediately (address in -> data out, no clock) because the
    ALU needs the operands *within* the same cycle to compute on them.
  - Saw this directly in the waveform: stored register values change only on a
    clock edge, while read outputs follow the address instantly.

- **x0 is hardwired to zero** — always reads as 0 and can never be written. Useful
  as a free constant zero, for padding, and for discarding a result. Enforced in
  hardware two ways: return 0 on a read of address 0, and block the write when the
  destination address is 0.

- Address width is **5 bits** (`[4:0]`) because 2^5 = 32 registers; data width is
  32 bits.

- **Testbench writing.** Self-checking tests print PASS/FAIL to the Tcl console,
  far better than eyeballing waveforms. The testbench is a reusable **skeleton**:
  the clock generator, error counter, self-checking task, and summary stay fixed;
  only the DUT-specific signals, instantiation, and stimulus change per module.
  Key habit: use `!==` (4-state compare) in checks so uninitialized (X) values are
  caught, and align stimulus to clock edges (set inputs on negedge, let posedge
  capture) to avoid races.

### Bugs / gotchas

- A testbench goes in **Simulation Sources**, not Design Sources — it must never be
  synthesized (it contains `#` delays, `$display`, `initial` stimulus).
- A standalone module shows as "not used in any module" in the design hierarchy
  until something instantiates it — expected and fine. For simulation, the
  testbench becomes the top and instantiates the DUT directly.

### Result

All tests pass in XSim: write/read-back, x0-stays-zero, write-enable gating, and
independent dual-port reads. Read-async / write-sync behavior confirmed in the
waveform.

### Next

Build the ALU (combinational: two 32-bit operands + an op-select -> 32-bit result).
Writing the RTL myself from spec this time.
