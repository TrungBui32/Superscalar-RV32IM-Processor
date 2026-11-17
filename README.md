# RV32IM Dual-Issue In-Order Pipelined Processor

A personal FPGA implementation of a dual-issue, in-order, 5-stage pipelined RISC-V processor supporting the RV32IM ISA. Targets the Xilinx Nexys 4 (Artix-7) board, synthesised and implemented in Vivado 2019.2.

**Historical board result:** ~50 MHz (original Artix-7 implementation). Current core OOC timing is reported below.

**CoreMark score:** 2.22 CoreMark/MHz

---

## Architecture Overview

### Pipeline

The processor issues two instructions per cycle (pipe0 = older, pipe1 = newer) through a classic 5-stage pipeline:

| Stage | Name | Work done |
|-------|------|-----------|
| IF    | Instruction Fetch | PC update, IROM read (BRAM), branch prediction |
| ID    | Instruction Decode | Register file read, immediate extension, hazard detection |
| EX    | Execute | ALU/shifter, data forwarding, mul/div dispatch |
| MEM   | Memory | DMEM read/write (BRAM), branch resolution |
| WB    | Write-Back | Register file write |

Both pipes share a single register file and a single DMEM port; structural hazards between pipes are resolved by the hazard controller.

### Supported ISA (RV32IM)

| Category | Instructions |
|----------|-------------|
| Arithmetic/Logic | ADD, SUB, AND, OR, XOR, SLT, SLTU, ADDI, ANDI, ORI, XORI, SLTI, SLTIU |
| Shifts | SLL, SRL, SRA, SLLI, SRLI, SRAI |
| Upper-immediate | LUI, AUIPC |
| Multiply/Divide | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU |
| Load | LB, LH, LW, LBU, LHU |
| Store | SB, SH, SW |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jump | JAL, JALR |
| System | ECALL, EBREAK, MRET, WFI |
| CSR (Zicsr) | CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI |
| Ordering | FENCE, FENCE.I (Zifencei) |

### Branch Predictor

Gshare-style predictor with:
- **128-entry BHT** (2-bit saturating counters) organised as 8 banks × 16 entries
- **Tagged BTB** storing 12-bit PC-relative offsets
- **8-entry Return Address Stack** for JALR return prediction
- PC-indexed using bits `[8:2]` for lookup; updates on branch resolution in MEM

### Multiply / Divide Unit

One outstanding operation, with a DSP-backed multiply datapath and a separate
iterative divider. Latencies below count clock edges **after request acceptance**
until `Busy` deasserts; result consumption can be delayed by an external stall.

| RV32 operation | Latency |
| --- | ---: |
| MUL / MULH / MULHU / MULHSU | 2 cycles |
| DIV / DIVU / REM / REMU, general case | 9 cycles |
| Division by zero, dividend zero, or divisor magnitude one | 1 cycle |

The multiplier registers extended operands, a signed product, and the result.
Vivado maps its 33-by-33-bit multiplication to four DSP48E1 blocks on Artix-7.
The divider executes four non-restoring binary steps per cycle and retains a
separate cycle for restoring the remainder and applying signs. Divide-by-zero
and signed-overflow results follow RV32M semantics.

The hazard controller stalls the pipeline while the operation computes. All
request data is captured at acceptance; the result stays stable until EX
advances or flushes the owning instruction through `ResultReady`. Holding the
request high during a memory stall cannot restart an already completed operation.
This interface supports one outstanding operation; the core does not issue a
new multiplication every cycle.

Run `bash scripts/test_muldiv.sh` with Icarus Verilog. It checks 370,720 arithmetic
cases, including exhaustive 4-, 6-, and 8-bit operands, RV32 random and corner
cases, changed request inputs, response backpressure, and reset. Twelve core
runs cover both issue slots, dependent mixed operations, branch flushes, and
instruction/data stalls. Sixteen further cases inject a timer interrupt during
multiply/divide execution or completion, with optional response stalls, and use
both operations inside the handler before `mret`. Build products go under the
ignored `sim/build` tree.


