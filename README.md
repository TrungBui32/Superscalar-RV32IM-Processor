# RV32IMA Dual-Issue In-Order Pipelined Processor

A personal FPGA implementation of a dual-issue, in-order, 5-stage pipelined RISC-V processor supporting the RV32IMA ISA. Targets the Xilinx Nexys 4 (Artix-7) board. The original implementation used Vivado 2019.2; the current full-SoC flow uses Vivado 2023.2.

**Historical board result:** ~50 MHz (original Artix-7 implementation). The current RV32IMA full SoC has been synthesized and routed in Vivado 2023.2, but setup timing does **not** close at the requested 50 MHz core / 100 MHz BRAM clocks: WNS **−8.237 ns**. See the resource and timing comparison below.

**CoreMark, current RTL simulation:** **2.4397 CoreMark/MHz (`-O1`)**, **3.3807 (`-O2`)**, or **3.4640 (`-O3`)**, GCC 10.2.0, ideal zero-wait BRAM model. See the reproducible run below; this is not a measured board score.

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

Both pipes share a single register file and use two ports of the same DMEM. Structural hazards are resolved by the hazard controller; atomic instructions temporarily own both memory access paths.

### Supported ISA (RV32IMA)

| Category | Instructions |
|----------|-------------|
| Arithmetic/Logic | ADD, SUB, AND, OR, XOR, SLT, SLTU, ADDI, ANDI, ORI, XORI, SLTI, SLTIU |
| Shifts | SLL, SRL, SRA, SLLI, SRLI, SRAI |
| Upper-immediate | LUI, AUIPC |
| Multiply/Divide | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU |
| Load | LB, LH, LW, LBU, LHU |
| Store | SB, SH, SW |
| Atomic (A: Zaamo + Zalrsc) | LR.W, SC.W, AMOSWAP.W, AMOADD.W, AMOXOR.W, AMOAND.W, AMOOR.W, AMOMIN.W, AMOMAX.W, AMOMINU.W, AMOMAXU.W |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jump | JAL, JALR |
| System | ECALL, EBREAK, MRET, SRET, WFI |
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
external I/O unconstrained. The full SoC was subsequently rerouted with the
DSP-based RTL; its setup timing remains negative at 50/100 MHz, as detailed in
the full-SoC results below. Core-only closure does not establish SoC closure.


### RV32A atomic execution

`rtl/core/atomic_unit.v` implements all eleven RV32A word instructions. Decode
checks `funct3=010`, the eleven legal `funct5` values, and `rs2=x0` for LR;
unsupported widths and reserved operations trap. All four `aq`/`rl` combinations
are legal. Address and operand come from forwarded `rs1` and `rs2`; results use
the existing memory-result writeback path. Pipeline registers already carry the
whole instruction, preserving the operation, ordering bits, destination and PC.

The first implementation serializes each atomic instruction through the system
barrier: older instructions drain before it issues, and younger instructions
wait until it completes. A shared engine handles either pipe. The memory-port
mux grants exclusive access to the owning MEM instruction and blocks the other
port. This conservative policy imposes sufficient ordering for every `aq`/`rl`
combination. AMOs return the old memory value; SC returns zero on success or one
on reservation failure. Writing `rd=x0` still performs the memory operation.

The engine latches request payloads, uses independent memory-request/response
handshakes, and holds its result until the core consumes it. The adapter bridges
to the current core's synchronous memory interface: one ready-qualified bus beat
is captured and acknowledged on the following core cycle. Bus progress does
not depend on the atomic pipeline stall, avoiding request/ready deadlocks and
repeated stores under backpressure. The present BRAM fabric has no dynamic bus
error signal; PMP/PMA faults are checked before dispatch. The reusable engine
also supports read/write error responses, including store/AMO fault causes for
AMO read failures.

LR reserves one aligned word. SC checks the most recent reservation and always
consumes it, whether successful or not. Ordinary committed stores on either
pipe conservatively invalidate the reservation, even at another address; this
also handles normal stores through aliases of backing RAM. Traps, `mret`,
`fence.i`, and PMP updates clear it. Branch flushes alone do not clear a live
reservation. LR releases memory ownership when it finishes; memory is never
locked across the instruction sequence from LR to SC. Constrained LR/SC loops
with no interfering stores make progress; the upstream test completes 1,024
successful increments with every tested stall seed.

