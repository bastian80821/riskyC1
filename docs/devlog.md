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
### Next
 
Optimisation and verification, in rough priority order:
- Synthesise and read the timing report — find the *actual* critical path rather than
  guessing. Prime suspects: the MEM chain above, and EX (forwarding mux + ALU).
- riscv-tests ISA suite and Spike co-simulation.
- UART, then on-hardware bring-up for real fmax and utilisation numbers.