### Mul/div measurements (2026-11-17)

Compared with `b3030eb`, `efd8404` reduces accepted-request-to-result latency
from 9 to 2 cycles for multiplication and from 9 to 1 for the special division
cases above. General division remains 9 cycles. At a 20 ns clock, the multiply
latency after acceptance is 40 ns instead of 180 ns; acceptance and downstream
stall cycles are excluded from this number.

| Directed core program | Previous cycles | New cycles |
| --- | ---: | ---: |
| MUL followed by a dependent ADDI | 20 | 13 |
| Same program, two-cycle completion stall | 31 | 15 |
| Fourteen dependent/mixed MUL/DIV/REM operations | 164 | 106 |
| Upstream `rv32um-p-mul`, no external stalls | 1,059 | 702 |
| Upstream `rv32um-p-mulh`, no external stalls | 1,043 | 700 |

All 344 ISA/directed runs across four stall seeds, two PMA runs, 97 CSR-suite
checks, and 28 existing interrupt combinations pass with the new RTL, in addition
to `scripts/test_muldiv.sh`. Yosys reports no structural problems or inferred
latches. Verilator reports no new mul/div warning; existing warnings elsewhere
in the core remain.

An isolated RV32 mul/div wrapper was synthesized and routed in Vivado 2023.2 on
`xc7a100tcsg324-1`, with a 20 ns clock and 0.1 ns user uncertainty, using default
`opt_design`, `place_design`, `phys_opt_design`, and `route_design` directives:

| Isolated unit, post-route | Previous | New |
| --- | ---: | ---: |
| LUTs | 2,316 | 621 |
| Flip-flops | 615 | 237 |
| DSP48E1 | 0 | 4 |
| Setup WNS | +6.361 ns | +6.077 ns |
| Hold WHS | +0.105 ns | +0.039 ns |

Both versions pass internal setup and hold timing at 50 MHz; external I/O delays
are unconstrained. The new isolated unit's worst path is in the four-step
divider. These unit measurements do not establish full-core or SoC timing.
Local before/after checkpoints, source snapshots, and reports are under the
ignored `sim/build/muldiv_compare/{baseline,optimized}/` directories. Functional
logs and ISA cycle comparisons are in `sim/build/muldiv_optimized/`.


The same core-only OOC flow and constraints used for `1a97d9b` also completed
on the new RTL, including routing all 19,913 routable nets with zero errors:

| Whole core, post-route | Before (`1a97d9b`) | DSP mul/div (`efd8404`) |
| --- | ---: | ---: |
| LUTs | 19,058 | 18,324 |
| Flip-flops | 7,639 | 7,278 |
| DSP48E1 | 0 | 4 |
| Setup WNS | +0.021 ns | +0.324 ns |
| Hold WHS | +0.038 ns | +0.039 ns |
| Critical datapath delay | 19.541 ns | 19.338 ns |

The core passes setup, hold, and pulse-width timing at 50 MHz. The integrated
mul/div instance uses 434 LUTs, 237 FFs, and four DSPs after routing. The critical
path now starts at `pmp_regions/upper_last_words_reg[37]` and ends at
`id_ex_reg1/csr_rdata_ex_reg[15]`; it is outside the multiplier. No timing
exceptions were added. DRC reports no errors, with DSP pipeline advisories and
OOC configuration-voltage/unloaded-port warnings remaining. The two-cycle
multiply meets timing without adding the extra DSP stages suggested by those
advisories.

Core reports, source snapshots, the flow script, and checkpoints are in
`sim/build/vivado_core_muldiv/`. These are internal core timing results with
external I/O unconstrained. **The full SoC has not been rerouted for this change**;
the older SoC timing results below do not describe the DSP-based RTL.

### Data Forwarding

11 bypass paths handled by `forward_ctrl`, covering:
- EX→EX (both pipes), MEM→EX (both pipes), WB→EX (both pipes)
- Cross-pipe forwarding (pipe0 result → pipe1 source)
- ID-stage forwarding for branches resolved early

### Memory