Atomic words must be four-byte aligned, independently of ordinary misaligned
load/store support. LR uses load alignment/access faults; SC and AMOs use
store/AMO faults. SC still undergoes permission checks when no reservation
exists. AMOs require both read and write PMP permissions before any access.
`ATOMIC_BASE`/`ATOMIC_MASK` select the supported PMA region (defaults describe a
flat abstract RAM). The SoC sets it to its actual 16 KiB DMEM backing RAM,
`0x10010000` through `0x10013fff`. Atomics to MMIO, ROM, or addresses beyond
the physical DMEM raise access faults. The current platform has one hart and no DMA;
adding another memory master requires global arbitration and reservation
invalidation events, not just an additional local atomic unit.

Run the standalone decode/unit and directed architectural regressions with:

```bash
python3 scripts/test_atomic.py
```

To include the ten upstream physical RV32A tests, initialize `riscv-tests/env`
and pass its checkout (or use `--riscv-env` for a separate physical environment):

```bash
python3 scripts/test_atomic.py --riscv-tests /path/to/riscv-tests
```

Validation passed 2,048 decode combinations, 4,635 unit transactions, and 68
architectural runs over four deterministic instruction/data stall seeds: 40
upstream RV32A runs and 28 directed runs. Directed coverage includes both issue
slots, destination/source overlap, signed/unsigned arithmetic, `rd=x0`, failed
SC, latest-LR replacement, byte stores and RAM aliases, taken branches,
wrong-path atomics, alignment/PMP/PMA/encoding faults, interrupt entry during
read/write/completion, and reservation clearing when an interrupt handler
executes LR and returns with `mret`.

The existing 344 ISA/directed runs, two PMA runs, 97 CSR-suite checks, 28 existing
PMP/split-access interrupt cases, and the mul/div suite also pass. Local legacy
CSR test fixtures were updated for the new `misa=0x40001101` value. Yosys reports
zero structural problems and no inferred latches; Verilator has no new atomic
warning or combinational-loop warning. The full-SoC resource/timing comparison
below includes this RV32A integration; earlier core-only OOC measurements above
remain historical snapshots. The current full SoC has not achieved timing closure.


### Atomic latency with the current memory adapter

Measured with instruction/data ready asserted, no interrupt injection, and the
current adapter acknowledging an accepted memory beat on the following core
cycle. The request edge is `req_valid && req_ready`; response latency counts
full clock intervals from that edge until `rsp_valid` is asserted.

| RV32A operation | Request to response valid | Request to response consumption | Total MEM-stage occupancy |
|---|---:|---:|---:|
| LR.W | 3 cycles | 4 cycles | 5 cycles |
| SC.W, success | 3 cycles | 4 cycles | 5 cycles |
| SC.W, reservation failure | 1 cycle | 2 cycles | 3 cycles |
| All nine AMO.W operations | 5 cycles | 6 cycles | 7 cycles |

MEM occupancy starts when the instruction enters MEM and ends when it advances
to WB. These figures exclude waiting in ID for older work to drain, and exclude
external stalls. A held response or a busy bus can increase latency. Alignment,
PMP, PMA, and encoding faults are checked before dispatch, so such instructions
do not contribute samples to the atomic engine's latency table. Architectural
cycle counts are distinct from the physical critical-path delay reported by
static timing analysis; no board-frequency claim follows from this table.

The latency probe observed 2,099 completed no-stall transactions across both
issue slots, covering every atomic operation, with identical minimum/maximum
latencies for each category. All 68 architectural runs, the 2,048 decode cases,
and 4,635 atomic-unit cases still pass with the probe enabled. Reproduce with:

```bash
python3 scripts/test_atomic.py --latency --riscv-tests /path/to/riscv-tests
```

Use `--riscv-env` if the physical test environment is in a separate checkout.
No-stall samples and `latency_summary.json` are written to the selected build
directory. The measurement used `sim/build/atomic_latency/`; its full log is
also preserved in `sim/build/vivado_soc_rv32a/atomic_latency.log`.

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
│   │   ├── atomic_unit.v   ← shared AMO and LR/SC engine
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

