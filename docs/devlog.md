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

---

## Day 7 — Conditional Branches

**Goal:** teach the core to make decisions. Until now the PC only did +4 — straight-line
code only, no loops or conditionals.

### The core idea

The PC's next value stops being "always +4" and becomes a **choice**:

```
next_pc = branch_taken ? branch_target : (pc + 4)
```

That mux is where control flow lives.

### What I built

- **Refactored `pc.sv`** into a dumb register — it now takes a `next_pc` input and just
  latches it. The "+4 or branch target" decision moved into the core. Refactored and
  re-tested *before* adding the feature, so breakage would be unambiguous.
- **Branch target adder:** `branch_target = pc_addr + imm`. RISC-V branch immediates are
  **relative offsets**, not absolute addresses — saves instruction bits and makes code
  position-independent.
- **Decoder:** new `branch` output (opcode `1100011`); `func3` finally wired to the core.
- **Dedicated branch comparator:** `br_eq`, `br_lt` (`$signed`), `br_ltu`.
- **All six branch types** decoded from `func3`.

### Six branches, three comparisons

The pairs are just inversions — `bge` is "NOT less than", `bne` is "NOT equal":

| func3 | inst | condition |
|-------|------|-----------|
| 000 | beq  | `br_eq` |
| 001 | bne  | `~br_eq` |
| 100 | blt  | `br_lt` |
| 101 | bge  | `~br_lt` |
| 110 | bltu | `br_ltu` |
| 111 | bgeu | `~br_ltu` |

### Design decision: comparator, not the ALU zero flag

First version used the ALU's zero flag (set `alu_op = SUB`; `res == 0` means equal). Works
for beq/bne, but blt/bge need a *less-than* result the zero flag can't give. Replaced it
with a dedicated comparator and deleted the zero flag:

- Branch comparison is logically distinct from ALU computation.
- In a **pipelined** design the branch decision is wanted *earlier* than the ALU result —
  decoupling now pays off later.

### `branch` must gate everything

`branch_taken = branch & branch_cond`. The **opcode** says "this is a branch"; **func3**
says "which one." Without the gate, an ordinary `addi` (also `func3 = 000`) could satisfy
the beq case and trigger a bogus jump.

### Bugs hit & fixed

1. **Duplicate `assign br_eq`** — two drivers on one signal → **X**, which propagated
   through `branch_cond` → `branch_taken` → the PC mux select → the whole design.
   *Lesson: when everything goes X at once, suspect one bad signal on a control path.*
2. **Stray breakpoint** — sim reported `Stopped at time : 0 fs` and never ran a cycle.
   *Lesson: read the Tcl console before staring at the waveform.*
3. **`branch` missing from the decoder's defaults block** → inferred latch. Every new
   control output must be defaulted.
4. **`logic branch_target[31:0]`** — packed/unpacked again. Dimension goes *before* the
   name for a bus.

### Verification

Five programs, one per branch type. The pair that actually proves correctness — same bits
(`x1 = 0xFFFFFFFF`, `x2 = 1`), opposite outcomes:

- `blt` (**signed**): −1 < 1 → **taken**
- `bltu` (**unsigned**): 4.29e9 ≥ 1 → **not taken**

That's the test that catches a broken `$signed()` cast. Also checked both directions of
beq/bne — a branch that *always* jumps would pass a taken-only test.


---

## Day 8 — Memory, File-Loaded Programs, LUI/AUIPC, and a Regression Suite

**Goal:** close out everything before the pipeline — data memory, loading programs
from files, the remaining U-type instructions, and (most importantly) an automated
test harness so pipeline work is verifiable.

### Data memory (loads / stores)

New module `dmem.sv` — structurally very close to the register file: **synchronous
write** gated by an enable, **combinational read**, word array indexed with
`addr[9:2]`.

- **The address is free:** `lw`/`sw` were already configured with `alu_src=1` and
  `alu_op=ADD`, so `alu_result` is `rs1 + imm` — the memory address. No new adder.
- **Store data comes from `rs2_data`,** bypassing the ALU entirely — in
  `sw rs2, off(rs1)`, rs1 is the base address and rs2 is the value to store.