| Memory | Size | Interface | Clock |
|--------|------|-----------|-------|
| IMEM | 32 kB | Xilinx Block RAM | 200 MHz (single-cycle read) |
| DMEM | 32 kB | Xilinx Block RAM | 200 MHz (single-cycle read/write) |

The processor core runs at **100 MHz**; BRAMs are clocked at **200 MHz** via Xilinx Clocking Wizard IP for single-cycle access.

### SoC Peripherals (`rtl/soc/`)

| Peripheral | File | Notes |
|------------|------|-------|
| UART | `uart.vhd` | TX/RX, 115200 baud |
| Machine timer | `machine_timer.v` | 64-bit mtime/mtimecmp, msip, machine IRQs |
| OLED display | `pmodoledrgb_bitmap.vhd` | Pmod OLED RGB bitmap |
| Accelerometer | `ADXL362Ctrl.vhd` + `SPI_If.vhd` | ADXL362 over SPI |

---

## Repository Layout

```
rv32im-processor/
├── rtl/
│   ├── core/               ← synthesisable processor core (Verilog)
│   │   ├── core.v          ← top-level pipeline (dual-issue)
│   │   ├── decode_unit.v   ← instruction decoder
│   │   ├── alu.v           ← arithmetic-logic unit
│   │   ├── barrel_shifter.v
│   │   ├── muldiv_unit.v   ← DSP multiply + iterative divide
│   │   ├── reg_file.v      ← 32×32-bit register file
│   │   ├── pc_reg.v        ← program counter register
│   │   ├── next_pc.v       ← next-PC computation
│   │   ├── imm_extend.v    ← immediate sign-extension
│   │   ├── branch_predictor.v
│   │   ├── hazard_ctrl.v
│   │   ├── forward_ctrl.v
│   │   ├── if_id_reg.v
│   │   ├── id_ex_reg.v
│   │   ├── ex_mem_reg.v
│   │   └── mem_wb_reg.v
│   └── soc/                ← board-level integration (Verilog + VHDL)
│       ├── fpga_top.vhd    ← FPGA top entity (Nexys 4 I/O mapping)
│       ├── soc_top.v       ← SoC wrapper (core + BRAMs + peripherals)
│       ├── uart.vhd
│       ├── ADXL362Ctrl.vhd
│       ├── SPI_If.vhd
│       └── pmodoledrgb_bitmap.vhd
├── constraints/
│   ├── nexys4.xdc
│   └── nexys4_ddr.xdc
├── sim/
│   ├── tb_soc.v            ← full SoC testbench
│   ├── tb_branch_predictor.v
│   ├── tb_dip_led.v        ← DIP→LED smoke test
│   ├── tb_dip_led_sc.v     ← self-checking DIP→LED testbench
│   └── run_sim.tcl         ← Vivado xsim automation
├── mem/
│   ├── IMEM.coe            ← instruction memory initialisation
│   └── DMEM.coe            ← data memory initialisation
├── sw/
│   └── coremark/           ← CoreMark 1.0 benchmark port
└── README.md
```

---

## Building the Software (CoreMark)

Prerequisites: RISC-V GCC cross-compiler and CMake 3.15+.

```bash
cd sw/coremark
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=../riscv-toolchain.cmake
make
```

The build produces a `.coe` file for loading into the IMEM Block RAM. The `hex_to_coe.py` utility converts a raw Intel-HEX or binary to COE format if needed.

---

## M-mode CSR, traps, and interrupts

The core currently implements machine mode only. `misa` is fixed to RV32IM
(`0x40001100`); it does not advertise U/S, compressed, floating-point, or atomic
instructions. S/H CSR address constants are retained in `csr.v` for future work,
but accesses to those unimplemented CSRs trap instead of exposing placeholder
registers. This is an intentional change from the earlier CSR-bank prototype.

Implemented machine CSRs include `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`,
`mepc`, `mcause`, `mtval`, and hardware-owned `mip`. `mstatus.MPP` is fixed to M;
only MIE/MPIE are writable. `mtvec` supports Direct/Vectored modes, and `mepc`
is aligned for IALIGN=32. `mstatush` and `mcounteren` read zero. Machine ID CSRs
read zero on this single-hart, non-commercial implementation.

