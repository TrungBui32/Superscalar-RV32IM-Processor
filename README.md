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

Multi-cycle, non-pipelined unit with 8-cycle latency:
- Multiply: Radix-16 Booth's algorithm
- Divide: iterative long-division with loop unrolling

The hazard controller stalls the pipeline when a mul/div is in-flight.

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
│   │   ├── muldiv_unit.v   ← Booth mul + iterative div
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
checks detect a boundary crossed by an RV32 byte/halfword/word access. The fault
address selects an upper bound only for a partial high-end match. Unsupported
access sizes fail closed. An all-ones NAPOT address covers the physical space;
empty/reversed TOR ranges do not match. These changes preserve pipeline latency
and do not add CSR-write cycles.

`pmp_region_cache.v` registers decoded bounds, active bits, and permissions
together, removing raw CSR decoding from the permission-check feedback path.
An accepted PMP CSR write marks the following cycle as refresh pending. Live
MEM work is held and memory accesses/interrupt entry are suppressed until the
cache catches up. The existing control-CSR serialization normally supplies
this bubble; the measured regressions retain their previous cycle counts.
CSR readback still uses the original CSR bank. All 16 entries, address modes,
locking rules, and partial-access faults remain supported.

The combinational PMP entry checks and region decoder have SAT proofs against
byte-interval and arithmetic-bound references. A sequential proof checks cache
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

A Vivado 2023.2 core-only out-of-context implementation on
`xc7a100tcsg324-1`, using a 20 ns clock, 0.1 ns user clock uncertainty, and
`HD.CLK_SRC=BUFGCTRL_X0Y0`, measured the following with the same implementation
flow and timing constraints:

| Post-route metric | Baseline (`426e4e0`) | Forwarding/flush (`6c60c44`) | PMP region cache |
|---|---:|---:|---:|
| Worst setup slack | -16.454 ns | -4.487 ns | -0.919 ns |
| Critical datapath delay | 35.751 ns | 23.969 ns | 20.269 ns |
| Critical logic levels | 45 | 27 | 25 |
| Hold slack | +0.035 ns | +0.037 ns | +0.033 ns |
| LUTs | 19,722 | 19,574 | 19,551 |
| Flip-flops | 6,454 | 6,519 | 7,619 |

Routing completed without errors and hold timing passed. Setup timing still
fails at 50 MHz. The setup-only period estimate improves from 36.454 ns through
24.487 ns to 20.919 ns (about 27.4, 40.8, and 47.8 MHz), not a frequency-sweep
or full-SoC guarantee. The cache trades 1,100 additional flip-flops for timing.
External input/output delays are unconstrained in this core-only run. No
protocol-derived false-path or multicycle exceptions were added. The remaining
worst path runs from a MEM effective-address register through permission,
misaligned-access stall, and CSR-write qualification to a PMP configuration
register's clock enable. The raw PMP decode is no longer on this path.

Cache validation passed 344 ISA/directed runs, two PMA fault runs, four
interrupt-during-refresh cases, the CSR regression, Verilator lint, Yosys
structural checks, and the cache coherence proof. Directed cases include all
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
controller are not implemented. Vivado-generated BRAM/clock IP remains required
for the complete board wrapper.

---

## Simulation

From the `sim/` directory, with Vivado on `PATH`:

```tcl
vivado -mode tcl -source run_sim.tcl
```

`run_sim.tcl` compiles all RTL with `xvlog`/`xvhdl`, elaborates with `xelab`, and launches `xsim`.

---

## Synthesis & Implementation

Open Vivado 2019.2, create a new project targeting `xc7a100tcsg324-1` (Nexys 4) or `xc7a100tdcsg324-1` (Nexys 4 DDR), add all files under `rtl/` and `constraints/nexys4.xdc`, set `rtl/soc/fpga_top.vhd` as the top module, and run the standard implementation flow.

---

## Key Design Decisions

- **Dual-issue with in-order commit** keeps implementation complexity low while doubling theoretical IPC on instruction-level-parallel code.
- **BRAM at 2× core frequency** gives single-cycle IMEM/DMEM latency without an instruction cache, which simplifies hazard handling significantly.
- **Gshare branch predictor** reduces branch-misprediction penalties (4-cycle flush) to a few percent overhead on typical workloads.
- **Radix-16 Booth multiply** completes in 8 cycles, avoiding a 32-cycle naive approach while staying within a single pipeline slot.