- **Read is combinational, deliberately.** A single-cycle core needs the loaded
  value to reach the register file's write port in the same cycle. A registered
  (synchronous) read would arrive a cycle late and require a stall. Real BRAM
  prefers a registered read, which is part of why pipelined CPUs have a separate
  MEM stage — memory access genuinely takes a cycle.
- **Decoder:** added `mem_read` / `mem_write` (and to the defaults block).
  Writeback mux extended to select `mem_rdata` for loads.

### Harvard architecture

Separate `imem` and `dmem`, each with its own address port. This is what makes
single-cycle execution possible: `lw` needs to fetch an instruction and load data
in the same cycle, which one memory with one port can't do. Real systems use
unified main memory (von Neumann) but split L1 instruction/data caches — Harvard at
the core level for exactly this reason.

### Programs from hex files (`$readmemh`)

Replaced the hardcoded `initial` block in `imem` with a zero-loop plus
`$readmemh("...hex", imem)`. Programs now live in `programs/*.hex`, one 32-bit hex
word per line, `//` comments allowed.

- **This is the unlock for everything downstream** — real assembled programs, ISA
  test suites, benchmarks. Xilinx also supports `$readmemh` for synthesis (it
  initializes BRAM in the bitstream), so it works on hardware too.
- **Order matters:** zero the array first, then overlay the program. `$readmemh`
  only fills as many words as the file has lines; without the zero-init, running
  past the end of the program hits X and the whole design goes undefined.
- **Known limitation:** the path in `imem.sv` is currently absolute, so the repo is
  not portable as-is. Relative paths resolve against the simulator's working
  directory (`build/*.sim/sim_1/behav/xsim/`), inside the gitignored build folder.
  Proper fix is to add the hex file to the project as a data file so a bare filename
  resolves.

### LUI / AUIPC

- **LUI** writes the 20-bit immediate into the upper bits of `rd` (lower 12 zeroed).
  The imm_gen already produces exactly this for U-format; it just needed routing to
  writeback. Exists because RV32I immediates are only 12 bits — `lui` + `addi` is the
  idiom for loading any 32-bit constant.
- **AUIPC** computes `pc + imm`, used for PC-relative addressing and (with `jalr`)
  long-range jumps.
- **Chose to add writeback mux inputs rather than route these through the ALU.** More
  explicit — each instruction's result comes from a clearly labelled source — and it
  avoided adding an operand mux on the ALU's `a` input (which AUIPC would need, since
  `a` is hardwired to `rs1_data`). Nice reuse: AUIPC's `pc + imm` is already computed
  by the `branch_target` adder, so no new hardware.
- The writeback mux is now **5-way:** `pc_plus4` (jumps), `mem_rdata` (loads), `imm`
  (LUI), `branch_target` (AUIPC), `alu_result` (everything else).

### Self-checking regression suite (the important part)

Built a real `core_tb` that runs multiple programs and asserts on the results,
printing PASS/FAIL — no waveform reading.

Two new techniques:

- **Hierarchical references** — the testbench reaches into the design to inspect and
  modify state: `dut.u_register_file.regs[3]`, `dut.u_imem.imem[i]`, `dut.pc_addr`.
  Simulation-only, and the standard way to check internals without adding debug ports.
- **A `run_program()` task** loads the program via
  `$readmemh(prog, dut.u_imem.imem)`, then clears imem/dmem/regs and cycles reset.
  This is what lets one simulation run test five different programs with no RTL edits.

**Why this matters now:** pipelining is a major restructuring of the entire datapath
and will be iterated on for weeks. Manually inspecting waveforms after every change is
slow and misses regressions. This suite turns "did I break anything?" into one command.

### Bugs hit & fixed

- **My own test was wrong before the core was.** The jump test checked "x3 stayed 0",
  but that program loops (jalr returns to addr 4, which then executes the skipped
  instruction), so x3 legitimately becomes 99 after one pass. Fixed by running exactly
  3 cycles and checking `pc == 4` instead — verifying the thing I actually care about
  (did the return land correctly) rather than a side effect of it. *Lesson: a
  self-checking test needs precision about what state, and when.*
- **Cycle counts matter per program.** Straight-line programs can overshoot harmlessly
  (they fall into zeroed memory and execute nops); looping programs must be counted
  exactly. A more robust harness would have programs signal completion rather than
  using fixed counts.