The 64-bit `mcycle` and `minstret` counters include RV32 high-half CSRs and
read-only `cycle`/`instret` aliases. `mcountinhibit` supports CY/IR. Faulted
instructions and bubbles do not retire; explicit writes to `minstret` suppress
that instruction's automatic increment. `time/timeh` read the SoC timer.

Synchronous traps cover illegal encodings/CSR accesses, M-mode ECALL, EBREAK,
and misaligned instruction targets. Misaligned loads/stores can be split into
byte transactions as described below; regions that disallow splitting raise
load/store address-misaligned traps. PMP denials raise instruction/load/store
access faults. Trap entry updates
`mepc`, `mcause`, `mtval`, and MIE/MPIE; `MRET` restores interrupt state and
resumes at `mepc`. `FENCE` serializes older operations; `FENCE.I` also flushes
prefetched instructions. `WFI` currently executes as a legal no-op.

`irq_software`, `irq_timer`, and `irq_external` on `core` are synchronous,
level-sensitive inputs. Eligible interrupts have priority external, software,
then timer. The core drains older work and saves the next unexecuted PC before
entering the handler. The SoC connects software/timer IRQs to `machine_timer.v`;
external IRQ is tied low until a device interrupt controller is integrated.

| MMIO address | Register | Notes |
|---|---|---|
| `0x02000000` | `msip` | Bit 0 asserts machine software interrupt |
| `0x02004000` / `0x02004004` | `mtimecmp` low/high | Reset to all ones; interrupt when `mtime >= mtimecmp` |
| `0x0200BFF8` / `0x0200BFFC` | `mtime` low/high | One tick per core clock; also readable through `time/timeh` |

For RV32 timer programming, use the normal safe sequence for the 64-bit compare
register (low = all ones, high = new high, low = new low). Clear a timer IRQ by
moving the compare value into the future; software cannot clear MTIP/MEIP by
writing `mip`.

CSR data forwarding is enabled by default. Set core parameter
`CSR_FORWARD_ENABLE=0` for the conservative baseline. Control writes and system
instructions remain serialization barriers. `DEBUG_HALT_ON_EBREAK=1` restores
the legacy testbench-only EBREAK halt behavior; the default is an architectural
breakpoint trap. The regression testbenches select debug halt explicitly where
needed.

### Memory protection and native breakpoints

PMP provides 16 entries (`pmpcfg0`–`pmpcfg3`, `pmpaddr0`–`pmpaddr15`) with
4-byte granularity and OFF, TOR, NA4, and NAPOT modes. The lowest matching entry
must cover the whole access. Locked entries enforce R/W/X in M-mode; unlocked
entries bypass permissions in M-mode. Configuration/address locks, including a
locked TOR entry's preceding address register, remain set until reset. This does
not add U/S modes or an MMU. The data bus carries 32-bit physical addresses.

`pmp_decode.v` computes region bounds once for the four instruction/data checks.
The checkers compare entries in parallel and select the lowest-numbered match.
NAPOT bounds use shared bit-prefix logic rather than variable-size additions.
Each checker compares the first 4-byte word with the region bounds; equality
checks detect a boundary crossed by an RV32 byte/halfword/word access. Permission
is denied only when the winning entry denies access, so a miss needs no separate
wide reduction in the allow path. The fault address selects an upper bound only
for a partial high-end match. Unsupported
access sizes fail closed. An all-ones NAPOT address covers the physical space;
empty/reversed TOR ranges do not match. These changes preserve pipeline latency
and do not add CSR-write cycles.