## Running CoreMark on the current RTL

The current RV32IMA core (`0748264`) was tested with unmodified EEMBC CoreMark
kernels from commit `1f483d5b8316753a742cbf5590caf5bd0a4e4777`. The runner extracts
committed files with `git show`; modifications in the source checkout are not
used. Only the platform header, startup, timing, and UART port are supplied by
this repository. The original COE-oriented port in `sw/coremark/` remains
unchanged and is not used for these measurements.

| Performance seeds, 40 iterations | GCC `-O1` | GCC `-O2` | GCC `-O3` |
|---|---:|---:|---:|
| Timed CPU cycles | 16,395,495 | 11,831,760 | 11,547,431 |
| Cycles per iteration | 409,887.375 | 295,794.000 | 288,685.775 |
| CoreMark/MHz, RTL estimate | **2.439695** | **3.380731** | **3.463974** |
| Timed simulated seconds at 1 MHz | 16.395495 | 11.831760 | 11.547431 |
| Instruction image bytes (`.text`) | 11,008 | 11,592 | 18,080 |

`-O1`, `-O2`, and `-O3` are GCC optimization levels, not processor configurations.
`-O1` performs basic optimization; `-O2` enables additional compiler
optimizations. On the same RTL and benchmark inputs, `-O2` reduces timed cycles
by **27.84%** and increases CoreMark/MHz by **38.57%** relative to `-O1`.
This difference measures compiler-generated code efficiency; the processor RTL
is identical at all three optimization levels. `-O1` matches the optimization level in the original
CoreMark CMake build.
`-O3` enables more aggressive compiler optimization. Relative to `-O2`, this
run reduces timed cycles by **2.40%** and increases throughput by **2.46%**,
while increasing the instruction image by **55.97%** (11,592 to 18,080 bytes).
All three instruction images fit the same 32 KiB IMEM; the data RAM size and
benchmark inputs are unchanged.

Both standard seed sets pass: performance `0,0,0x66` and validation
`0x3415,0x3415,0x66`. Each run uses 2000 bytes total for the three algorithms,
one context, static allocation, no cache, and always-ready instruction/data
memory. The model maps the actual 32 KiB instruction and 16 KiB data RAM sizes
and SoC addresses. Per-algorithm CRCs match the official known values; final
CRCs also match independent native execution of the same pristine kernels:
performance `crcfinal=0x65c5`, validation `crcfinal=0xf006` after 40 iterations.
Each target run exceeds ten simulated seconds at the explicit 1 MHz model
clock. Simulator timestamps and the software timer use that same frequency.

| Validation seeds, 40 iterations | GCC `-O1` | GCC `-O2` | GCC `-O3` |
|---|---:|---:|---:|
| Timed CPU cycles | 16,408,852 | 11,883,653 | 11,581,709 |
| Standard CRC checks | PASS | PASS | PASS |
| Final CRC versus native reference | PASS | PASS | PASS |

The reported CoreMark/MHz score uses the performance seed set; the validation
seed set checks correctness. Raw logs and machine-readable results are in
`sim/build/coremark_verified/results_O1_40.json`, `results_O2_40.json`,
`results_O3_40.json`, and `comparison.json`.

The cross compiler is `riscv64-unknown-elf-gcc` 10.2.0. All benchmark C files use
the same flags, with `-O1`, `-O2`, or `-O3` as indicated:

```text
-march=rv32ima -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0
-ffreestanding -fno-builtin -fno-pic -fno-pie -ffunction-sections -fdata-sections
```

There is no LTO or PGO. Timing uses `mcycle` over upstream's timed region;
initialization and output formatting are outside that interval. The score is
`iterations * 1,000,000 / timed_cycles`. The port uses `HAS_FLOAT=0`; firmware
prints integer seconds/rates, while the host computes this value from unrounded
cycle counts. The 1 MHz model clock allows full
validation-duration runs without simulating 500 million cycles per seed set;
it does not establish an achievable FPGA clock. These are architectural
throughput estimates from core RTL with ideal memory, not a board measurement,
full-SoC benchmark, or new timing-closure result. The older 2.22/MHz headline had
no matching reproducible configuration and is not used as a performance baseline.