- **Trailing comma in `alu.sv`'s port list** (left over from deleting `zero_flag`)
  caused a syntax error, which made the module unresolvable — showing as
  `u_alu : xil_defaultlib.alu` with a `?` in the hierarchy. Regenerating the project
  via `build.tcl` did not fix it: project regeneration repairs lost file references,
  but can't fix a syntax error in the source. *Two different failure modes.*
- **`$readmemh` fails quietly.** A missing file gives a console warning and leaves
  memory zeroed, so the core executes nops and looks like it's running. Signature:
  `inst` is always `00000000` and the PC just marches +4. The regression suite caught
  this immediately on one test and named the file — much faster than waveform archaeology.
- **Wrong hand-assembled test instructions cost real time:** `0010a023` is
  `sw x1, 0(x1)`, not `sw x1, 0(x2)` — one hex digit in the rs1 field. Encodings are
  now generated programmatically rather than written by hand.

### Verification

Coverage: ALU ops, store + load round trip, branch taken / not-taken, jal + jalr
call/return, lui + auipc. **16 checks, all passing.**

### Status

Single-cycle core now runs the full RV32I integer datapath end to end — arithmetic
and logic, immediates, loads/stores, all six branches, jal/jalr, and LUI/AUIPC — from
file-loaded programs, guarded by an automated regression suite. Feature-complete and
regression-guarded, ready for the pipeline restructure.


---

## Day 9 — Pipelining, Step 1: Splitting the Datapath

**Goal:** convert the single-cycle core into a 5-stage pipeline. This step inserts the
pipeline registers only — no hazard handling — so the hazards show up as concrete test
failures rather than abstractions.

### Why pipeline

In the single-cycle core, the clock period must cover the *entire* path of the slowest
instruction: fetch, decode, register read, ALU, memory, writeback. Everything else sits
idle while one part works.

Cutting the datapath into five stages with registers between them means the clock only
has to cover the **slowest single stage**, and five instructions can be in flight at
once — one per stage. Much higher clock, roughly one instruction retired per cycle.

### The design work is a paper exercise

The mechanical rule: **for each stage boundary, what does everything to the right need
that is produced to the left?** Those signals need a pipeline register.

Easiest done backwards, starting from WB. Each register carries what its own stage needs
*plus* everything all later stages need — signals don't teleport, they ride the pipeline.

| Register | Contents | Notes |
|---|---|---|
| IF/ID | inst, pc_addr, pc_plus4 | smallest — control signals don't exist yet |
| ID/EX | ~19 signals | fattest — everything the decoder just produced |
| EX/MEM | 13 signals | alu_result + the writeback mux inputs/selects |
| MEM/WB | wb_data, rd, reg_write | 38 bits — the mux has collapsed 5 candidates to 1 |

### Key realisations

- **A signal is carried if and only if it is produced in one stage and consumed in a
  later one.** `imm_sel` is generated *and* used in ID, so it never enters a pipeline
  register. Everything else the decoder produces travels somewhere.
- **`reg_write` isn't one signal any more — it's four.** Five instructions are in flight,
  each needing its own copy of every control signal, so `reg_write` becomes
  `exe_reg_write` / `mem_reg_write` / `wb_reg_write`. A single "hold it until needed"
  register wouldn't work: it would be overwritten by the next instruction to decode.
  A pipeline register is a **conveyor belt**, not storage.
- **`rd` and `wb_rd` are the same signal for different instructions.** `rd` belongs to the
  instruction in ID; `wb_rd` to the one in WB, four instructions earlier. The stage prefix
  identifies *which instruction* you're talking about.
- **Two paths flow backward**, and both are where hazards come from:
  - EX → IF: `take_pc_rel`, `branch_target`, `jalr_target` reach the PC mux
  - WB → ID: the register file's write port
- **Reset clears the pipeline registers to zero**, which decodes as opcode 0 → the
  decoder's `default` case → all control signals off. That's a **bubble**. The same
  mechanism will be reused for flushing.

### Design decisions

- **Branches resolve in EX**, not ID. Resolving in ID would flush only 1 instruction
  instead of 2, but it lengthens ID's critical path (register read → comparator →
  decision → PC mux) and complicates forwarding. Chose the simpler option first;
  moving it to ID later is a measurable optimisation with a clear before/after.