`pmp_region_cache.v` registers decoded bounds, active bits, and permissions
together, removing raw CSR decoding from the permission-check feedback path.
Bounds are cached as signed `(byte_boundary >> 2) - 1` values. A zero boundary
therefore becomes -1. Comparing the current word against this cached value
handles both containment and crossing into the next word without an address
incrementer on the allow path. A partial high-end match implies that the upper
boundary is the next word. Its address is computed directly from the access
address in parallel with permission checks, avoiding a wide boundary mux and
a late incrementer on the fault-address path.
An accepted PMP CSR write marks the following cycle as refresh pending. Live
MEM work is held and memory accesses/interrupt entry are suppressed until the
cache catches up. The existing control-CSR serialization normally supplies
this bubble; the measured regressions retain their previous cycle counts.
CSR readback still uses the original CSR bank. All 16 entries, address modes,
locking rules, and partial-access faults remain supported.

The combinational PMP entry checks and region decoder have SAT proofs against
byte-interval and arithmetic-bound references. A compositional proof cuts the
per-entry results and checks all 16 entries' priority and fault-address selection
against a procedural first-match reference, using the high-end fault predicate's
boundary relation. A sequential proof checks cache
coherence outside refresh and completion of a blocked refresh after one edge,
assuming raw state changes only on accepted writes and those writes stop while
live MEM work is blocked. Run them from the repository root:

```bash
yosys -Q -s formal/pmp.ys
yosys -Q -s formal/pmp_cache.ys
```

Two native address triggers provide exact-address execute/load/store breakpoints
before the matching instruction takes effect. `tselect`, `tdata1`, `tdata2`,
`tinfo`, and `tcontrol` are implemented. The supported configuration is mcontrol
type 2, M-mode, address equality, before timing, and breakpoint exception action.
Unsupported mcontrol fields read zero. `tcontrol.MTE/MPTE` disable triggers in a trap
handler and restore them on MRET. External Debug Mode, JTAG debug, trigger
chaining, and data-value matching are not implemented.

### Misaligned data accesses

`SUPPORT_MISALIGNED=1` enables halfword/word loads and stores at any byte offset,
including accesses across word boundaries. The MEM stage splits these accesses
into byte transfers, holds the pipeline through external stalls, and assembles
load data before sign/zero extension. Split stores are not atomic. PMP and
triggers check the original complete access before any byte transfer starts.
Overlapping memory operations remain ordered across the two issue pipes.

`MISALIGNED_BASE` and `MISALIGNED_MASK` select a RAM region with a prefix mask;
both endpoints must be inside it. Their defaults are zero, allowing all
byte-addressable memory on the standalone core. The board SoC restricts splitting
to its DMEM region (`0x10010000`–`0x1001ffff`), so misaligned MMIO accesses trap.
Set `SUPPORT_MISALIGNED=0` to trap all misaligned halfword/word accesses.

The local ISA audit passed all 66 RV32 physical-environment tests in `rv32ui`,
`rv32um`, and `rv32mi` from riscv-tests commit
`3df703cd52d5f0d8224e3c50bf03c6cb70efff98`, using test-env commit
`6de71edb142be36319e380ce782c3d1830c65d68`. The same tests also passed with
three deterministic random memory-stall seeds. This uses a unified RAM model
around the core; it is not a full-board FPGA or timing validation.

### Forwarding and pipeline flush timing

GPR bypass selection uses registered MEM producer validity/write intent. Late
PMP/trap decisions qualify architectural writes and squash younger work, without
feeding back through the EX operand mux and address-hazard comparisons. During
structural/long-operation stalls, younger stages remain held until trap delivery.

Flush clears validity, instruction/control fields, and side-effect enables.
Wide payload registers follow their normal enable independently of flush; their
values in invalid bubbles are unspecified. Real stalls preserve live payloads,
including EX operand refresh from forwarding. This reduces the load on flush
nets while preserving all valid instruction data and precise traps.

Interrupt acceptance requires empty EX/MEM stages, which also rules out live
split accesses and PMP refresh stalls. It uses external bus/clock/multicycle
readiness directly, retaining the explicit refresh guard. This removes a
permission-dependent MEM stall path into interrupt selection and the vectored
trap-address adder without changing the cycle in which an interrupt is accepted.
The trap proof also checks this readiness equivalence.

Memory-pair hazard detection uses dedicated operand sums rather than the
general ALU/writeback result mux. Loads and stores always select addition, so
this removes shifter and CSR/link-result paths from address-conflict detection
without changing conflicts, pipeline latency, or serialization cycles. The
decoder/ALU equivalence proof checks the address substitution for arbitrary
instructions and operands:

```bash
yosys -Q -s formal/memory_address.ys
```

A Vivado 2023.2 core-only out-of-context implementation on
`xc7a100tcsg324-1`, using a 20 ns clock, 0.1 ns user clock uncertainty, and
`HD.CLK_SRC=BUFGCTRL_X0Y0`, measured the following with the same implementation
flow and timing constraints:

| Post-route metric | PMP region cache (`b96cf3d`) | PMP/IRQ changes | Dedicated hazard address (`1a97d9b`) |
|---|---:|---:|---:|
| Worst setup slack | -0.919 ns | -0.665 ns | +0.021 ns |
| Critical datapath delay | 20.269 ns | 20.226 ns | 19.541 ns |
| Critical logic levels | 25 | 26 | 24 |
| Hold slack | +0.033 ns | +0.035 ns | +0.038 ns |
| LUTs | 19,551 | 19,069 | 19,058 |
| Flip-flops | 7,619 | 7,639 | 7,639 |

The final standard flow (`opt_design`, `place_design`, `phys_opt_design`,
`route_design`, all with default directives) fully routed 20,786 nets with no
routing errors. Setup, hold, and pulse-width timing pass at 50 MHz. Setup margin
is only 21 ps; this is a core-only result, not a full-SoC or board timing
guarantee. External input/output delays remain unconstrained. The clock period,
uncertainty, and clock source were unchanged, and no protocol-derived false-path
or multicycle exceptions were added. Compared with the prior PMP cache, these
changes save 493 LUTs at a cost of 20 flip-flops, with no additional pipeline
stage or observed cycle-count penalty.

The remaining worst path runs from a MEM effective-address register through
permission, misaligned-access stall, and CSR-write qualification to a PMP address
register. Raw PMP decoding and access-side boundary increments are no longer on
the permission path. Local reports and checkpoints are in the ignored directory
`sim/build/vivado_core_pmp_agu_20261117/`.

Cache validation passed 344 ISA/directed runs, two PMA fault runs, four
interrupt-during-refresh cases, 24 split-store/interrupt combinations, the CSR
regression, Verilator lint, Yosys structural checks, and seven formal properties.
All 344 ISA/directed runs and 28 interrupt cases retain their baseline cycle
counts. Directed cases include all
16 locked entries, immediate accesses after PMP writes, TOR predecessor
updates, partial misaligned stores, and traps with dependent younger work.

Run the trap-priority proof and pipeline sequential equivalence checks with:

```bash
yosys -Q -s formal/trap_squash.ys
python3 formal/pipeline_payload_equivalence.py --reference 426e4e0
```

Run the open-source functional regressions from any directory:

```bash
./sim/run_csr_tests.sh
```

They require Icarus Verilog (`iverilog`, `vvp`) and cover decode, normalized
forwarding, pipeline hazards, randomized architectural scoreboards, trap/MRET,
interrupt masking/priority/vectoring/retriggering, counter behavior, and actual
CPU + MMIO timer/software interrupt handlers. They do not certify ISA compliance
or FPGA timing. U/S-mode, MMU, external bus access-fault inputs, and a device interrupt
controller are not implemented. The complete board wrapper uses generated
BRAM/clock/counter IP; the full-SoC build script below recreates these IPs.

---

## Simulation

From the `sim/` directory, with Vivado on `PATH`:

```tcl
vivado -mode tcl -source run_sim.tcl
```

`run_sim.tcl` compiles all RTL with `xvlog`/`xvhdl`, elaborates with `xelab`, and launches `xsim`.

---

## Synthesis & Implementation

With Vivado 2023.2 on `PATH`, run from the repository root:

```bash
vivado -mode batch -source scripts/implement_soc.tcl
```

The script builds `fpga_top` on `xc7a100tcsg324-1`, including the mixed
Verilog/VHDL board wrapper, core, memories, timer, UART, OLED, and accelerometer
logic that remains connected after optimization. It recreates the missing IPs:

| IP | Configuration |
|---|---|
| `clk_wiz_0` | 100 MHz input, 50 MHz core, 100 MHz BRAM; both outputs at 0 degrees |
| `blk_mem_gen_0` | True dual-port 8192 x 32-bit memory (32 KiB), initialized from `mem/IMEM.coe` |
| `blk_mem_gen_1` | True dual-port 4096 x 32-bit memory (16 KiB), 8-bit write lanes, initialized from `mem/DMEM.coe` |
| `c_counter_binary_0` | 32-bit incrementing counter with synchronous clear |

Both BRAM read ports have one cycle of latency at the BRAM clock; there are no
additional output registers. Unspecified image locations are initialized to
zero. These configurations are reconstructed from the RTL port widths and
connections; the original `.xci` files are absent. Some older RTL comments
describe different frequencies or capacities.

Sources, memory images, generated project/IPs, checkpoints, and reports are
saved under `sim/build/vivado_soc/` (ignored by Git). Optional arguments select
another output directory and the existing `nexys4_ddr` pin file:

```bash
vivado -mode batch -source scripts/implement_soc.tcl -tclargs sim/build/vivado_soc_ddr nexys4_ddr
```

This is a normal full-device implementation, with real MMCM-generated clock
relationships and 0.1 ns user clock uncertainty. The old blanket 20 ns
clock-to-clock max-delay is removed; core/BRAM and peripheral crossings must
meet their actual edge relationships. External I/O delay budgets are not
specified, so internal timing results alone do not constitute complete board
interface signoff. The build ends with a routed checkpoint and timing,
utilization, clock-interaction, exception, and DRC reports.

The measured full-SoC run on 2026-11-17 completed synthesis and routed all
23,873 routable nets, with no black boxes and no routing or DRC errors. Its
setup timing does **not** close at the requested 50/100 MHz configuration:

| Full-SoC post-route metric | Result |
|---|---:|
| Worst setup slack | -6.846 ns |
| Total negative setup slack | -3508.618 ns |
| Setup-failing endpoints | 2,627 |
| Worst hold slack | +0.036 ns (zero failing endpoints) |
| LUTs | 21,766 |
| Flip-flops | 8,103 |
| RAMB36 / RAMB18 | 12 / 1 |

The worst path starts at `soc_top_inst/core_inst/ex_mem_reg0/alu_out_mem_reg[2]`,
passes through PMP permission and store-data qualification, and ends at a DMEM
BRAM data input (`DIADI[6]`). The 50 MHz-to-100 MHz crossing has a 10 ns setup
requirement and a 16.130 ns datapath delay (4.570 ns logic, 11.560 ns routing).
The reverse BRAM-to-core direction has WNS -3.703 ns. The core's 50 MHz domain
also has intra-clock WNS -3.593 ns in this integrated placement. Consequently,
the earlier positive core-only OOC result does not establish SoC timing closure.
There are no unconstrained internal endpoints; two external input ports and
19 output ports still have no external delay budgets. The routed checkpoint
and detailed reports are in `sim/build/vivado_soc/`.

The current wrapper does not implement all declared MMIO signals: GPIO/display
writes and UART RX reads/acknowledgement are incomplete, and unused RX logic is
pruned. The optional RX synchronizer constraint is guarded when its registers
are absent. DMEM has a 64 KiB decode window backed by 16 KiB of storage, so
addresses in that window alias every 16 KiB. A completed implementation describes
this connected RTL; it does not establish firmware or board functionality.

---

## Key Design Decisions

- **Dual-issue with in-order commit** keeps implementation complexity low while doubling theoretical IPC on instruction-level-parallel code.
- **BRAM at 2× core frequency** gives single-cycle IMEM/DMEM latency without an instruction cache, which simplifies hazard handling significantly.
- **Gshare branch predictor** reduces branch-misprediction penalties (4-cycle flush) to a few percent overhead on typical workloads.
- **DSP-backed multiply** produces a result two cycles after request acceptance, while the separate divider retains four binary steps per cycle.