Requirements: Verilator, GNU make, host GCC/G++, the RISC-V cross compiler, and
an existing Git checkout of EEMBC CoreMark. Run:

```bash
python3 scripts/run_coremark.py --coremark /path/to/coremark \
  --rev 1f483d5b8316753a742cbf5590caf5bd0a4e4777 \
  --iterations 40 --hz 1000000 --opt O2
python3 scripts/run_coremark.py --coremark /path/to/coremark \
  --rev 1f483d5b8316753a742cbf5590caf5bd0a4e4777 \
  --iterations 40 --hz 1000000 --opt O1
python3 scripts/run_coremark.py --coremark /path/to/coremark \
  --rev 1f483d5b8316753a742cbf5590caf5bd0a4e4777 \
  --iterations 40 --hz 1000000 --opt O3
```

The script builds both seed sets, validates standard CRCs and native-reference
CRCs, checks simulated clock/timer consistency, and saves source hashes,
compiler commands, ELF/HEX images, output logs and JSON results under the ignored
`sim/build/coremark/` directory. `--build` selects another directory; the
measurements above are preserved in `sim/build/coremark_verified/`. Smaller
iteration counts are useful smoke tests but may fall below the required run
duration; their JSON results explicitly mark that condition.

---

## Privilege, CSRs, traps, and interrupts

The core supports M/S/U privilege with physical addressing. `misa` is fixed to
`0x40141101` (RV32IMA plus S/U); compressed, floating-point and hypervisor
extensions are not advertised. Reset enters M-mode. CSR accesses check the
current privilege, address existence and read-only encoding.

Machine CSRs include `mstatus`, `misa`, `medeleg`, `mideleg`, `mie`, `mtvec`,
`mcounteren`, `mscratch`, `mepc`, `mcause`, `mtval` and `mip`. Supervisor CSRs
include `sstatus`, `sie`, `stvec`, `scounteren`, `sscratch`, `sepc`, `scause`,
`stval`, `sip` and `satp`. `sstatus` shares SIE/SPIE/SPP with `mstatus`;
`sie`/`sip` expose the delegated bits of `mie`/`mip`. Writes preserve backing
bits outside each alias. `mstatush`, `menvcfg/menvcfgh` and `senvcfg` read zero.
Machine ID CSRs read zero on the default single-hart implementation.

`satp` supports **Bare only** and always reads zero. TVM, SUM and MXR are
read-only zero; **Sv32, page-table walking and page faults are not implemented**.
`SFENCE.VMA` currently traps as an illegal instruction, a permitted choice for
Bare-only implementations. `MRET`/`SRET` restore privilege and interrupt state,
clear MPRV when returning below M, and reset their previous-privilege field
(MPP or SPP) to U. S-mode `SRET` is blocked by TSR. WFI is a no-op in M and
in S with TW=0; it traps in U and in S with TW=1. `mtvec`/`stvec` support Direct/Vectored modes; EPCs use IALIGN=32.

`medeleg` supports implemented synchronous causes 0–9; M-mode traps always
remain in M. Delegated traps update SEPC/SCAUSE/STVAL and SIE/SPIE/SPP;
other traps update MEPC/MCAUSE/MTVAL and MIE/MPIE/MPP. `mideleg` supports
SSIP/STIP/SEIP. M-mode firmware can inject these pending bits through `mip`;
S-mode can write only delegated SSIP through `sip`. Machine IRQ pins remain
machine-level sources; no Sstc or external interrupt controller is provided.
Machine-targeted IRQs can interrupt S/U regardless of MIE. Supervisor-targeted
IRQs are masked in M, gated by SIE in S and individually enabled in U.

The 64-bit `mcycle` and `minstret` counters include RV32 high-half CSRs and
read-only `cycle`/`instret` aliases. `mcountinhibit` supports CY/IR. Faulted
instructions and bubbles do not retire; explicit writes to `minstret` suppress
that instruction's automatic increment. `time/timeh` read the SoC timer.
`mcounteren` gates counter reads in S/U; U also requires `scounteren` permission.