- **Writeback mux resolves in MEM**, so MEM/WB carries one 32-bit result instead of five
  values plus five selects (~165 fewer flip-flops, and WB becomes trivially short). The
  tradeoff is mux delay in series with the dmem read. If MEM turns out to be the critical
  path, moving the mux to WB is the fix — WB has enormous slack. **To revisit after
  synthesis and a timing report**, rather than guessing now.
- **Operand mux resolves in EX**, the opposite call — carry `rs2_data`, `imm`, `alu_src`
  separately rather than pre-muxing in ID. Forwarding has to inject values immediately
  before the ALU, and it replaces the *register* operand, not the immediate. Pre-muxing
  would collapse them into one wire and make that impossible.

### Bug found by reasoning, not by testing

The register file is **read in ID and written in WB**. With a synchronous write and a
combinational read, an ID-stage read of a register being written that same cycle returns
the **stale** value. That fires at any dependency distance of 3 — common in real code.

Fixed by making the register file **write-first**: if a read address matches the write
address and the write is enabled, return the incoming write data instead of the stored
value. Three lines, handled once at the source for both read ports, rather than adding
comparators and mux inputs to the forwarding network later. (x0 check stays first in the
priority chain.)

Harmless to the single-cycle core, confirmed by re-running its regression suite: still
16/16.

### Result: correctly broken

Ran the regression suite against the pipelined core — **11/16 pass, 5 fail**, and every
failure is a predicted hazard:

- **`add x3, x1, x2` → x3 = 0.** The two `addi`s were still in MEM and WB when the `add`
  reached EX, so it read stale zeros. Textbook RAW data hazard.
- **`sub x4, x1, x2` → x4 = 5.** Instructive: by then `addi x1` had *just* reached WB, so
  the new write-first bypass delivered x1 = 5 correctly — but x2 was one stage behind and
  read 0. So 5 − 0 = 5. The fix works; dependency *distance* is what decides.
- **Store/load test** — same cause, operands not ready.
- **`x3 = 0x63` on the branch test.** The instruction the taken branch should have skipped
  **executed anyway** — it was already in the pipeline when the branch resolved in EX, and
  nothing flushed it. Concrete proof of the 2-instruction branch penalty.
- Tests 4 and 5 pass because those programs happen to have no back-to-back dependencies.

Also: the pipeline needs ~4 extra cycles to drain, so every test's cycle count had to
increase (6 → 12).

## Day 10 — Pipelining, Steps 2–4: Forwarding, Flushing, and a Hazard That Wasn't
 
**Goal:** finish the pipeline. Resolve the data and control hazards that Step 1
deliberately exposed, and get the pipelined core to match single-cycle behaviour.
 
### Step 2: Forwarding
 
The failing test was `add x3, x1, x2` producing 0 — when the `add` reached EX, the two
`addi`s were still in MEM and WB, so the ID-stage register read returned stale zeros.
 
**The key insight: the values already exist.** The `addi` results are sitting in the
EX/MEM and MEM/WB pipeline registers. They just haven't been written back to the register
file yet. So don't wait — route them directly to the ALU inputs, bypassing the register
file entirely.
 
Built:
- A **forwarding unit** in EX: combinational logic comparing `exe_rs1`/`exe_rs2` against
  `mem_rd` and `wb_rd`, producing two 2-bit selects.
- **Two 3-way muxes** between the ID/EX register and the ALU — one per operand.
Three conditions gate each forward, and each earns its place:
- `mem_reg_write` — only forward from an instruction that actually writes a register
  (a store or branch has meaningless data in `mem_rd`).
- `mem_rd != 0` — x0 always reads zero; forwarding a "write to x0" would corrupt it.
- `mem_rd == exe_rs1` — the actual dependency test.
**MEM takes priority over WB.** If both stages write the same register, MEM holds the
*newer* value. Getting this backwards produces stale-but-plausible results — the worst
kind of bug.
 
**Forward `mem_wb_data`, not `mem_alu_result`.** That's the writeback mux output, already
resolved to what the instruction actually produces — the ALU result for arithmetic, but
`pc+4` for `jal`, the immediate for `lui`. Forwarding the raw ALU result would break
`jal x1, target` followed by a use of the return address.
 
