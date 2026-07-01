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

---

## Day 3 — ALU

**Goal:** build the RV32I arithmetic/logic unit — the compute engine the register
file feeds into — and verify all ten operations in simulation.

### What I learned

- The ALU is **purely combinational**: two operands and a control code in, a result
  out, no clock and no state. Built with a single `always_comb` + `case` block,
  which acts as a big multiplexer selecting which computed result reaches the output.
- **The 10 operations are not arbitrary** — they are the minimal set the RV32I base
  integer instructions need: ADD (also used for memory-address and branch-target
  calculation), SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU. Loads, stores, branches,
  and jumps reuse these (a branch compares with SUB/SLT, a load computes its address
  with ADD). Multiply/divide are absent because they belong to the optional M
  extension.
- **Op encoding:** 10 operations need 4 control bits (2^4 = 16 ≥ 10). Encoded as
  named `localparam`s (`ALU_ADD` etc.) instead of magic numbers — readable and
  decouples the names from the chosen values.
- **Signed vs unsigned shows up twice, and it matters:**
  - SRL (logical right shift) fills vacated bits with 0; SRA (arithmetic) preserves
    the sign by filling with the sign bit. SRA requires both `$signed(a)` and the
    `>>>` operator — `>>>` alone on an unsigned operand does not sign-extend.
  - SLT (signed) and SLTU (unsigned) compare the same bits differently: `0xFFFFFFFF`
    is −1 signed but ~4.29e9 unsigned, so SLT vs SLTU give opposite answers. Default
    `logic` comparison is unsigned, so SLT needs `$signed()` on both operands.
- **Shift amount is `b[4:0]`** (low 5 bits) for all three shifts, because a 32-bit
  value can only meaningfully shift by 0–31.
- Instruction sets are extensible: new ops can be added as ALU case arms, full custom
  instructions via the decoder, or whole standard extensions (M, F). ML acceleration
  is more likely a **separate parallel accelerator** (systolic array of MAC units)
  attached as a coprocessor than just extra ALU ops — same SystemVerilog/verification
  skills, bigger structure.

### Verification

Self-checking testbench (combinational, so no clock/edge discipline — just drive
inputs, `#1` to settle, compare). All ten operations pass, including the two edge-case
pairs that actually prove correctness:
- SRA vs SRL on `0xFFFFFFF0`: `0xFFFFFFFF` (sign-filled) vs `0x0FFFFFFF` (zero-filled).
- SLT vs SLTU on `0xFFFFFFFF` < `1`: `1` (signed, −1<1) vs `0` (unsigned, huge≥1).


---

## Day 4 — Immediate Generator

**Goal:** build the unit that extracts the immediate constant baked into an
instruction, reassembles its scattered bits, and sign-extends to 32 bits.

### What I learned

- Combinational, like the ALU: 32-bit instruction + a format-select code in, a
  32-bit immediate out. Built with `always_comb` + `case`, one arm per format.
- **Five immediate formats** (I, S, B, U, J — R-type has no immediate). RISC-V keeps
  the register fields (rs1/rs2/rd) in fixed positions across all formats for simpler
  decode hardware; the cost is that the immediate bits get scattered into whatever
  positions are left, differently per format. The generator un-scrambles them.
- **`inst[31]` is the sign bit in every signed format** — placed there deliberately
  so sign-extension hardware is uniform.
- Built immediates with concatenation `{}` (glue scattered slices in order, MSB
  first) and sign-extension via replication `{N{inst[31]}}`, where N = 32 − (imm
  width). The bit-counting rule: **every concatenation must total exactly 32 bits.**
- B and J: the top immediate bit equals the sign bit, so `inst[31]` plays two roles
  (replicated for sign-extension AND placed as the explicit top bit). Collapsing
  them gives the same value only because the bits are adjacent — but writing it
  explicitly matches the spec and is more honest/readable.

### Bugs hit & fixed

- **S-type sign-extension off by one:** used `{19{inst[31]}}` instead of `{20{}}`
  (S immediate is 12 bits → needs 20 sign bits, not 19). Symptom was telling: the
  negative S test gave `0x7FFFFFFE` instead of `0xFFFFFFFE` — wrong in *only* the top
  bit, the signature of a too-short sign-extension. The positive S test passed and
  hid it, because a positive immediate has a 0 in the sign bit. Confirms why every
  format needs a **negative** test case — only a negative value exercises sign-
  extension.
- U-type: first wrote `"000000000000"` (a string literal = ASCII codes) instead of
  `12'b0` (a sized literal). Strings are not bit vectors.

### Verification

Self-checking testbench, each format tested with a positive and a negative
immediate, plus U. Test instructions crafted by working backwards: pick the target
immediate, place its bits into the positions that format dictates. All 9 pass.

---

## Day 5 — Instruction Decoder

**Goal:** build the decoder — the unit that reads a 32-bit instruction and produces
the control signals that drive the register file, ALU, and immediate generator. This
is the piece that ties the three existing modules together.

### What I learned

- The decoder does two jobs: **field extraction** (pure bit-slicing of the
  fixed-position fields) and **control generation** (deciding what every other module
  should do). Combinational — instruction in, control signals out.
- **Fixed fields, always in the same positions** (this is what the immediate
  scrambling bought us): `opcode=inst[6:0]`, `rd=inst[11:7]`, `funct3=inst[14:12]`,
  `rs1=inst[19:15]`, `rs2=inst[24:20]`, `funct7=inst[31:25]`. Extracted with simple
  `assign`s.
- **Control signals generated:** `reg_write` (write the destination register?),
  `alu_src` (ALU 2nd operand from rs2 or immediate?), `imm_sel` (which immediate
  format), `alu_op` (which ALU operation).
