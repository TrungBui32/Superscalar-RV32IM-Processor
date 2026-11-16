# RV32IM Dual-Issue In-Order Pipelined Processor

A personal FPGA implementation of a dual-issue, in-order, 5-stage pipelined RISC-V processor supporting the RV32IM ISA. Targets the Xilinx Nexys 4 (Artix-7) board, synthesised and implemented in Vivado 2019.2.

**Max frequency:** ~50 MHz (post-implementation, Artix-7)  
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
NAPOT decoding uses a trailing-bit mask rather than a chain of conditional
shifts. An all-ones NAPOT address covers the physical space; empty/reversed TOR
ranges do not match. These changes preserve pipeline latency and do not add
CSR-write cycles.

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