**Two operands need two independent muxes**, because either can be the stale one, and both
can be stale simultaneously from *different* stages — which is exactly the failing test
(`x1` forwarded from WB, `x2` from MEM, same cycle).
 
**Store data also needs forwarding.** `add x5, ...` followed by `sw x5, 0(x6)` would store
a stale value if the EX/MEM register captured the raw `exe_rs2_data`. Fixed by capturing
`data_fwd_b` (the forwarding mux output) instead — note *not* `alu_b`, which may have
selected the immediate.
 
Result: 11/16 → 15/16. All data hazards resolved.
 
### Step 4: Branch flushing
 
The remaining failure: `x3 = 0x63` on the branch test — the instruction the taken branch
should have skipped **executed anyway**.
 
Because branches resolve in EX, two instructions behind the branch have already been
fetched by the time the outcome is known (one in ID, one in IF). The PC redirect works —
the *target* is fetched correctly — but those two speculative instructions are already
inside the machine.
 
**The fix reuses the reset path.** A pipeline register cleared to zero holds instruction
`0x00000000`, which decodes as opcode 0, hits the decoder's `default` case, and produces
all-zero control signals. That's a **bubble** — an instruction that does nothing. So:
 
```
assign flush = take_pc_rel | exe_jmpr;
...
if (rst || flush) begin ... end     // in the IF/ID and ID/EX banks
```
 
Six lines total. No new hardware — just a second reason to trigger something that already
existed.
 
**Only two registers get flushed**, not the whole pipeline. Instructions in EX/MEM and
MEM/WB are *older* than the branch and are legitimately in flight — killing them would
discard correct results. The pipeline holds instructions in program order, so "everything
after the branch" is precisely the two slots behind it.
 
This is the 2-cycle branch penalty, and it's the direct cost of resolving in EX rather
than ID. It's also the seed of branch prediction: same flush machinery, triggered less
often because the guess is smarter than "always not-taken."
 
Result: **16/16**. Pipelined core matches single-cycle behaviour on all five programs.
 
### Step 3: the load-use hazard that isn't (this time)
 
The textbook load-use case:
 
```
lw  x3, 0(x1)
add x4, x3, x5     # needs x3 in EX
```
 
Forwarding classically *cannot* fix this — load data isn't available until the end of MEM,
one cycle after the dependent instruction needs it in EX, and data can't move backward in
time. It requires a stall.
 
Wrote a test program for it expecting a failure. **It passed.**
 
The reason is architectural, not luck: **dmem's read is combinational** and **the writeback
mux resolves in MEM**, so `mem_wb_data` already contains the loaded value *within* the MEM
cycle — and that's exactly what the forwarding path reads. The value is available in time,
so no stall is needed. In the textbook design, memory is modelled with a synchronous read,
which is what creates the hazard.
 
**Decision: leave it, and document the tradeoff.** The cost is real — the MEM critical path
is now `alu_result → dmem combinational read → 5-way writeback mux → forwarding mux → ALU
input`, a long chain crossing a stage boundary, and a likely candidate for the design's
critical path at synthesis. A combinational-read memory also won't infer a true BRAM
(at 256 words it becomes distributed LUT RAM), so it doesn't scale.
 
**Kept the test as a guard.** It passes now, with a comment stating the assumption and
exactly what would break it: if dmem is ever changed to a registered read, or the writeback
mux moves to WB, this test fails immediately and a load-use stall becomes necessary. Much
better than discovering it later as a mysterious wrong answer.
 
### Status
 
**Working 5-stage pipelined RV32I core** — forwarding, branch flushing, write-first
register file. **18/18 regression checks across 6 programs**, matching the single-cycle
core's behaviour.
 
Four backward-flowing paths in the design, and every one corresponds to a hazard:
- EX → IF (control flow / branch redirect)
- WB → ID (register file write port)
- MEM → EX and WB → EX (forwarding)

---

## Day 11 — UART: Making the Core Talk

**Goal:** give the core real I/O. A processor that can only be observed by reaching into
its registers in simulation isn't much of a computer — it needs to be able to output
something.