Synchronous traps cover illegal encodings/CSR accesses, ECALL from M/S/U, EBREAK,
and misaligned instruction targets. Misaligned loads/stores can be split into
byte transactions as described below; regions that disallow splitting raise
load/store address-misaligned traps. PMP denials and memory-interface errors
raise instruction/load/store access faults. Fetch faults follow their instruction
through the pipeline; split accesses retain the failing byte address, and atomic
read/write errors propagate through the atomic response. Trap entry updates
`mepc`/`mcause`/`mtval` or their supervisor counterparts. Trap returns resume
at the corresponding EPC. `FENCE` serializes older operations; `FENCE.I` also flushes
prefetched instructions. WFI behavior is privilege-dependent as described above.

`irq_software`, `irq_timer`, and `irq_external` on `core` are synchronous,
level-sensitive inputs. Higher-privilege targets have priority; within each
target, standard interrupts follow MEI/MSI/MTI/SEI/SSI/STI priority. The core
drains older work and saves the next unexecuted PC before
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
locked TOR entry's preceding address register, remain set until reset. S/U
always enforce matching-entry permissions and deny unmatched accesses. MPRV
applies MPP privilege to M-mode data accesses while fetch keeps current-mode
permissions. The data bus carries 32-bit physical addresses.

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

Run the machine-mode functional regressions from the repository root:

```bash
python3 scripts/test_machine.py --suite all
```

The machine suite requires Icarus Verilog (`iverilog`, `vvp`) and a RISC-V GNU
cross compiler. It covers access faults, precise dual-issue side effects, CSR
address legality and masks, trap/MRET, interrupt masking/priority/vectoring,
counters, timer MMIO and a two-task M-mode context-switch program. The full-SoC
UART test uses behavioral models of the configured synchronous FPGA IP.
Supervisor regression covers privilege transitions, CSR aliases and access
checks, delegated synchronous traps, vectored supervisor interrupts, MPRV and
PMP enforcement, under four bus-stall patterns. Run only those tests with
`python3 scripts/test_machine.py --suite supervisor`.
These tests do not certify complete ISA compliance or FPGA timing. An MMU
and a device interrupt controller are not implemented. The complete board
wrapper uses generated BRAM/clock/counter IP; the full-SoC build script below recreates these IPs.

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

The latest full-SoC run on 2026-11-18 used source checkout `de36d9c`
(including RV32A RTL from `0748264`), on the same board, with the same COE memory
images, IP configuration, clock constraints, and default implementation flow
as the previous DSP mul/div run (`9c41c06`). No RTL or timing constraints were
changed for this measurement. Synthesis completed with no black boxes; all
22,319 routable nets were fully routed with zero routing errors. There are no
DRC errors; six DSP pipelining advisory warnings remain (two DPOP-1, four DPOP-2).
Setup timing still does **not** close at the requested 50 MHz core / 100 MHz
BRAM configuration:

| Full-SoC post-route metric | Before DSP mul/div | DSP mul/div, before RV32A | Current RV32IMA |
|---|---:|---:|---:|
| Worst setup slack | -6.846 ns | -7.147 ns | -8.237 ns |
| Total negative setup slack | -3508.618 ns | -3603.940 ns | -7993.786 ns |
| Setup-failing endpoints | 2,627 | 2,546 | 3,679 |
| Worst hold slack | +0.036 ns | +0.040 ns | +0.030 ns |
| Hold-failing endpoints | 0 | 0 | 0 |
| LUTs | 21,766 | 19,767 | 20,060 |
| Flip-flops | 8,103 | 7,723 | 7,951 |
| DSP48E1 | 0 | 4 | 4 |
| RAMB36 / RAMB18 | 12 / 1 | 12 / 1 | 12 / 1 |
| Worst-path datapath delay | 16.130 ns | 16.423 ns | 17.509 ns |

Compared with the preceding DSP-based SoC, the RV32A design uses 293 more LUTs
(+1.48%) and 228 more flip-flops (+2.95%), with unchanged DSP and BRAM counts.
On `xc7a100t`, the current design occupies **31.64% of LUTs**, **6.27% of
flip-flops**, **1.67% of DSPs**, and **9.26% of BRAM capacity** (12.5 equivalent
RAMB36 tiles). These are whole-SoC post-route differences, including optimization
and placement changes; they are not an isolated atomic-unit area measurement.
The earlier DSP conversion saved 1,999 LUTs and 380 flip-flops before RV32A.

