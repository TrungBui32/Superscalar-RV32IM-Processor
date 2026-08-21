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
| System | ECALL, EBREAK |

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