Also: synthesis had been reporting nonsense (274 LUTs for a whole pipelined core), and
diagnosing *why* turned out to be as instructive as the UART itself.

### Why synthesis numbers were meaningless

Two separate problems, which I'd been conflating:

**Pruning.** `core_pipelined` had no output ports — only `clk` and `rst` in. Synthesis
deletes anything that can't affect a pin, so with nothing observable the entire netlist
was dead logic. Utilization came back *empty*. This doesn't happen in simulation because
the testbench reaches inside with hierarchical references; synthesis has no equivalent.

**Specialization.** More fundamental: `$readmemh` bakes the program into imem at synthesis
time, so Vivado knows exactly which instructions exist. It constant-folds through the
decoder, deletes ALU operations never used, removes branch logic that never fires. What
gets built isn't a processor — it's *a circuit that computes the results of that one
program*. imem itself became a 257-input constant mux rather than a memory.

Adding debug outputs fixed pruning (274 LUTs instead of 0). Adding a real UART output pin
changed it to 298. Adding `rom_style = "block"` to force BRAM inference changed nothing —
a **combinational** memory read can't infer block RAM, since real BRAMs have a registered
read port. So the attribute was silently ignored, which is the earlier combinational-read
decision coming due in a second way.

**Conclusion: honest numbers require the program to be unknown at synthesis time.** That
means a write port on imem fed from outside — i.e. UART RX and a bootloader. Deferred, but
now understood rather than guessed at. Nothing else will fix it.

### UART transmitter

New module `uart_tx.sv` — the first **finite state machine** in the project. Everything
before this was combinational logic or plain registers.

The protocol: one wire, no shared clock. Both ends agree a baud rate and count time
locally. Line idles high; a falling edge is the start bit; 8 data bits **LSB first**; a
stop bit returns it high. Ten bit-times per byte.

At 100 MHz and 115200 baud that's **868 clock cycles per bit** — so one byte takes ~8,700
cycles. The core executes ~8,700 instructions in that time. I/O is *slow*, and that gap is
not a flaw in the design; it's the nature of talking to the outside world.

Four states (IDLE / START / DATA / STOP), a bit-time counter, a bit index, and a shift
register. `tx_busy = (state != IDLE)`.

**Why latch `tx_data` into a shift register:** because `tx_data` comes from
`mem_rs2_data`, a *pipeline* signal that changes every single cycle as instructions flow
through MEM. The byte is only present for the one cycle the store is in MEM. Pipeline
signals are one-cycle snapshots, not stored values — the same fact that motivates the
pipeline registers themselves.

Verified with a testbench that implements a **UART receiver**: it watches the `tx` pin the
way a terminal would — waits for the start edge, samples the *middle* of each bit window
(maximum tolerance to clock drift), reassembles LSB-first. Tests the protocol, not the
implementation. All six bytes pass including `0x00`, `0xFF`, `0xA5`.

Ran it with `CLK_FREQ`/`BAUD_RATE` overridden to give 10 cycles per bit instead of 868 —
which is exactly why those are parameters rather than constants.

### Memory-mapped I/O

The core talks to the UART through **addresses that aren't memory**:

- `0x1000` — write a byte here → transmit
- `0x1004` — read here → returns the busy flag

An address decoder in MEM does the routing:

```
uart_sel      = (mem_alu_result[31:12] != 0)      // >= 0x1000 -> device
dmem_we       = mem_mem_write & ~uart_sel          // normal store
tx_start      = mem_mem_write &  uart_sel          // device store
mem_read_data = uart_sel ? {31'd0, tx_busy} : mem_rdata
```

One comparator and a few gates. The pipeline has no idea any of this exists — it just
executes `sw` and `lw`.

`uart_tx_pin` becomes a genuine top-level output, which is what makes the design
observable to synthesis.

### The core does not wait — software does

There's no hardware stall for I/O. `tx_start` is a one-cycle pulse; if the UART is busy it
is silently ignored and the byte is dropped. So software must poll:

```
wait:  lw   x4, 4(x2)      # read busy flag
       bne  x4, x0, wait
       sw   x1, 0(x2)      # now safe to send
```

The core runs that loop at full speed for ~8,700 cycles, doing useless work. That's
**busy-waiting**, and it's how all simple embedded I/O works. Interrupts or a FIFO would
avoid the waste; neither is implemented.