For comparison at synthesis, the current design uses 19,519 LUTs and 7,915
flip-flops, versus 19,377 and 7,697 before RV32A. The atomic-unit synthesis
hierarchy accounts for 236 LUTs and 176 flip-flops; integration logic also lives
in decode, memory arbitration, and pipeline control. Both syntheses use four
DSP48E1s and 12 RAMB36 plus one RAMB18.

The worst routed path starts at
`soc_top_inst/core_inst/ex_mem_reg1/alu_out_mem_reg[12]`, passes through PMP
permission and memory/pipeline qualification, and ends at the DMEM BRAM data
input `ramloop[1].../DIBDI[7]`. Its core-to-BRAM crossing has a **10 ns setup
requirement** and a **17.509 ns datapath delay** (3.452 ns logic, 14.057 ns routing),
with 17 logic levels. Routing contributes 80.29% of that delay. The preceding
DSP-based run had 19 logic levels and 16.423 ns datapath delay: fewer logic levels
in the new run have not offset its greater routing delay. The bottleneck remains
the memory/control path, outside the multiplier datapath.

| Clock direction, post-route WNS | Before DSP mul/div | DSP mul/div, before RV32A | Current RV32IMA |
|---|---:|---:|---:|
| Core to core (20 ns requirement) | -3.593 ns | -2.821 ns | -3.979 ns |
| Core to BRAM (10 ns requirement) | -6.846 ns | -7.147 ns | -8.237 ns |
| BRAM to core (10 ns requirement) | -3.703 ns | -3.361 ns | -4.715 ns |

Hold and pulse-width timing pass (minimum slacks +0.030 ns and +3.000 ns).
There are no unclocked registers, unconstrained internal endpoints, or valid
timing exceptions; two external input ports and 19 output ports still have no
external delay budgets. All implemented RTL snapshots and recorded input hashes
match the sources used to launch the build. This run does not establish board
functionality or a supported operating frequency. The earlier core-only OOC
closure result does not establish timing closure for the current full SoC.

Instruction latency is measured separately in the atomic latency table above:
LR.W and successful SC.W occupy MEM for five core cycles, reservation-failed
SC.W for three, and each AMO.W for seven, without external stalls. Their atomic
request-to-response-valid latencies are three, three, one, and five cycles,
respectively. These simulation cycle counts and the CoreMark results are not
measured board performance; converting them to time at 50 MHz would assume a
clock configuration that has not passed setup timing.

Current reports, checkpoints, source snapshots, input hashes, device utilization,
and per-clock-pair timing are in `sim/build/vivado_soc_rv32a/`, including
`routed.dcp`, `timing_routed.rpt`, `critical_paths.rpt`, `utilization_device.rpt`,
`clock_paths.tsv`, and `analysis.json`. Reproduce synthesis and implementation with:

```bash
vivado -mode batch -source scripts/implement_soc.tcl -tclargs sim/build/vivado_soc_rv32a nexys4
```

Use a fresh output directory to preserve an existing run. Earlier reports remain
in `sim/build/vivado_soc_muldiv/` and `sim/build/vivado_soc/`; all three build
directories are ignored by Git.

The current wrapper does not implement all declared MMIO signals: GPIO/display
writes and UART RX reads/acknowledgement are incomplete, and unused RX logic is
pruned. The optional RX synchronizer constraint is guarded when its registers
are absent. The address checker limits DMEM accesses to its physical 16 KiB
(`0x10010000`–`0x10013fff`); former aliases now raise access faults. Fetch is
limited to the 32 KiB IROM. Timer registers, UART TX/status and the cycle counter
are decoded with access permissions; unimplemented MMIO accesses raise faults.
A completed implementation describes this connected RTL; it does not establish firmware or board functionality.

---

## Key Design Decisions

- **Dual-issue with in-order commit** keeps implementation complexity low while doubling theoretical IPC on instruction-level-parallel code.
- **BRAM at 2× core frequency** gives single-cycle IMEM/DMEM latency without an instruction cache, which simplifies hazard handling significantly.
- **Gshare branch predictor** reduces branch-misprediction penalties (4-cycle flush) to a few percent overhead on typical workloads.
- **DSP-backed multiply** produces a result two cycles after request acceptance, while the separate divider retains four binary steps per cycle.