- **The two signals that test understanding of what an instruction *does*:**
  - `reg_write = 0` for **store and branch** — they don't produce a register result
    (store writes memory; branch only decides whether to jump). Everything else writes.
  - `alu_src = 0` (register) for R-type and branch (operate on two registers);
    `= 1` (immediate) for everything that folds in a constant (I-ALU, load, store).
- **`alu_src` polarity is a chosen convention** (0=register, 1=immediate), not a law —
  it just has to match the datapath mux that obeys it.
- **funct3/funct7 sub-decode for `alu_op`:** opcode gives the instruction class, but
  funct3 (and funct7 for two cases) picks the exact ALU op. `funct7[5]` distinguishes
  ADD/SUB and SRL/SRA (1 = the SUB/arithmetic variant). Done with a nested `case(func3)`.
- **R-type vs I-ALU decode differ in two spots** (don't blind-copy): I-type `funct3=000`
  is always ADD (no "subtract immediate" exists), and for shift-immediates the upper
  immediate bits act as a funct7-like selector for SRLI/SRAI.

### Design pattern reinforced

Set **defaults for every control signal at the top of the `always_comb`**, before the
`case`. Each opcode arm then overrides only what differs. Prevents inferred latches and
keeps each arm short.

### Bugs hit & fixed

- LUI initially decoded as I-format (`imm_sel=I`) — it's **U-format**. The first two
  control signals look like an I-ALU instruction, but the immediate is encoded
  completely differently (upper 20 bits), so it needed `imm_sel=U`.
- SRL/SRA ternary polarity inverted relative to the (correct) ADD/SUB line — the two
  `funct7[5]` ternaries must have the same polarity (1 = special variant). Caught by
  comparing against the working ADD/SUB arm.

### Verification

Self-checking testbench feeding 12 real assembled instructions, checking all four
control signals each. Deliberately targets the bug-prone spots: add-vs-sub and
srl-vs-sra (prove the funct7 decode), srai (I-type shift funct7), and sw/beq (prove
reg_write correctly drops to 0). All pass.

### Status

All four datapath building blocks done and verified: register file, ALU, immediate
generator, decoder.

---

## Day 6 — Single-Cycle Core (Integration)

**Goal:** wire the four building blocks (register file, ALU, immediate generator,
decoder) plus two new modules (program counter, instruction memory) into a top-level
`core` that fetches and executes a real program end to end.

### New modules written

- **Program counter (`pc`)** — my first sequential module since the register file.
  Holds the current instruction address; on each clock edge it either resets to 0 or
  advances by 4. Key concepts: it is `always_ff` (not `always_comb`) because it holds
  state across cycles, and it uses a **synchronous reset** (checked inside the clocked
  block, so it takes effect on the clock edge). Advances by **4**, not 1, because
  RV32I instructions are 4 bytes and memory is byte-addressed.
- **Instruction memory (`imem`)** — read-only, combinational lookup: address in,
  instruction out. Preloaded with a hand-assembled 4-instruction test program via an
  `initial` block (scaffolding — will later move to `$readmemh` from a hex file so the
  core can run arbitrary assembled programs, then eventually a runtime loader).
  - **Word vs byte addressing:** the PC counts in bytes (0, 4, 8, 12) but the memory
    array is indexed by word (0, 1, 2, 3). Indexing with `addr[9:2]` drops the low 2
    bits = divide by 4 = the byte-address → word-index conversion.

### Integration (the `core` top module)

Pure connection work — instantiate all six modules and wire outputs to inputs with
internal `logic` wires. The datapath flow: PC → imem (fetch) → decoder + register file
(decode/read) → alu_src mux → ALU (execute) → back to register file write port
(writeback). The mux (`assign alu_b = alu_src ? imm : rs2_data;`) picks the ALU's
second operand: immediate or rs2, per the decoder's `alu_src`.

Method takeaway: derive the wire list by walking every sub-module's ports — each port
either connects to a core port (clk/rst) or to an internal wire, and two connected
ports share one wire. Ports connect by name even when the two sides are named
differently (e.g. decoder `reg_write` → register file `rd_we`).

### Bugs hit & fixed

- **`clc` vs `clk` typo** (again) in the core's clock port and two instantiations —
  same one-character class of bug as the Day 1 XDC cascade. Port names must match the
  sub-module's declaration exactly.
- **Reset stuck high:** first run showed `rst` asserted for the whole simulation, so
  the PC never advanced past instruction 0 — only the combinational decode of the
  first instruction was visible, no writes ever happened. Cause was the testbench not
  deasserting reset. Fix: ensure the testbench drives `rst = 1` briefly then `rst = 0`
  to release. Lesson: a PC frozen at 0 with a solid-high reset is the signature of a
  reset that never releases.

### Verification

Confirmed in simulation: `pc_addr` steps 0 → 4 → 8 → C; each instruction fetches and
decodes correctly; `alu_src` flips 1→1→0→0 (immediate for the addis, register for
add/sub); `alu_op` goes 0→0→0→1 (ADD, ADD, ADD, SUB); and `alu_result` produces
**5, 3, 8, 2** — the correct program output.

Notes: immediate garbage on the R-type instructions is harmless because `alu_src=0`
makes the mux ignore it (a "wrong value that doesn't matter because it isn't selected").
`XXXXXXXX` after the 4th instruction is just execution running past the loaded program
into uninitialized memory.

### Status

**Working single-cycle RV32I core** — fetches, decodes, reads registers, executes in
the ALU, and writes back, producing correct results for a real instruction sequence.

### Next

Extend instruction support (branches/jumps need the PC to take a computed target, not
just +4; loads/stores need a data memory), then move toward pipelining. Also migrate
`imem` from a hardcoded program to `$readmemh` so the core can run assembled programs
and, eventually, the official riscv-tests suite.