Note the loop polls **before** sending, not after — the busy flag isn't valid until a
cycle after a store lands in MEM.

### Bug found: the branch comparator wasn't forwarded

The poll loop exposed a real hole in the forwarding network. The `bne` depends on the
immediately-preceding `lw`, but the branch comparator read the **raw** registered values:

```
assign br_eq = (exe_rs1_data == exe_rs2_data);     // stale!
```

so it compared data from before the load completed, and the branch resolved wrongly —
the next store fired while the UART was still busy, dropping the byte. Fixed by comparing
the **forwarded** operands (`data_fwd_a` / `data_fwd_b`), and the same for the JALR target
adder, which also read `exe_rs1_data` directly.

**The 18-check regression suite missed this** — no existing test had a branch depending on
the instruction immediately before it. Worth adding one.

### Result

Wrote a program that prints `"HI\n"`: sets up the UART base address with `lui`, then for
each character loads the immediate, polls the busy flag, and stores to `0x1000`.

The integration testbench decodes the serial line and traces every memory-stage access.
Output:

```
Received 3 bytes:
  [0] 0x48   'H'
  [1] 0x49   'I'
  [2] 0x0a   newline
===== PASS =====
```

The trace shows the whole mechanism: the poll loop spinning at one PC with `busy=1` for
thousands of cycles, then `busy=0`, the branch falling through, and the store firing with
the next character. Software waiting on hardware, correctly.

One debugging note: the first run appeared to hang. It hadn't — three bytes plus polling
needs ~26,000 cycles, and the simulation was only running 1,000 ns (100 cycles). Not every
stuck-looking loop is a bug.

### Status

Pipelined core with working memory-mapped serial output. It fetches and executes a real
program with loops and branches, forwards a load result into a branch comparison, routes
stores to a device instead of memory, and serializes bytes at correct baud timing while
software polls for readiness. That is a computer with I/O.

---

## Day 12 — Runtime Program Loading, Real Numbers, and Hardware Bring-Up

**Goal:** close the loop. Make programs loadable at runtime over serial, get honest
synthesis numbers, and run the core on the actual FPGA.

### UART receiver

`uart_rx.sv` mirrors the transmitter but is harder in one specific way: **TX sets its own
timing; RX has to find it.** On the falling start-bit edge it waits *half* a bit-time,
re-checks the line is still low (rejecting glitches), then samples every bit-time from
there — landing in the **middle** of each bit window, which gives maximum tolerance to
clock drift between two independently-clocked machines.

It also has a **two-stage synchroniser** on the `rx` input. That signal arrives from
outside the FPGA, asynchronous to the local clock; sampling it directly risks
metastability, where a flip-flop caught mid-transition outputs an undefined level that
propagates into the design. Two flops in series make that vanishingly unlikely. Standard
practice for *any* asynchronous external input.

### Bootloader

A hardware FSM rather than a software one — contained, and no bootstrapping problem.

Protocol, little-endian: 4 bytes of word count N, then N words of program. A length
header rather than a terminator, because no instruction can be mistaken for an end marker.

**The arbitration is trivially solved**: `core_rst = rst_btn | ~core_run` holds the core
in reset for the entire load, so the bootloader owns imem's write port and the core owns
its read port, never at the same time. No arbiter needed.

`imem` gains a write port and therefore a clock — it was purely combinational before,
because read-only memory has no state changes during operation.

### The point of all this: honest synthesis numbers

Previously `$readmemh` baked the program in at synthesis time, so Vivado knew exactly
which instructions existed and **specialised the design** — constant-folding through the
decoder, deleting unused ALU operations, removing branch logic that never fires. What got
built was *a circuit that computes one program's output*, not a processor.

With a write port fed from a top-level input, the contents are unknowable at synthesis.
Vivado has no choice but to build a general-purpose core.

| | Specialised (before) | General (after) |
|---|---|---|
| LUT | 274 | **1120** (3.44%) |
| FF | 187 | **699** (1.07%) |
| BRAM | 0 | **0.5** |

A 4x jump, and the FF count now matches the pipeline-register estimate made when the
stage contents were first listed — a good confirmation the design is what it's supposed
to be. imem also finally infers as **block RAM** now that it has a proper write port.

### Timing: ~94 MHz

Method: deliberately **over-constrain** to find the ceiling. Set `-period 10.000` (100
MHz), implement, and read Worst Negative Slack:

```
WNS = -0.616 ns  ->  required period 10.616 ns  ->  fmax ~94.2 MHz
```

Confirmed by re-running at 10.616 ns: **WNS +0.066 ns, zero failing endpoints, all
constraints met.** Hold timing also passes (+0.035 ns), which matters — hold violations
are far harder to fix than setup ones.

### The critical path was not where I expected

Predicted: the MEM chain (dmem combinational read → 5-way writeback mux → forwarding mux
→ ALU). Actual, from the timing report — all six worst paths identical in shape:

```
From: u_core/mem_alu_result_reg[2]   (EX/MEM register)
To:   u_core/u_pc/pc_reg[29]         (the PC)
10.603 ns total = 4.380 logic + 6.223 net,  21 logic levels,  fanout 129
```

That's the **branch-redirect path**: a value in MEM, forwarded backward into EX, through
the branch comparator, the branch decision logic, the 3-way PC mux, into the PC. Created
by the fix on Day 11 that made the branch comparator use forwarded operands — necessary
for correctness, and now the bottleneck.

Notable that **net delay (6.2 ns) exceeds logic delay (4.4 ns)** — nearly 60% is wire, not
gates. Characteristic of a signal crossing physically distant parts of the chip with high
fanout. So relocating the writeback mux (the optimisation I'd been assuming) would not
help much; the fix would be **resolving branches in ID instead of EX**, which shortens
this path *and* halves the branch penalty. Deferred as a measured optimisation with
before/after on both fmax and IPC.

### Hardware bring-up

Ran at the board's native 12 MHz rather than adding an MMCM — fmax is a property of the
timing analysis, not of the clock actually used, so the 94 MHz figure stands regardless.

Bugs hit:

- **UART pins swapped.** Digilent's master XDC names the UART pins **from the USB bridge's
  perspective**: `uart_rxd_out` (R12) is the bridge's *receive* line, i.e. where the
  **FPGA transmits**; `uart_txd_in` (V12) is where the **FPGA receives**. I had assigned
  them by the obvious-looking reading and got both backwards, so the bootloader never saw
  the incoming bytes. Symptom: LD2 (loading) stayed on forever while the board's own TX
  indicator blinked — proving bytes reached the bridge but not the receiver.
- **Baud parameter not propagated.** `uart_tx` was instantiated with a hardcoded
  `CLK_FREQ(100_000_000)` while the board runs at 12 MHz, so it held each bit for 868
  cycles instead of 104. Received bytes came out as `0x00`/`0x80` garbage — the signature
  of sampling at the wrong rate. Fixed by threading `CLK_FREQ`/`BAUD_RATE` as parameters
  from `top` down through `core_pipelined` to both UARTs, so there is one source of truth.
  The elaboration log had actually hinted at it: `uart_rx(CLK_FREQ=12000000)` versus
  `uart_tx_default`.
- **Hardware Manager hung on "connecting to server".** The Arty S7 uses one FTDI chip for
  both JTAG and UART, so an open COM port handle can block the JTAG channel. Kill any
  running serial script before programming.

### Result

```
> python scripts/send_program.py COM5 programs/hello_test.hex
Loaded 14 instruction words from programs/hello_test.hex
Program sent.  Core released.  Output follows:
----------------------------------------
HI
```

Full loop on real silicon: host → serial → bootloader → instruction memory → pipelined
core → ALU → memory-mapped UART → serial → terminal.

### Status

Working pipelined RV32I processor on a Spartan-7, loading programs at runtime over serial
and printing results. **1120 LUT / 699 FF / 0.5 BRAM (3.4% of the device), fmax ~94 MHz,
timing closed with zero failing endpoints.**

### Next

- riscv-tests ISA compliance suite and Spike co-simulation — now practical, since programs
  load at runtime instead of requiring a re-synthesis each time
- Dhrystone / CoreMark for IPC
- Branch resolution in ID: shortens the critical path *and* halves the branch penalty,
  measurable on both fmax and IPC
