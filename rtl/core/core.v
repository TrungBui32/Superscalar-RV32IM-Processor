`timescale 1ns / 1ps


// Change wire to reg if assigned inside a procedural (always) block. However, where it is easy enough, use assign instead of always.
// A 2-1 multiplexing can be done easily using an assign with a ternary operator
// For multiplexing with number of inputs > 2, a case construct within an always block is a natural fit. DO NOT to use nested ternary assignment operator as it hampers the readability of your code.


module core #(
    parameter PC_INIT = 32'h00400000,
    parameter CSR_FORWARD_ENABLE = 1'b1,
    parameter DEBUG_HALT_ON_EBREAK = 1'b0
) (
    input CLK,
    input RESET,
    // IRQ inputs must be synchronous to CLK (synchronize external pins in SoC).
    input irq_software,
    input irq_timer,
    input irq_external,
    input [63:0] time_value,
    input [31:0] Instr_pipe0,
    input [31:0] Instr_pipe1,
    input [31:0] ReadData_in_pipe0,       // Name mangled to support lb/lbu/lh/lhu
    input [31:0] ReadData_in_pipe1,       // Name mangled to support lb/lbu/lh/lhu_pipe1
    // use pc_en in hazard unit to control WE_PC to wait until this signal high
    input locked,               // from clocking wizard to indicate stable clock, just run after this is high
    input imem_ready,
    input dmem_ready,    
    output MemRead,
    output [2:0] MemWrite_out_pipe0,		// Column-wise write enable to support sb/sw. Each column is a byte.
    output [2:0] MemWrite_out_pipe1,		// Column-wise write enable to support sb/sw. Each column is a byte.
    output [31:0] PC,
    output [31:0] ALUResult_pipe0,
    output [31:0] ALUResult_pipe1,
    output [31:0] WriteData_out_pipe0,		// Name mangled to support sb/sw
    output [31:0] WriteData_out_pipe1,
    output [4:0] LwSizeSel_pipe0,
    output [4:0] LwSizeSel_pipe1
    );
    localparam R_type_opcode = 7'b0110011;
    localparam sw_opcode  = 7'b0100011;
    localparam lw_opcode  = 7'b0000011;
    localparam jal_opcode = 7'b1101111;
    localparam jalr_opcode= 7'b1100111;
    localparam branch_opcode = 7'b1100011;
    localparam CSR_opcode    = 7'b1110011;

    localparam Funct3_sw  = 3'b010;
    localparam Funct3_lw  = 3'b010;
    localparam Funct3_mul = 3'b000; // for mul
    localparam Funct3_mulh = 3'b001; // for mulh
    localparam Funct3_mulu = 3'b011; // for mulu
    localparam Funct3_mulsu = 3'b010; // for mulsu
    localparam Funct3_div = 3'b100; // for div
    localparam Funct3_divu = 3'b101; // for divu
    localparam Funct3_rem = 3'b110; // for rem
    localparam Funct3_remu = 3'b111; // for remu
    localparam Func3_CSRRW = 3'b001;
    localparam Func3_CSRRS = 3'b010;
    localparam Func3_CSRRC = 3'b011;
    localparam Func3_CSRRWI = 3'b101;
    localparam Func3_CSRRSI = 3'b110;
    localparam Func3_CSRRCI = 3'b111;

    // Forwarding Unit parameters
    parameter SEL_IDEX  = 4'b0000; // use ID/EX value
    parameter SEL_ALU_EXMEM_PIPE0 = 4'b0001; // use EX/MEM ALU result
    parameter SEL_ALU_MEMWB_PIPE0 = 4'b0010;  //use MEM/WB ALU result
    parameter SEL_MCYCLE_EXMEM_PIPE0 = 4'b0011;
    parameter SEL_MCYCLE_MEMWB_PIPE0 = 4'b0100;
    parameter SEL_LW_MEMWB_PIPE0 = 4'b0101;
    parameter SEL_LW_MEMWB_PIPE1 = 4'b0110;
    parameter SEL_ALU_EXMEM_PIPE1 = 4'b0111; // use EX/MEM ALU result
    parameter SEL_ALU_MEMWB_PIPE1 = 4'b1000;  //use MEM/WB ALU result
    parameter SEL_MCYCLE_EXMEM_PIPE1 = 4'b1001;
    parameter SEL_MCYCLE_MEMWB_PIPE1 = 4'b1010;



    wire valid_id_pipe0;
    wire illegal_id_pipe0;
    wire valid_ex_pipe0, illegal_ex_pipe0;
    wire [31:0] instruction_ex_pipe0;
    wire valid_mem_pipe0, illegal_mem_pipe0;
    wire [31:0] instruction_mem_pipe0;
    wire valid_wb_pipe0, illegal_wb_pipe0;
    wire [31:0] instruction_wb_pipe0;
    wire csr_wvalid_wb_pipe0;
    wire valid_id_pipe1;
    wire illegal_id_pipe1;
    wire valid_ex_pipe1, illegal_ex_pipe1;
    wire [31:0] instruction_ex_pipe1;
    wire valid_mem_pipe1, illegal_mem_pipe1;
    wire [31:0] instruction_mem_pipe1;
    wire valid_wb_pipe1, illegal_wb_pipe1;
    wire [31:0] instruction_wb_pipe1;
    wire csr_wvalid_wb_pipe1;

    //RV Signals
    wire [31:0] ReadData;
    wire [31:0] WriteData;
    wire imem_stall;
    assign imem_stall = !imem_ready;
    wire dmem_stall;
    assign dmem_stall = !dmem_ready;

    // The signals that are commented out (except CLK) will need to be uncommented and attached a stage suffix for pipelining,
    //  except if the connection is within the same stage.

    // RegFile signals
    wire       WE_pipe0;
    wire       WE_pipe1;
    reg [31:0] WD_pipe0;
    reg [31:0] WD_pipe1;

    wire IF_ID_en_pipe0;
    wire IF_ID_flush_pipe0;
    wire ID_EX_en_pipe0;
    wire ID_EX_flush_pipe0;
    wire EX_MEM_en_pipe0;
    wire EX_MEM_flush_pipe0;
    wire MEM_WB_en_pipe0;
    wire MEM_WB_flush_pipe0;

    wire IF_ID_en_pipe1;
    wire IF_ID_flush_pipe1;
    wire ID_EX_en_pipe1;
    wire ID_EX_flush_pipe1;
    wire EX_MEM_en_pipe1;
    wire EX_MEM_flush_pipe1;
    wire MEM_WB_en_pipe1;
    wire MEM_WB_flush_pipe1;


    // IF stage signals
    wire [31:0] PC_reg;
    assign PC = PC_reg;

    wire [31:0] pc_if_pipe0;
    assign pc_if_pipe0 = PC_reg;

    wire [31:0] pcplus4_if_pipe0;
    assign pcplus4_if_pipe0 = pc_if_pipe0 + 32'h00000004;

    wire [31:0] pc_if_pipe1;
    assign pc_if_pipe1 = PC_reg + 32'h00000004;

    wire [31:0] pcplus4_if_pipe1;
    assign pcplus4_if_pipe1 = pc_if_pipe1 + 32'h00000004;

    wire [31:0] Instr_if_pipe0;
    assign Instr_if_pipe0 = Instr_pipe0;

    wire [31:0] Instr_if_pipe1;
    assign Instr_if_pipe1 = Instr_pipe1;

    wire is_ebreak_if_pipe0;
    assign is_ebreak_if_pipe0 = (DEBUG_HALT_ON_EBREAK && Instr_if_pipe0 == 32'h00100073);

    wire is_ebreak_if_pipe1;
    assign is_ebreak_if_pipe1 = (DEBUG_HALT_ON_EBREAK && Instr_if_pipe1 == 32'h00100073);

    
    wire branch_pred_if;
    reg  [31:0] pc_if_branch_prediction;
    wire [31:0] branch_pred_target_if;

    // Branch and Jump detection in IF stage for branch prediction for pipe0
    wire is_cond_jump_if_pipe0;
    assign is_cond_jump_if_pipe0 = (Instr_if_pipe0[6:0] == branch_opcode) ? 1'b1 : 1'b0;

    wire is_jal_if_pipe0;
    assign is_jal_if_pipe0 = (Instr_if_pipe0[6:0] == jal_opcode) ? 1'b1 : 1'b0;
    
    wire is_jalr_if_pipe0;
    assign is_jalr_if_pipe0 = (Instr_if_pipe0[6:0] == jalr_opcode) ? 1'b1 : 1'b0;

    wire is_branch_if_pipe0;
    assign is_branch_if_pipe0 = (is_cond_jump_if_pipe0 || is_jal_if_pipe0 || is_jalr_if_pipe0) ? 1'b1 : 1'b0;

    wire is_jump_if_pipe0;
    assign is_jump_if_pipe0 = (is_jal_if_pipe0 || is_jalr_if_pipe0);


    wire is_call_if_pipe0;
    assign is_call_if_pipe0 = (is_jal_if_pipe0) && (Instr_if_pipe0[11:7] == 5'd1 || Instr_if_pipe0[11:7] == 5'd5) ? 1'b1 : 1'b0;

    wire is_return_if_pipe0;
    assign is_return_if_pipe0 = (is_jalr_if_pipe0) && (Instr_if_pipe0[19:15] == 5'd1 || Instr_if_pipe0[19:15] == 5'd5) && (Instr_if_pipe0[11:7] == 5'd0) ? 1'b1 : 1'b0;

    wire branch_pred_if_pipe0;
    assign branch_pred_if_pipe0 = branch_pred_if;

    wire [31:0] branch_pred_target_if_pipe0;
    assign branch_pred_target_if_pipe0 = branch_pred_target_if;


    // Branch and Jump detection in IF stage for branch prediction for pipe1
    wire is_jal_if_pipe1;
    assign is_jal_if_pipe1 = (Instr_if_pipe1[6:0] == jal_opcode) ? 1'b1 : 1'b0;

    wire is_jalr_if_pipe1;
    assign is_jalr_if_pipe1 = (Instr_if_pipe1[6:0] == jalr_opcode) ? 1'b1 : 1'b0;

    wire is_cond_jump_if_pipe1;
    assign is_cond_jump_if_pipe1 = (Instr_if_pipe1[6:0] == branch_opcode) ? 1'b1 : 1'b0;

    wire is_branch_if_pipe1;
    assign is_branch_if_pipe1 = (is_cond_jump_if_pipe1 || is_jal_if_pipe1 || is_jalr_if_pipe1) ? 1'b1 : 1'b0;

    wire is_jump_if_pipe1;
    assign is_jump_if_pipe1 = (is_jal_if_pipe1 || is_jalr_if_pipe1);


    wire is_call_if_pipe1;
    assign is_call_if_pipe1 = (is_jal_if_pipe1) && (Instr_if_pipe1[11:7] == 5'd1 || Instr_if_pipe1[11:7] == 5'd5) ? 1'b1 : 1'b0;

    wire is_return_if_pipe1;
    assign is_return_if_pipe1 = (is_jalr_if_pipe1) && (Instr_if_pipe1[19:15] == 5'd1 || Instr_if_pipe1[19:15] == 5'd5) && (Instr_if_pipe1[11:7] == 5'd0) ? 1'b1 : 1'b0;

    wire branch_pred_if_pipe1;
    assign branch_pred_if_pipe1 = branch_pred_if;

    wire [31:0] branch_pred_target_if_pipe1;
    assign branch_pred_target_if_pipe1 = branch_pred_target_if;


    wire is_jump_if;
    assign is_jump_if = (is_jump_if_pipe0 || is_jump_if_pipe1);
    wire is_branch_if;
    assign is_branch_if = (is_branch_if_pipe0 || is_branch_if_pipe1);
    wire is_call_if;
    assign is_call_if = (is_branch_if_pipe0)? is_call_if_pipe0 : is_call_if_pipe1;
    wire is_return_if;
    assign is_return_if = (is_branch_if_pipe0)? is_return_if_pipe0 : is_return_if_pipe1;

    // ID stage signals
    wire [31:0] pc_id_pipe0;
    wire [31:0] pcplus4_id_pipe0;
    wire [31:0] Instr_id_pipe0;
    wire [6:0] opcode_id_pipe0;
    wire [2:0] funct3_id_pipe0;
    wire [6:0] funct7_id_pipe0;

    wire [31:0] pc_id_pipe1;
    wire [31:0] pcplus4_id_pipe1;
    wire [31:0] Instr_id_pipe1;
    wire [6:0] opcode_id_pipe1;
    wire [2:0] funct3_id_pipe1;
    wire [6:0] funct7_id_pipe1;

    wire is_cond_jump_id_pipe0;
    wire is_jal_id_pipe0;
    wire is_jalr_id_pipe0;

    wire RegWrite_id_pipe0;
    wire MemRead_id_pipe0;
    wire [2:0] MemWrite_id_pipe0;
    wire MemtoReg_id_pipe0;
    wire [4:0] LwSizeSel_id_pipe0;

    wire is_R_type_id_pipe0;
    assign is_R_type_id_pipe0 = (opcode_id_pipe0 == R_type_opcode);

    wire is_cond_jump_id_pipe1;
    wire is_jal_id_pipe1;
    wire is_jalr_id_pipe1;

    wire RegWrite_id_pipe1;
    wire MemRead_id_pipe1;
    wire [2:0] MemWrite_id_pipe1;
    wire MemtoReg_id_pipe1;
    wire [4:0] LwSizeSel_id_pipe1;

    wire is_R_type_id_pipe1;
    assign is_R_type_id_pipe1 = (opcode_id_pipe1 == R_type_opcode);


    wire [1:0] ALUSrcA_id_pipe0;
    wire [1:0] ALUSrcB_id_pipe0;
    wire [2:0] ImmSrc_id_pipe0;
    wire [24:0] InstrImm_id_pipe0;


    wire [1:0] ALUSrcA_id_pipe1;
    wire [1:0] ALUSrcB_id_pipe1;
    wire [2:0] ImmSrc_id_pipe1;
    wire [24:0] InstrImm_id_pipe1;


    wire [31:0] ExtImm_id_pipe0;
    wire [3:0] ALUControl_id_pipe0;
    wire [4:0] rs1_id_pipe0;
    wire [4:0] rs2_id_pipe0;
    wire [4:0] rd_id_pipe0;
    wire [31:0] RD1_id_pipe0;
    wire [31:0] RD2_id_pipe0;


    wire [31:0] ExtImm_id_pipe1;
    wire [3:0] ALUControl_id_pipe1;
    wire [4:0] rs1_id_pipe1;
    wire [4:0] rs2_id_pipe1;
    wire [4:0] rd_id_pipe1;
    wire [31:0] RD1_id_pipe1;
    wire [31:0] RD2_id_pipe1;


    reg  [31:0] rs1_val_id_pipe0;
    reg  [31:0] rs2_val_id_pipe0;
    reg [31:0] PC_branch_id_pipe0;

    reg  [31:0] rs1_val_id_pipe1;
    reg  [31:0] rs2_val_id_pipe1;
    reg [31:0] PC_branch_id_pipe1;


    wire MCycle_id_pipe0; // Start signal from Decoder
    wire [1:0] MCycleOp_id_pipe0; // Multi-cycle operation from Decoder
    

    wire MCycle_id_pipe1; // Start signal from Decoder
    wire [1:0] MCycleOp_id_pipe1; // Multi-cycle operation from Decoder


    wire branch_pred_id_pipe0;
    wire [31:0] branch_pred_target_id_pipe0;
    wire is_ebreak_id_pipe0;

    wire branch_pred_id_pipe1;
    wire [31:0] branch_pred_target_id_pipe1;
    wire is_ebreak_id_pipe1;

    wire id_is_store_pipe0;
    assign id_is_store_pipe0 = (MemWrite_id_pipe0)? 1'b1 : 1'b0;

    wire id_is_store_pipe1;
    assign id_is_store_pipe1 = (MemWrite_id_pipe1)? 1'b1 : 1'b0;

    wire [11:0] csr_addr_id_pipe0;
    wire [31:0] csr_rdata_id_pipe0;
    wire csr_rvalid_id_pipe0;
    wire csr_wvalid_id_pipe0;
    wire csr_rillegal_id_pipe0;
    wire csr_rillegal_bank_id_pipe0;
    wire uses_rs1_id_pipe0;
    wire uses_rs2_id_pipe0;
    wire [11:0] csr_addr_id_pipe1;
    wire [31:0] csr_rdata_id_pipe1;
    wire csr_rvalid_id_pipe1;
    wire csr_wvalid_id_pipe1;
    wire csr_rillegal_id_pipe1;
    wire csr_rillegal_bank_id_pipe1;
    wire uses_rs1_id_pipe1;
    wire uses_rs2_id_pipe1;

    //EX stage signals
    wire [31:0] pc_ex_pipe0;
    wire [31:0] pcplus4_ex_pipe0;
    wire [31:0] rs1_val_ex_pipe0;
    wire [31:0] rs2_val_ex_pipe0;
    wire [31:0] imm_ex_pipe0;
    wire [4:0]  rs1_idx_ex_pipe0;
    wire [4:0]  rs2_idx_ex_pipe0;
    wire [4:0]  rd_idx_ex_pipe0;
    wire [2:0]  funct3_ex_pipe0;
    wire [6:0]  opcode_ex_pipe0;
    wire         RegWrite_ex_pipe0;
    wire [2:0]   MemWrite_ex_pipe0;
    wire         MemRead_ex_pipe0;
    wire         MemToReg_ex_pipe0;
    wire [4:0]   LwSizeSel_ex_pipe0;

    wire         is_cond_jump_ex_pipe0;
    wire         is_jal_ex_pipe0;
    wire         is_jalr_ex_pipe0;
    wire         is_ebreak_ex_pipe0;

    wire [31:0] pc_ex_pipe1;
    wire [31:0] pcplus4_ex_pipe1;
    wire [31:0] rs1_val_ex_pipe1;
    wire [31:0] rs2_val_ex_pipe1;
    wire [31:0] imm_ex_pipe1;
    wire [4:0]  rs1_idx_ex_pipe1;
    wire [4:0]  rs2_idx_ex_pipe1;
    wire [4:0]  rd_idx_ex_pipe1;
    wire [2:0]  funct3_ex_pipe1;
    wire [6:0]  opcode_ex_pipe1;
    wire         RegWrite_ex_pipe1;
    wire [2:0]   MemWrite_ex_pipe1;
    wire         MemRead_ex_pipe1;
    wire         MemToReg_ex_pipe1;
    wire [4:0]   LwSizeSel_ex_pipe1;

    wire         is_cond_jump_ex_pipe1;
    wire         is_jal_ex_pipe1;
    wire         is_jalr_ex_pipe1;
    wire         is_ebreak_ex_pipe1;


    wire [1:0]   AluSrcA_ex_pipe0;
    wire [1:0]   AluSrcB_ex_pipe0;
    wire [3:0]   AluOp_ex_pipe0;
    wire [31:0] ALUResult_ex_pipe0;
    wire [31:0] alu_out_ex_pipe0;
    wire [2:0] ALUFlags_ex_pipe0;

    wire [1:0]   AluSrcA_ex_pipe1;
    wire [1:0]   AluSrcB_ex_pipe1;
    wire [3:0]   AluOp_ex_pipe1;
    wire [31:0] ALUResult_ex_pipe1;
    wire [31:0] alu_out_ex_pipe1;
    wire [2:0] ALUFlags_ex_pipe1;


    wire         MCycle_ex_pipe0;
    wire [1:0]   MCycleOp_ex_pipe0;
    reg [31:0] MCycle_Result_ex_pipe0;

    wire         MCycle_ex_pipe1;
    wire [1:0]   MCycleOp_ex_pipe1;
    reg [31:0] MCycle_Result_ex_pipe1;

    wire [31:0] store_data_ex_pipe0;

    wire [31:0] store_data_ex_pipe1;


    reg [31:0] PC_branch_ex_pipe0;
    wire  [3:0]  sel_EX_store_data_pipe0;

    reg [31:0] PC_branch_ex_pipe1;
    wire  [3:0]  sel_EX_store_data_pipe1;


    wire branch_pred_ex_pipe0;
    wire [31:0] branch_pred_target_ex_pipe0;

    wire branch_pred_ex_pipe1;
    wire [31:0] branch_pred_target_ex_pipe1;

    wire ex_is_store_pipe0;
    assign ex_is_store_pipe0 = (MemWrite_ex_pipe0)? 1'b1 : 1'b0;

    wire ex_is_store_pipe1;
    assign ex_is_store_pipe1 = (MemWrite_ex_pipe1)? 1'b1 : 1'b0;

    wire [11:0] csr_addr_ex_pipe0;
    wire [31:0] csr_rdata_ex_pipe0;
    wire [31:0] csr_wdata_ex_pipe0;
    wire csr_wvalid_ex_pipe0;
    wire csr_rillegal_ex_pipe0;
    wire csr_rvalid_ex_pipe0;
    wire [11:0] csr_addr_ex_pipe1;
    wire [31:0] csr_rdata_ex_pipe1;
    wire [31:0] csr_wdata_ex_pipe1;
    wire csr_wvalid_ex_pipe1;
    wire csr_rillegal_ex_pipe1;
    wire csr_rvalid_ex_pipe1;

    //MEM stage signals
    reg [31:0] mem_rdata_mem_pipe0;
    wire [31:0] pc_mem_pipe0;
    wire [31:0] pcplus4_mem_pipe0;
    wire [31:0] alu_out_mem_pipe0;
    wire [4:0] store_idx_mem_pipe0;
    wire [31:0] store_data_mem_pipe0;
    wire        MCycle_mem_pipe0;
    wire [31:0] MCycle_Result_mem_pipe0;
    
    wire        is_cond_jump_mem_pipe0;
    wire        is_jal_mem_pipe0;
    wire        is_jalr_mem_pipe0;
    wire [31:0] PC_branch_mem_pipe0;
    wire [31:0] branch_pred_target_mem_pipe0;
    wire        is_ebreak_mem_pipe0;
    
    wire        is_jal_jalr_mem_pipe0;
    assign is_jal_jalr_mem_pipe0 = is_jal_mem_pipe0 || is_jalr_mem_pipe0;

    reg [31:0] mem_rdata_mem_pipe1;
    wire [31:0] pc_mem_pipe1;
    wire [31:0] pcplus4_mem_pipe1;
    wire [31:0] alu_out_mem_pipe1;
    wire [4:0] store_idx_mem_pipe1;
    wire [31:0] store_data_mem_pipe1;
    wire        MCycle_mem_pipe1;
    wire [31:0] MCycle_Result_mem_pipe1;

    wire        is_cond_jump_mem_pipe1;
    wire        is_jal_mem_pipe1;
    wire        is_jalr_mem_pipe1;
    wire [31:0] PC_branch_mem_pipe1;
    wire [31:0] branch_pred_target_mem_pipe1;
    wire        is_ebreak_mem_pipe1;

    wire        is_jal_jalr_mem_pipe1;
    assign is_jal_jalr_mem_pipe1 = is_jal_mem_pipe1 || is_jalr_mem_pipe1;


    wire [4:0] rd_idx_mem_pipe0;
    wire [2:0] funct3_mem_pipe0;
    wire [6:0] opcode_mem_pipe0;
    wire        RegWrite_mem_pipe0;
    wire [2:0]  MemWrite_mem_pipe0;
    wire        MemRead_mem_pipe0;
    wire        MemToReg_mem_pipe0;
    wire [4:0]  LwSizeSel_mem_pipe0;
    wire [3:0]  sel_MEM_store_data_pipe0;

    wire [2:0] ALUFlags_mem_pipe0;
    wire [1:0] PCSrc_mem_pipe0;

    wire [2:0] ALUFlags_mem_pipe1;
    wire [1:0] PCSrc_mem_pipe1;

    wire [4:0]  rd_idx_mem_pipe1;
    wire [2:0]  funct3_mem_pipe1;
    wire [6:0]  opcode_mem_pipe1;
    wire        RegWrite_mem_pipe1;
    wire [2:0]  MemWrite_mem_pipe1;
    wire        MemRead_mem_pipe1;
    wire        MemToReg_mem_pipe1;
    wire [4:0]  LwSizeSel_mem_pipe1;
    wire [3:0]  sel_MEM_store_data_pipe1;

    wire [11:0] csr_waddr_mem_pipe0;
    wire [31:0] csr_wdata_mem_pipe0;
    wire [31:0] csr_rdata_mem_pipe0;
    wire csr_wvalid_mem_pipe0; // intent latched in EX/MEM
    wire csr_wfire_mem_pipe0; // qualified request sent to the bank
    wire csr_rillegal_mem_pipe0;
    wire csr_willegal_mem_pipe0;
    wire csr_rvalid_mem_pipe0;
    wire csr_error_mem_pipe0;
    wire [31:0] csr_rdata_wb_pipe0;
    wire csr_rvalid_wb_pipe0;
    wire [11:0] csr_waddr_mem_pipe1;
    wire [31:0] csr_wdata_mem_pipe1;
    wire [31:0] csr_rdata_mem_pipe1;
    wire csr_wvalid_mem_pipe1; // intent latched in EX/MEM
    wire csr_wfire_mem_pipe1; // qualified request sent to the bank
    wire csr_rillegal_mem_pipe1;
    wire csr_willegal_mem_pipe1;
    wire csr_rvalid_mem_pipe1;
    wire csr_error_mem_pipe1;
    wire [31:0] csr_rdata_wb_pipe1;
    wire csr_rvalid_wb_pipe1;

    //WB stage signals
    wire [31:0] pcplus4_wb_pipe0;
    wire [31:0] mem_rdata_wb_pipe0;
    wire [31:0] alu_out_wb_pipe0;
    wire        MCycle_wb_pipe0;
    wire [31:0] MCycle_Result_wb_pipe0;
    wire [4:0]  rd_idx_wb_pipe0;
    wire [2:0]  funct3_wb_pipe0;
    wire [6:0]  opcode_wb_pipe0;
    wire        RegWrite_wb_pipe0;
    wire        MemToReg_wb_pipe0;
    wire is_ebreak_wb_pipe0;

    wire [31:0] pcplus4_wb_pipe1;
    wire [31:0] mem_rdata_wb_pipe1;
    wire [31:0] alu_out_wb_pipe1;
    wire        MCycle_wb_pipe1;
    wire [31:0] MCycle_Result_wb_pipe1;
    wire [4:0]  rd_idx_wb_pipe1;
    wire [2:0]  funct3_wb_pipe1;
    wire [6:0]  opcode_wb_pipe1;
    wire        RegWrite_wb_pipe1;
    wire        MemToReg_wb_pipe1;
    wire is_ebreak_wb_pipe1;

    wire is_ebreak_wb;
    assign is_ebreak_wb = is_ebreak_wb_pipe0 || is_ebreak_wb_pipe1;

    // ALU signals

    reg [31:0] Src_A_pipe0;
    reg [31:0] Src_B_pipe0;

    reg [31:0] Src_A_pipe1;
    reg [31:0] Src_B_pipe1;

    reg [31:0] Src_A_MCycle;
    reg [31:0] Src_B_MCycle;

    assign ALUResult_pipe0 = alu_out_mem_pipe0;
    assign ALUResult_pipe1 = alu_out_mem_pipe1;

    
    // ProgramCounter signals
    wire WE_PC;    
    wire [31:0] PC_IN;
        
    // Other internal signals here
    reg [31:0] PC_value;

    assign MemRead = MemRead_mem_pipe0 || MemRead_mem_pipe1; // Memory read signal
    assign WE_pipe0 = RegWrite_wb_pipe0; // Write enable for RegFile
    assign WE_pipe1 = RegWrite_wb_pipe1; // Write enable for RegFile
    assign LwSizeSel_pipe0 = LwSizeSel_mem_pipe0;
    assign LwSizeSel_pipe1 = LwSizeSel_mem_pipe1;

    always @(*) begin
        case(LwSizeSel_mem_pipe0)
            5'b00001: mem_rdata_mem_pipe0 = {{24{ReadData_in_pipe0[7]}}, ReadData_in_pipe0[7:0]}; // lb
            5'b00010: mem_rdata_mem_pipe0 = {{16{ReadData_in_pipe0[15]}}, ReadData_in_pipe0[15:0]}; // lh
            5'b00100: mem_rdata_mem_pipe0 = ReadData_in_pipe0[31:0]; // lw
            5'b01000: mem_rdata_mem_pipe0 = {24'b0, ReadData_in_pipe0[7:0]}; // lbu
            5'b10000: mem_rdata_mem_pipe0 = {16'b0, ReadData_in_pipe0[15:0]}; // lhu
            default: mem_rdata_mem_pipe0 = 32'b0; // should not occur
        endcase
    end


    always @(*) begin
        case(LwSizeSel_mem_pipe1)
            5'b00001: mem_rdata_mem_pipe1 = {{24{ReadData_in_pipe1[7]}}, ReadData_in_pipe1[7:0]}; // lb
            5'b00010: mem_rdata_mem_pipe1 = {{16{ReadData_in_pipe1[15]}}, ReadData_in_pipe1[15:0]}; // lh
            5'b00100: mem_rdata_mem_pipe1 = ReadData_in_pipe1[31:0]; // lw
            5'b01000: mem_rdata_mem_pipe1 = {24'b0, ReadData_in_pipe1[7:0]}; // lbu
            5'b10000: mem_rdata_mem_pipe1 = {16'b0, ReadData_in_pipe1[15:0]}; // lhu
            default: mem_rdata_mem_pipe1 = 32'b0; // should not occur
        endcase
    end

    // WriteData logic
    assign WriteData_out_pipe0 = store_data_mem_pipe0;    // Change datapath as appropriate if supporting sb/sh
    assign MemWrite_out_pipe0 = (MEM_WB_en_pipe0 && !MEM_WB_flush_pipe0)? MemWrite_mem_pipe0 : 3'b000; // Change datapath as appropriate if supporting sb/sh
    reg [31:0] rs2_val_ex_forward_pipe0;
    assign store_data_ex_pipe0 = rs2_val_ex_forward_pipe0;

    // Forwarding logic for store data in EX stage
    wire [3:0] forward_selA_ex_pipe0;
    wire [3:0] forward_selB_ex_pipe0;



    always @(*) begin
            case (forward_selB_ex_pipe0)
                SEL_MCYCLE_EXMEM_PIPE1: rs2_val_ex_forward_pipe0 = MCycle_Result_mem_pipe1[31:0];
                SEL_MCYCLE_EXMEM_PIPE0: rs2_val_ex_forward_pipe0 = MCycle_Result_mem_pipe0[31:0];
                SEL_ALU_EXMEM_PIPE1: rs2_val_ex_forward_pipe0 = alu_out_mem_pipe1;
                SEL_ALU_EXMEM_PIPE0: rs2_val_ex_forward_pipe0 = alu_out_mem_pipe0;
                SEL_MCYCLE_MEMWB_PIPE1: rs2_val_ex_forward_pipe0 = MCycle_Result_wb_pipe1[31:0];
                SEL_MCYCLE_MEMWB_PIPE0: rs2_val_ex_forward_pipe0 = MCycle_Result_wb_pipe0[31:0];
                SEL_ALU_MEMWB_PIPE1: rs2_val_ex_forward_pipe0 = alu_out_wb_pipe1;
                SEL_ALU_MEMWB_PIPE0: rs2_val_ex_forward_pipe0 = alu_out_wb_pipe0;
                SEL_LW_MEMWB_PIPE1: rs2_val_ex_forward_pipe0 = mem_rdata_wb_pipe1;
                SEL_LW_MEMWB_PIPE0: rs2_val_ex_forward_pipe0 = mem_rdata_wb_pipe0;
                SEL_IDEX: rs2_val_ex_forward_pipe0 = rs2_val_ex_pipe0;
                default: rs2_val_ex_forward_pipe0 = 32'bx;
            endcase    
    end

    // WriteData logic
    assign WriteData_out_pipe1 = store_data_mem_pipe1;    // Change datapath as appropriate if supporting sb/sh
    assign MemWrite_out_pipe1 = (MEM_WB_en_pipe1 && !MEM_WB_flush_pipe1)? MemWrite_mem_pipe1 : 3'b000; // Change datapath as appropriate if supporting sb/sh
    reg [31:0] rs2_val_ex_forward_pipe1;
    assign store_data_ex_pipe1 = rs2_val_ex_forward_pipe1;

    wire [3:0] forward_selA_ex_pipe1;
    wire [3:0] forward_selB_ex_pipe1;

    always @(*) begin
        case (forward_selB_ex_pipe1)
                SEL_MCYCLE_EXMEM_PIPE1: rs2_val_ex_forward_pipe1 = MCycle_Result_mem_pipe1[31:0];
                SEL_MCYCLE_EXMEM_PIPE0: rs2_val_ex_forward_pipe1 = MCycle_Result_mem_pipe0[31:0];
                SEL_ALU_EXMEM_PIPE1: rs2_val_ex_forward_pipe1 = alu_out_mem_pipe1;
                SEL_ALU_EXMEM_PIPE0: rs2_val_ex_forward_pipe1 = alu_out_mem_pipe0;
                SEL_MCYCLE_MEMWB_PIPE1: rs2_val_ex_forward_pipe1 = MCycle_Result_wb_pipe1[31:0];
                SEL_MCYCLE_MEMWB_PIPE0: rs2_val_ex_forward_pipe1 = MCycle_Result_wb_pipe0[31:0];
                SEL_ALU_MEMWB_PIPE1: rs2_val_ex_forward_pipe1 = alu_out_wb_pipe1;
                SEL_ALU_MEMWB_PIPE0: rs2_val_ex_forward_pipe1 = alu_out_wb_pipe0;
                SEL_LW_MEMWB_PIPE1: rs2_val_ex_forward_pipe1 = mem_rdata_wb_pipe1;
                SEL_LW_MEMWB_PIPE0: rs2_val_ex_forward_pipe1 = mem_rdata_wb_pipe0;
                SEL_IDEX: rs2_val_ex_forward_pipe1 = rs2_val_ex_pipe1;
                default: rs2_val_ex_forward_pipe1 = 32'bx;
        endcase
    end

    // todo: other datapath connections here
    //decode connections
    assign opcode_id_pipe0 = Instr_id_pipe0[6:0];
    assign funct3_id_pipe0 = Instr_id_pipe0[14:12];
    assign funct7_id_pipe0 = Instr_id_pipe0[31:25];

    //register file connections
    assign rs1_id_pipe0 = Instr_id_pipe0[19:15];
    assign rs2_id_pipe0 = Instr_id_pipe0[24:20];
    assign rd_id_pipe0 = Instr_id_pipe0[11:7];

    //decode connections
    assign opcode_id_pipe1 = Instr_id_pipe1[6:0];
    assign funct3_id_pipe1 = Instr_id_pipe1[14:12];
    assign funct7_id_pipe1 = Instr_id_pipe1[31:25];

    //register file connections
    assign rs1_id_pipe1 = Instr_id_pipe1[19:15];
    assign rs2_id_pipe1 = Instr_id_pipe1[24:20];
    assign rd_id_pipe1 = Instr_id_pipe1[11:7];

    wire branch_pred_mem_pipe0;
    wire branch_pred_mem_pipe1;

    wire [127:0] pmp_config;
    wire [511:0] pmp_address;
    wire [1:0] pmp_fetch_allow, pmp_data_allow;
    wire [31:0] pmp_badaddr0, pmp_badaddr1;
    pmp_check pmp_fetch0(.config_bytes(pmp_config), .addresses(pmp_address),
        .address(pc_mem_pipe0), .size(3'd4), .access_type(3'b100),
        .allow(pmp_fetch_allow[0]), .fault_address());
    pmp_check pmp_data0(.config_bytes(pmp_config), .addresses(pmp_address),
        .address(alu_out_mem_pipe0), .size(3'd1 << funct3_mem_pipe0[1:0]),
        .access_type(MemRead_mem_pipe0 ? 3'b001 : 3'b010),
        .allow(pmp_data_allow[0]), .fault_address(pmp_badaddr0));
    pmp_check pmp_fetch1(.config_bytes(pmp_config), .addresses(pmp_address),
        .address(pc_mem_pipe1), .size(3'd4), .access_type(3'b100),
        .allow(pmp_fetch_allow[1]), .fault_address());
    pmp_check pmp_data1(.config_bytes(pmp_config), .addresses(pmp_address),
        .address(alu_out_mem_pipe1), .size(3'd1 << funct3_mem_pipe1[1:0]),
        .access_type(MemRead_mem_pipe1 ? 3'b001 : 3'b010),
        .allow(pmp_data_allow[1]), .fault_address(pmp_badaddr1));
    // Control CSR writes remain barriers; data CSR accesses bypass older
    // EX/MEM writes. One CSR per issue group keeps same-cycle RMW ordered.
    wire csr_wait, csr_split;
    wire csr_trap_pipe0, csr_trap_pipe1, csr_trap_fire;
    wire [31:0] csr_trap_pc, csr_trap_vector;
    wire [3:0] csr_forward_valid;
    wire [47:0] csr_forward_addr;
    wire [127:0] csr_forward_data;
    wire pipeline_can_advance = locked && imem_ready && dmem_ready &&
                                !MCycle_Busy && !is_ebreak_wb && !RESET;
    wire csr_pending = csr_rvalid_ex_pipe0 || csr_rvalid_ex_pipe1 ||
                       csr_rvalid_mem_pipe0 || csr_rvalid_mem_pipe1;
    wire csr_older_pending = valid_ex_pipe0 || valid_ex_pipe1 || valid_mem_pipe0 || valid_mem_pipe1;
    function csr_control_write;
        input [11:0] addr;
        begin
            case (addr)
                12'h300, 12'h100, 12'h301, 12'h302, 12'h303,
                12'h304, 12'h104, 12'h344, 12'h144,
                12'h305, 12'h105, 12'h306, 12'h106:
                    csr_control_write = 1'b1;
                default: csr_control_write = (addr >= 12'h3a0 && addr <= 12'h3bf);
            endcase
        end
    endfunction
    function serial_instruction;
        input [31:0] insn;
        begin
            serial_instruction = (insn[6:0] == 7'h73 && insn[14:12] == 0) ||
                                 (insn[6:0] == 7'h0f);
        end
    endfunction
    function counter_access;
        input [11:0] addr;
        begin counter_access = addr[11:8] == 4'hb || addr[11:8] == 4'hc || addr == 12'h320; end
    endfunction
    wire system_requested =
        (valid_id_pipe0 && (serial_instruction(Instr_id_pipe0) || illegal_id_pipe0)) ||
        (valid_id_pipe1 && (serial_instruction(Instr_id_pipe1) || illegal_id_pipe1));
    wire system_pending =
        (valid_ex_pipe0 && (serial_instruction(instruction_ex_pipe0) || illegal_ex_pipe0)) ||
        (valid_ex_pipe1 && (serial_instruction(instruction_ex_pipe1) || illegal_ex_pipe1)) ||
        (valid_mem_pipe0 && (serial_instruction(instruction_mem_pipe0) || illegal_mem_pipe0)) ||
        (valid_mem_pipe1 && (serial_instruction(instruction_mem_pipe1) || illegal_mem_pipe1));
    wire counter_requested = (csr_rvalid_id_pipe0 && counter_access(csr_addr_id_pipe0)) ||
                             (csr_rvalid_id_pipe1 && counter_access(csr_addr_id_pipe1));
    wire wb_pending = valid_wb_pipe0 || valid_wb_pipe1;
    wire irq_pending;
    wire [31:0] irq_cause;
    wire irq_fire;
    wire mret_fire, fencei_fire;
    wire [31:0] machine_return_pc;
    wire [31:0] trap_cause, trap_value;
    reg [31:0] sync_cause0, sync_cause1, sync_value0, sync_value1;
    reg sync_fault0, sync_fault1;
    wire [1:0] retire_count;
    function suppress_instret;
        input [31:0] insn;
        input wvalid;
        begin suppress_instret = wvalid && (insn[31:20] == 12'hb02 || insn[31:20] == 12'hb82); end
    endfunction
    assign retire_count = {1'b0,(valid_wb_pipe0 && MEM_WB_en_pipe0 && !suppress_instret(instruction_wb_pipe0,csr_wvalid_wb_pipe0))} +
                          {1'b0,(valid_wb_pipe1 && MEM_WB_en_pipe1 && !suppress_instret(instruction_wb_pipe1,csr_wvalid_wb_pipe1))};
    wire csr_control_pending =
        (csr_wvalid_ex_pipe0 && csr_control_write(csr_addr_ex_pipe0)) ||
        (csr_wvalid_ex_pipe1 && csr_control_write(csr_addr_ex_pipe1)) ||
        (csr_wvalid_mem_pipe0 && csr_control_write(csr_waddr_mem_pipe0)) ||
        (csr_wvalid_mem_pipe1 && csr_control_write(csr_waddr_mem_pipe1));
    wire csr_control_requested =
        (csr_wvalid_id_pipe0 && csr_control_write(csr_addr_id_pipe0)) ||
        (csr_wvalid_id_pipe1 && csr_control_write(csr_addr_id_pipe1));
    wire csr_fault_pending =
        (csr_rvalid_ex_pipe0 && csr_rillegal_ex_pipe0) ||
        (csr_rvalid_ex_pipe1 && csr_rillegal_ex_pipe1) ||
        (csr_rvalid_mem_pipe0 && csr_rillegal_mem_pipe0) ||
        (csr_rvalid_mem_pipe1 && csr_rillegal_mem_pipe1);
    assign csr_wait = irq_pending || system_pending ||
        ((system_requested || counter_requested) && (csr_older_pending || wb_pending)) ||
        (CSR_FORWARD_ENABLE ?
         (csr_fault_pending || csr_control_pending || (csr_control_requested && csr_older_pending)) :
         (csr_pending || ((csr_rvalid_id_pipe0 || csr_rvalid_id_pipe1) && csr_older_pending)));
    wire serial_id0 = csr_rvalid_id_pipe0 || (valid_id_pipe0 && (serial_instruction(Instr_id_pipe0) || illegal_id_pipe0));
    wire serial_id1 = csr_rvalid_id_pipe1 || (valid_id_pipe1 && (serial_instruction(Instr_id_pipe1) || illegal_id_pipe1));
    assign csr_split = serial_id0 || (serial_id1 && valid_id_pipe0);

    assign csr_forward_addr = {csr_addr_ex_pipe1, csr_addr_ex_pipe0,
                               csr_waddr_mem_pipe1, csr_waddr_mem_pipe0};
    assign csr_forward_data = {csr_wdata_ex_pipe1, csr_wdata_ex_pipe0,
                               csr_wdata_mem_pipe1, csr_wdata_mem_pipe0};
    // Forward intent even while MEM is held; ID also holds on those cycles.
    // Never let a faulting or wrong-path producer influence a surviving read.
    assign csr_forward_valid[0] = CSR_FORWARD_ENABLE && csr_wvalid_mem_pipe0 &&
        !csr_rillegal_mem_pipe0 && !csr_trap_fire;
    assign csr_forward_valid[1] = CSR_FORWARD_ENABLE && csr_wvalid_mem_pipe1 &&
        !csr_rillegal_mem_pipe1 && !csr_rillegal_mem_pipe0 && !csr_trap_fire;
    assign csr_forward_valid[2] = CSR_FORWARD_ENABLE && csr_wvalid_ex_pipe0 &&
        !csr_rillegal_ex_pipe0 && !csr_fault_pending_mem && !mem_redirect;
    assign csr_forward_valid[3] = CSR_FORWARD_ENABLE && csr_wvalid_ex_pipe1 &&
        !csr_rillegal_ex_pipe1 && !csr_rillegal_ex_pipe0 && !csr_fault_pending_mem && !mem_redirect;
    wire csr_fault_pending_mem = csr_trap_pipe0 || csr_trap_pipe1;
    always @(*) begin
        sync_fault0 = 1'b0;
        sync_cause0 = 32'd2;
        sync_value0 = instruction_mem_pipe0;
        if (!pmp_fetch_allow[0]) begin
            sync_fault0=1'b1; sync_cause0=32'd1; sync_value0=pc_mem_pipe0;
        end else if (illegal_mem_pipe0 || csr_rillegal_mem_pipe0) sync_fault0 = 1'b1;
        else if (instruction_mem_pipe0 == 32'h00000073) begin
            sync_fault0 = 1'b1; sync_cause0 = 32'd11; sync_value0 = 0;
        end else if (!DEBUG_HALT_ON_EBREAK && instruction_mem_pipe0 == 32'h00100073) begin
            sync_fault0 = 1'b1; sync_cause0 = 32'd3; sync_value0 = pc_mem_pipe0;
        end else if ((is_jal_mem_pipe0 || is_jalr_mem_pipe0 ||
                     (is_cond_jump_mem_pipe0 && PCSrc_mem_pipe0[0])) && PC_branch_mem_pipe0[1:0] != 0) begin
            sync_fault0 = 1'b1; sync_cause0 = 0; sync_value0 = PC_branch_mem_pipe0;
        end else if ((MemRead_mem_pipe0 || |MemWrite_mem_pipe0) &&
                     ((funct3_mem_pipe0[1:0] == 2 && alu_out_mem_pipe0[1:0] != 0) ||
                      (funct3_mem_pipe0[1:0] == 1 && alu_out_mem_pipe0[0]))) begin
            sync_fault0 = 1'b1; sync_cause0 = MemRead_mem_pipe0 ? 32'd4 : 32'd6;
            sync_value0 = alu_out_mem_pipe0;
        end else if ((MemRead_mem_pipe0 || |MemWrite_mem_pipe0) && !pmp_data_allow[0]) begin
            sync_fault0=1'b1; sync_cause0=MemRead_mem_pipe0 ? 32'd5 : 32'd7;
            sync_value0=pmp_badaddr0;
        end
    end
    always @(*) begin
        sync_fault1 = 1'b0;
        sync_cause1 = 32'd2;
        sync_value1 = instruction_mem_pipe1;
        if (!pmp_fetch_allow[1]) begin
            sync_fault1=1'b1; sync_cause1=32'd1; sync_value1=pc_mem_pipe1;
        end else if (illegal_mem_pipe1 || csr_rillegal_mem_pipe1) sync_fault1 = 1'b1;
        else if (instruction_mem_pipe1 == 32'h00000073) begin
            sync_fault1 = 1'b1; sync_cause1 = 32'd11; sync_value1 = 0;
        end else if (!DEBUG_HALT_ON_EBREAK && instruction_mem_pipe1 == 32'h00100073) begin
            sync_fault1 = 1'b1; sync_cause1 = 32'd3; sync_value1 = pc_mem_pipe1;
        end else if ((is_jal_mem_pipe1 || is_jalr_mem_pipe1 ||
                     (is_cond_jump_mem_pipe1 && PCSrc_mem_pipe1[0])) && PC_branch_mem_pipe1[1:0] != 0) begin
            sync_fault1 = 1'b1; sync_cause1 = 0; sync_value1 = PC_branch_mem_pipe1;
        end else if ((MemRead_mem_pipe1 || |MemWrite_mem_pipe1) &&
                     ((funct3_mem_pipe1[1:0] == 2 && alu_out_mem_pipe1[1:0] != 0) ||
                      (funct3_mem_pipe1[1:0] == 1 && alu_out_mem_pipe1[0]))) begin
            sync_fault1 = 1'b1; sync_cause1 = MemRead_mem_pipe1 ? 32'd4 : 32'd6;
            sync_value1 = alu_out_mem_pipe1;
        end else if ((MemRead_mem_pipe1 || |MemWrite_mem_pipe1) && !pmp_data_allow[1]) begin
            sync_fault1=1'b1; sync_cause1=MemRead_mem_pipe1 ? 32'd5 : 32'd7;
            sync_value1=pmp_badaddr1;
        end
    end
    assign csr_trap_pipe0 = valid_mem_pipe0 && sync_fault0;
    assign csr_trap_pipe1 = valid_mem_pipe1 && sync_fault1 &&
        !(mem_redirect && (is_cond_jump_mem_pipe0 || is_jal_mem_pipe0 || is_jalr_mem_pipe0));
    assign mret_fire = pipeline_can_advance && !csr_trap_pipe0 && !csr_trap_pipe1 &&
        ((valid_mem_pipe0 && instruction_mem_pipe0 == 32'h30200073) ||
         (valid_mem_pipe1 && instruction_mem_pipe1 == 32'h30200073));
    assign fencei_fire = pipeline_can_advance &&
        ((valid_mem_pipe0 && instruction_mem_pipe0[6:0] == 7'h0f && instruction_mem_pipe0[14:12] == 1) ||
         (valid_mem_pipe1 && instruction_mem_pipe1[6:0] == 7'h0f && instruction_mem_pipe1[14:12] == 1));
    assign irq_fire = pipeline_can_advance && irq_pending && !csr_older_pending && !wb_pending;
    assign csr_trap_fire = pipeline_can_advance && (csr_trap_pipe0 || csr_trap_pipe1 || irq_fire);
    assign csr_trap_pc = irq_fire ? (valid_id_pipe0 ? pc_id_pipe0 : valid_id_pipe1 ? pc_id_pipe1 : PC) :
                         csr_trap_pipe0 ? pc_mem_pipe0 : pc_mem_pipe1;
    assign trap_cause = irq_fire ? irq_cause : csr_trap_pipe0 ? sync_cause0 : sync_cause1;
    assign trap_value = irq_fire ? 32'b0 : csr_trap_pipe0 ? sync_value0 : sync_value1;

    assign csr_rillegal_id_pipe0 = csr_rillegal_bank_id_pipe0 ||
        (csr_wvalid_id_pipe0 && csr_addr_id_pipe0[11:10] == 2'b11);
    assign csr_addr_id_pipe0 = Instr_id_pipe0[31:20];
    assign csr_wdata_ex_pipe0 = (funct3_ex_pipe0[1:0] == 2'b01) ?
                                 Src_A_pipe0 : ALUResult_ex_pipe0;
    assign csr_wfire_mem_pipe0 = csr_wvalid_mem_pipe0 &&
        MEM_WB_en_pipe0 && !MEM_WB_flush_pipe0 && !csr_rillegal_mem_pipe0 && !csr_trap_fire && !RESET;
    assign csr_error_mem_pipe0 = csr_rillegal_mem_pipe0 || csr_willegal_mem_pipe0 || (valid_mem_pipe0 && sync_fault0);

    assign csr_rillegal_id_pipe1 = csr_rillegal_bank_id_pipe1 ||
        (csr_wvalid_id_pipe1 && csr_addr_id_pipe1[11:10] == 2'b11);
    assign csr_addr_id_pipe1 = Instr_id_pipe1[31:20];
    assign csr_wdata_ex_pipe1 = (funct3_ex_pipe1[1:0] == 2'b01) ?
                                 Src_A_pipe1 : ALUResult_ex_pipe1;
    assign csr_wfire_mem_pipe1 = csr_wvalid_mem_pipe1 &&
        MEM_WB_en_pipe1 && !MEM_WB_flush_pipe1 && !csr_rillegal_mem_pipe1 && !csr_trap_fire && !RESET;
    assign csr_error_mem_pipe1 = csr_rillegal_mem_pipe1 || csr_willegal_mem_pipe1 || (valid_mem_pipe1 && sync_fault1);

    // RegFile WD logic
    always @(*) begin
        if(csr_rvalid_wb_pipe0)
            WD_pipe0 = csr_rdata_wb_pipe0;
        else if(MemToReg_wb_pipe0)
            WD_pipe0 = mem_rdata_wb_pipe0;
        else if(MCycle_wb_pipe0)
            WD_pipe0 = MCycle_Result_wb_pipe0[31:0];
        else 
            WD_pipe0 = alu_out_wb_pipe0;
    end

    // RegFile WD logic
    always @(*) begin
        if(csr_rvalid_wb_pipe1)
            WD_pipe1 = csr_rdata_wb_pipe1;
        else if(MemToReg_wb_pipe1)
            WD_pipe1 = mem_rdata_wb_pipe1;
        else if(MCycle_wb_pipe1)
            WD_pipe1 = MCycle_Result_wb_pipe1[31:0];
        else 
            WD_pipe1 = alu_out_wb_pipe1;
    end
    

    // Extend connections
    assign InstrImm_id_pipe0 = Instr_id_pipe0[31:7];
    assign InstrImm_id_pipe1 = Instr_id_pipe1[31:7];


    // Multi-Cycle unit for multiplication and division
    wire MCycle_start;
    assign MCycle_start = MCycle_ex_pipe0 || MCycle_ex_pipe1; // Start signal for multi-cycle operations
    wire is_mulsu_ex;
    assign is_mulsu_ex = (MCycle_ex_pipe0 && funct3_ex_pipe0 == Funct3_mulsu) || (MCycle_ex_pipe1 && funct3_ex_pipe1 == Funct3_mulsu);
    wire MCycle_Busy; // MCycle busy signal
    reg [1:0]  MCycleOp_ex;
    wire [63:0] MCycle_out_ex;

    always @(*) begin
        if(MCycle_ex_pipe0) begin
            MCycleOp_ex = MCycleOp_ex_pipe0;
            Src_A_MCycle = Src_A_pipe0;
            Src_B_MCycle = Src_B_pipe0;
        end 
        else if(MCycle_ex_pipe1) begin
            MCycleOp_ex = MCycleOp_ex_pipe1;
            Src_A_MCycle = Src_A_pipe1;
            Src_B_MCycle = Src_B_pipe1;
        end
    end


    always @(*) begin
        case(funct3_ex_pipe0)
            Funct3_mul: MCycle_Result_ex_pipe0 = MCycle_out_ex[31:0]; // LSW of Product
            Funct3_mulh: MCycle_Result_ex_pipe0 = MCycle_out_ex[63:32]; // MSW of Product
            Funct3_mulu: MCycle_Result_ex_pipe0 = MCycle_out_ex[63:32]; // LSW of Product
            Funct3_mulsu: MCycle_Result_ex_pipe0 = MCycle_out_ex[63:32]; // LSW of Product
            Funct3_div: MCycle_Result_ex_pipe0 = MCycle_out_ex[31:0]; // Quotient
            Funct3_divu: MCycle_Result_ex_pipe0 = MCycle_out_ex[31:0]; // Quotient
            Funct3_rem: MCycle_Result_ex_pipe0 = MCycle_out_ex[63:32]; // Remainder
            Funct3_remu: MCycle_Result_ex_pipe0 = MCycle_out_ex[63:32]; // Remainder
            default: MCycle_Result_ex_pipe0 = 32'b0; // should not occur
        endcase
    end

    always @(*) begin
        case(funct3_ex_pipe1)
            Funct3_mul: MCycle_Result_ex_pipe1 = MCycle_out_ex[31:0]; // LSW of Product
            Funct3_mulh: MCycle_Result_ex_pipe1 = MCycle_out_ex[63:32]; // MSW of Product
            Funct3_mulu: MCycle_Result_ex_pipe1 = MCycle_out_ex[63:32]; // LSW of Product
            Funct3_mulsu: MCycle_Result_ex_pipe1 = MCycle_out_ex[63:32]; // LSW of Product
            Funct3_div: MCycle_Result_ex_pipe1 = MCycle_out_ex[31:0]; // Quotient
            Funct3_divu: MCycle_Result_ex_pipe1 = MCycle_out_ex[31:0]; // Quotient
            Funct3_rem: MCycle_Result_ex_pipe1 = MCycle_out_ex[63:32]; // Remainder
            Funct3_remu: MCycle_Result_ex_pipe1 = MCycle_out_ex[63:32]; // Remainder
            default: MCycle_Result_ex_pipe1 = 32'b0; // should not occur
        endcase
    end


    wire [3:0] forward_selA_id_pipe0;
    wire [3:0] forward_selB_id_pipe0;

    wire [3:0] forward_selA_id_pipe1;
    wire [3:0] forward_selB_id_pipe1;

    // Forwarding logic for ID stage
    always @(*) begin
        case (forward_selA_id_pipe0)
            SEL_MCYCLE_MEMWB_PIPE1: rs1_val_id_pipe0 = MCycle_Result_wb_pipe1[31:0];
            SEL_MCYCLE_MEMWB_PIPE0: rs1_val_id_pipe0 = MCycle_Result_wb_pipe0[31:0];
            SEL_ALU_MEMWB_PIPE1: rs1_val_id_pipe0 = alu_out_wb_pipe1;
            SEL_ALU_MEMWB_PIPE0: rs1_val_id_pipe0 = alu_out_wb_pipe0;
            SEL_LW_MEMWB_PIPE0: rs1_val_id_pipe0 = mem_rdata_wb_pipe0;
            SEL_LW_MEMWB_PIPE1: rs1_val_id_pipe0 = mem_rdata_wb_pipe1;
            SEL_IDEX: rs1_val_id_pipe0 = RD1_id_pipe0;
            default: rs1_val_id_pipe0 = 32'b0;
        endcase
    end

    always @(*) begin
        case(forward_selB_id_pipe0)
            SEL_MCYCLE_MEMWB_PIPE1: rs2_val_id_pipe0 = MCycle_Result_wb_pipe1[31:0];
            SEL_MCYCLE_MEMWB_PIPE0: rs2_val_id_pipe0 = MCycle_Result_wb_pipe0[31:0];
            SEL_LW_MEMWB_PIPE1: rs2_val_id_pipe0 = mem_rdata_wb_pipe1;
            SEL_LW_MEMWB_PIPE0: rs2_val_id_pipe0 = mem_rdata_wb_pipe0;
            SEL_ALU_MEMWB_PIPE1: rs2_val_id_pipe0 = alu_out_wb_pipe1;
            SEL_ALU_MEMWB_PIPE0: rs2_val_id_pipe0 = alu_out_wb_pipe0;
            SEL_IDEX: rs2_val_id_pipe0 = RD2_id_pipe0;
            default: rs2_val_id_pipe0 = 32'b0;
        endcase
    end


    always @(*) begin
        case (forward_selA_id_pipe1)
            SEL_MCYCLE_MEMWB_PIPE1: rs1_val_id_pipe1 = MCycle_Result_wb_pipe1[31:0];
            SEL_MCYCLE_MEMWB_PIPE0: rs1_val_id_pipe1 = MCycle_Result_wb_pipe0[31:0];
            SEL_ALU_MEMWB_PIPE1: rs1_val_id_pipe1 = alu_out_wb_pipe1;
            SEL_ALU_MEMWB_PIPE0: rs1_val_id_pipe1 = alu_out_wb_pipe0;
            SEL_LW_MEMWB_PIPE0: rs1_val_id_pipe1 = mem_rdata_wb_pipe0;
            SEL_LW_MEMWB_PIPE1: rs1_val_id_pipe1 = mem_rdata_wb_pipe1;
            SEL_IDEX: rs1_val_id_pipe1 = RD1_id_pipe1;
            default: rs1_val_id_pipe1 = 32'b0;
        endcase
    end

    always @(*) begin
        case(forward_selB_id_pipe1)
            SEL_MCYCLE_MEMWB_PIPE1: rs2_val_id_pipe1 = MCycle_Result_wb_pipe1[31:0];
            SEL_MCYCLE_MEMWB_PIPE0: rs2_val_id_pipe1 = MCycle_Result_wb_pipe0[31:0];
            SEL_LW_MEMWB_PIPE1: rs2_val_id_pipe1 = mem_rdata_wb_pipe1;
            SEL_LW_MEMWB_PIPE0: rs2_val_id_pipe1 = mem_rdata_wb_pipe0;
            SEL_ALU_MEMWB_PIPE1: rs2_val_id_pipe1 = alu_out_wb_pipe1;
            SEL_ALU_MEMWB_PIPE0: rs2_val_id_pipe1 = alu_out_wb_pipe0;
            SEL_IDEX: rs2_val_id_pipe1 = RD2_id_pipe1;
            default: rs2_val_id_pipe1 = 32'b0;
        endcase
    end


    //ALU connections
    always @(*) begin
        if(AluSrcA_ex_pipe0 == 2'b11) begin
            Src_A_pipe0 = {27'b0, rs1_idx_ex_pipe0};
        end
        else if(AluSrcA_ex_pipe0 == 2'b01) begin
            Src_A_pipe0 = 32'b0;
        end
        else if(AluSrcA_ex_pipe0 == 2'b10) begin
            Src_A_pipe0 = pc_ex_pipe0;
        end
        else if(AluSrcA_ex_pipe0 == 2'b00) begin
            case (forward_selA_ex_pipe0)
                SEL_MCYCLE_EXMEM_PIPE1: Src_A_pipe0 = MCycle_Result_mem_pipe1[31:0];
                SEL_MCYCLE_EXMEM_PIPE0: Src_A_pipe0 = MCycle_Result_mem_pipe0[31:0];
                SEL_ALU_EXMEM_PIPE1: Src_A_pipe0 = alu_out_mem_pipe1;
                SEL_ALU_EXMEM_PIPE0: Src_A_pipe0 = alu_out_mem_pipe0;
                SEL_MCYCLE_MEMWB_PIPE1: Src_A_pipe0 = MCycle_Result_wb_pipe1[31:0];
                SEL_MCYCLE_MEMWB_PIPE0: Src_A_pipe0 = MCycle_Result_wb_pipe0[31:0];
                SEL_ALU_MEMWB_PIPE1: Src_A_pipe0 = alu_out_wb_pipe1;
                SEL_ALU_MEMWB_PIPE0: Src_A_pipe0 = alu_out_wb_pipe0;
                SEL_LW_MEMWB_PIPE1: Src_A_pipe0 = mem_rdata_wb_pipe1;
                SEL_LW_MEMWB_PIPE0: Src_A_pipe0 = mem_rdata_wb_pipe0;
                SEL_IDEX: Src_A_pipe0 = rs1_val_ex_pipe0;
                default: Src_A_pipe0 = 32'b0;
            endcase
        end
        else begin
            Src_A_pipe0 = 32'bx; // undefined
        end
    end


    always @(*) begin
        if(AluSrcB_ex_pipe0 == 2'b10) begin
            Src_B_pipe0 = csr_rdata_ex_pipe0;
        end
        else if(AluSrcB_ex_pipe0 == 2'b01) begin
            Src_B_pipe0 = imm_ex_pipe0;
        end
        else if(AluSrcB_ex_pipe0 == 2'b00) begin
            Src_B_pipe0 = rs2_val_ex_forward_pipe0;
        end
        else begin
            Src_B_pipe0 = 32'bx; // undefined
        end
    end


    //ALU connections
    always @(*) begin
        if(AluSrcA_ex_pipe1 == 2'b11) begin
            Src_A_pipe1 = {27'b0, rs1_idx_ex_pipe1};
        end
        else if(AluSrcA_ex_pipe1 == 2'b01) begin
            Src_A_pipe1 = 32'b0;
        end
        else if(AluSrcA_ex_pipe1 == 2'b10) begin
            Src_A_pipe1 = pc_ex_pipe1;
        end
        else if(AluSrcA_ex_pipe1 == 2'b00) begin
            case (forward_selA_ex_pipe1)
                SEL_MCYCLE_EXMEM_PIPE1: Src_A_pipe1 = MCycle_Result_mem_pipe1[31:0];
                SEL_MCYCLE_EXMEM_PIPE0: Src_A_pipe1 = MCycle_Result_mem_pipe0[31:0];
                SEL_ALU_EXMEM_PIPE1: Src_A_pipe1 = alu_out_mem_pipe1;
                SEL_ALU_EXMEM_PIPE0: Src_A_pipe1 = alu_out_mem_pipe0;
                SEL_MCYCLE_MEMWB_PIPE1: Src_A_pipe1 = MCycle_Result_wb_pipe1[31:0];
                SEL_MCYCLE_MEMWB_PIPE0: Src_A_pipe1 = MCycle_Result_wb_pipe0[31:0];
                SEL_ALU_MEMWB_PIPE1: Src_A_pipe1 = alu_out_wb_pipe1;
                SEL_ALU_MEMWB_PIPE0: Src_A_pipe1 = alu_out_wb_pipe0;
                SEL_LW_MEMWB_PIPE1: Src_A_pipe1 = mem_rdata_wb_pipe1;
                SEL_LW_MEMWB_PIPE0: Src_A_pipe1 = mem_rdata_wb_pipe0;
                SEL_IDEX: Src_A_pipe1 = rs1_val_ex_pipe1;
                default: Src_A_pipe1 = 32'b0;
            endcase
        end
        else begin
            Src_A_pipe1 = 32'b0; // undefined
        end
    end

    always @(*) begin
        if(AluSrcB_ex_pipe1 == 2'b10) begin
            Src_B_pipe1 = csr_rdata_ex_pipe1;
        end
        else if(AluSrcB_ex_pipe1 == 2'b01) begin
            Src_B_pipe1 = imm_ex_pipe1;
        end
        else if(AluSrcB_ex_pipe1 == 2'b00) begin
            Src_B_pipe1 = rs2_val_ex_forward_pipe1;
        end
        else begin
            Src_B_pipe1 = 32'bx; // undefined
        end
    end


    assign alu_out_ex_pipe0 = csr_rvalid_ex_pipe0 ? csr_rdata_ex_pipe0 : (is_jal_ex_pipe0 || is_jalr_ex_pipe0) ? pcplus4_ex_pipe0 : ALUResult_ex_pipe0;
    assign alu_out_ex_pipe1 = csr_rvalid_ex_pipe1 ? csr_rdata_ex_pipe1 : (is_jal_ex_pipe1 || is_jalr_ex_pipe1) ? pcplus4_ex_pipe1 : ALUResult_ex_pipe1;



    always @(*) begin
        if(is_cond_jump_ex_pipe0 || is_jal_ex_pipe0) begin
            PC_branch_ex_pipe0 = pc_ex_pipe0 + imm_ex_pipe0; // jump target
        end
        else if(is_jalr_ex_pipe0) begin
            PC_branch_ex_pipe0 = (Src_A_pipe0 + imm_ex_pipe0) & 32'hfffffffe;
        end
    end


    always @(*) begin
        if(is_cond_jump_ex_pipe1 || is_jal_ex_pipe1) begin
            PC_branch_ex_pipe1 = pc_ex_pipe1 + imm_ex_pipe1; // jump target
        end
        else if(is_jalr_ex_pipe1) begin
            PC_branch_ex_pipe1 = (Src_A_pipe1 + imm_ex_pipe1) & 32'hfffffffe;
        end
    end

    // branch prediction signals

    wire update_conditional_mem;
    assign update_conditional_mem = (is_cond_jump_mem_pipe0 || is_cond_jump_mem_pipe1);

    wire update_unconditional_mem;
    assign update_unconditional_mem = (is_jal_jalr_mem_pipe0 || is_jal_jalr_mem_pipe1);

    wire update_branch_conditional_mem;
    assign update_branch_conditional_mem = (is_cond_jump_mem_pipe0 && PCSrc_mem_pipe0[0]) || (is_cond_jump_mem_pipe1 && PCSrc_mem_pipe1[0]);

    wire [31:0] update_pc_conditional_mem;
    assign update_pc_conditional_mem = (is_cond_jump_mem_pipe0)? pc_mem_pipe0 : pc_mem_pipe1;

    wire [31:0] update_pc_unconditional_mem;
    assign update_pc_unconditional_mem = (is_jal_jalr_mem_pipe0)? pc_mem_pipe0 : pc_mem_pipe1;

    reg [31:0] update_target_conditional_mem;
    always @(*) begin
        if(is_cond_jump_mem_pipe0)
            update_target_conditional_mem = (PCSrc_mem_pipe0[0]) ? PC_branch_mem_pipe0 : pcplus4_mem_pipe0;
        else
            update_target_conditional_mem = (PCSrc_mem_pipe1[0]) ? PC_branch_mem_pipe1 : pcplus4_mem_pipe1;
    end

    wire [31:0] update_target_unconditional_mem;
    assign update_target_unconditional_mem = (is_jal_jalr_mem_pipe0)? PC_branch_mem_pipe0 : PC_branch_mem_pipe1;

    wire [6:0] update_pc_index_conditional_mem;
    assign update_pc_index_conditional_mem = (is_cond_jump_mem_pipe0)? pc_mem_pipe0[8:2] : pc_mem_pipe1[8:2];

    wire [6:0] update_pc_index_unconditional_mem;
    assign update_pc_index_unconditional_mem = (is_jal_jalr_mem_pipe0)? pc_mem_pipe0[8:2] : pc_mem_pipe1[8:2];

    reg branch_pred_correct_mem;
    always @(*) begin
        branch_pred_correct_mem = 1'b1;
        if(is_cond_jump_mem_pipe0) begin
            if(PCSrc_mem_pipe0[0] == 0)
                branch_pred_correct_mem = (branch_pred_mem_pipe0 == 1'b0);
            else if(PCSrc_mem_pipe0[0] == 1)
                branch_pred_correct_mem = (branch_pred_mem_pipe0 == 1'b1) && (PC_branch_mem_pipe0 == branch_pred_target_mem_pipe0);
        end
        else if(is_jal_mem_pipe0 || is_jalr_mem_pipe0) begin
            branch_pred_correct_mem = (branch_pred_mem_pipe0 == 1'b1) && (PC_branch_mem_pipe0 == branch_pred_target_mem_pipe0);
        end
        else if(is_cond_jump_mem_pipe1) begin
           if(PCSrc_mem_pipe1[0] == 0)
                branch_pred_correct_mem = (branch_pred_mem_pipe1 == 1'b0);
            else if(PCSrc_mem_pipe1[0] == 1)
                branch_pred_correct_mem = (branch_pred_mem_pipe1 == 1'b1) && (PC_branch_mem_pipe1 == branch_pred_target_mem_pipe1);
        end
        else if(is_jal_mem_pipe1 || is_jalr_mem_pipe1) begin
            branch_pred_correct_mem = (branch_pred_mem_pipe1 == 1'b1) && (PC_branch_mem_pipe1 == branch_pred_target_mem_pipe1);
        end
    end

    always @(*) begin
        if(is_branch_if_pipe0)
            pc_if_branch_prediction = pc_if_pipe0;
        else
            pc_if_branch_prediction = pc_if_pipe1;
    end



    //PC connections
    assign PC_IN = PC_value;
    // Simplified PC selection logic - avoid nested ternary operators
    always @(*) begin
        if (RESET) begin
            PC_value = PC_INIT;
        end
        else if (csr_trap_fire) begin
            PC_value = csr_trap_vector;
        end
        else if (mret_fire) begin PC_value = machine_return_pc; end
        else if (fencei_fire) begin
            PC_value = (valid_mem_pipe0 && instruction_mem_pipe0[6:0] == 7'h0f) ? pcplus4_mem_pipe0 : pcplus4_mem_pipe1;
        end
        else if(branch_pred_correct_mem) begin
            if(branch_pred_if && is_branch_if) begin
                PC_value = branch_pred_target_if; // predicted target
            end
            else begin
                if(is_branch_if_pipe0)
                    PC_value = pcplus4_if_pipe0; // predicted target
                else
                    PC_value = pcplus4_if_pipe1;
            end
        end
        else begin
            // Misprediction: select the correct target
            if(is_cond_jump_mem_pipe0) begin
                if(PCSrc_mem_pipe0[0]) // branch taken
                    PC_value = PC_branch_mem_pipe0;
                else // branch not taken
                    PC_value = pcplus4_mem_pipe0;
            end
            else if(is_jal_mem_pipe0 || is_jalr_mem_pipe0) begin
                PC_value = PC_branch_mem_pipe0; // jump target
            end
            else if(is_cond_jump_mem_pipe1) begin
                if(PCSrc_mem_pipe1[0]) // branch taken
                    PC_value = PC_branch_mem_pipe1;
                else // branch not taken
                    PC_value = pcplus4_mem_pipe1;
            end
            else if(is_jal_mem_pipe1 || is_jalr_mem_pipe1) begin
                PC_value = PC_branch_mem_pipe1; // jump target
            end
            else begin
                if(is_jump_if_pipe0 || is_branch_if_pipe0) 
                    PC_value = pcplus4_if_pipe0; // predicted target
                else
                PC_value = pcplus4_if_pipe1;
            end
        end
    end


    wire mem_redirect;
    assign mem_redirect = ~branch_pred_correct_mem;
    // wire mem_redirect = (is_jal_jalr_mem_pipe0 || is_jal_jalr_mem_pipe1 || is_cond_jump_mem_pipe0 || is_cond_jump_mem_pipe1);
    


    // Instantiate RegFile
    reg_file reg_file_inst( 
                    .CLK(CLK),
                    .WE_pipe0(WE_pipe0),
                    .WE_pipe1(WE_pipe1),
                    .rs1_pipe0(rs1_id_pipe0),
                    .rs2_pipe0(rs2_id_pipe0),
                    .rd_pipe0(rd_idx_wb_pipe0),
                    .rs1_pipe1(rs1_id_pipe1),
                    .rs2_pipe1(rs2_id_pipe1),
                    .rd_pipe1(rd_idx_wb_pipe1),
                    .WD_pipe0(WD_pipe0),
                    .WD_pipe1(WD_pipe1),
                    .RD1_pipe0(RD1_id_pipe0),
                    .RD2_pipe0(RD2_id_pipe0),
                    .RD1_pipe1(RD1_id_pipe1),
                    .RD2_pipe1(RD2_id_pipe1)
                );

    csr csr_inst(
        .forward_valid(csr_forward_valid),
        .forward_addr(csr_forward_addr),
        .forward_data(csr_forward_data),
        .irq_software(irq_software), .irq_timer(irq_timer), .irq_external(irq_external),
        .time_value(time_value), .retire_count(retire_count),
        .interrupt_pending(irq_pending), .interrupt_cause(irq_cause),
        .mret_valid(mret_fire), .return_pc(machine_return_pc),
        .pmp_config(pmp_config), .pmp_address(pmp_address),
        .trap_cause(trap_cause), .trap_value(trap_value),
        .trap_valid(csr_trap_fire),
        .trap_pc(csr_trap_pc),
        .trap_vector(csr_trap_vector),
        .clk(CLK),
        .rst(RESET),
        .csr_raddr_pipe0(csr_addr_id_pipe0),
        .csr_waddr_pipe0(csr_waddr_mem_pipe0),
        .csr_wdata_pipe0(csr_wdata_mem_pipe0),
        .csr_raddr_pipe1(csr_addr_id_pipe1),
        .csr_waddr_pipe1(csr_waddr_mem_pipe1),
        .csr_wdata_pipe1(csr_wdata_mem_pipe1),
        .csr_rvalid_pipe0(csr_rvalid_id_pipe0),
        .csr_rvalid_pipe1(csr_rvalid_id_pipe1),
        .csr_wvalid_pipe0(csr_wfire_mem_pipe0),
        .csr_wvalid_pipe1(csr_wfire_mem_pipe1),
        .csr_rdata_pipe0(csr_rdata_id_pipe0),
        .csr_rdata_pipe1(csr_rdata_id_pipe1),
        .csr_rillegal_pipe0(csr_rillegal_bank_id_pipe0),
        .csr_rillegal_pipe1(csr_rillegal_bank_id_pipe1),
        .csr_willegal_pipe0(csr_willegal_mem_pipe0),
        .csr_willegal_pipe1(csr_willegal_mem_pipe1)
    );
                
     // Instantiate Extend Module
    imm_extend imm_extend0(
                    .ImmSrc(ImmSrc_id_pipe0),
                    .InstrImm(InstrImm_id_pipe0),
                    .ExtImm(ExtImm_id_pipe0)
    );

    imm_extend imm_extend1(
                    .ImmSrc(ImmSrc_id_pipe1),
                    .InstrImm(InstrImm_id_pipe1),
                    .ExtImm(ExtImm_id_pipe1)
    );
                
    // Instantiate Decoder
    decode_unit decode_unit0(
                    .Instruction(Instr_id_pipe0),
                    .illegal_instruction(illegal_id_pipe0),
                    .Opcode(opcode_id_pipe0),
                    .Rs1(rs1_id_pipe0),
                    .uses_rs1(uses_rs1_id_pipe0),
                    .uses_rs2(uses_rs2_id_pipe0),
                    .csr_rvalid(csr_rvalid_id_pipe0),
                    .csr_wvalid(csr_wvalid_id_pipe0),
                    .Funct3(funct3_id_pipe0),
                    .Funct7(funct7_id_pipe0),
                    .RegWrite(RegWrite_id_pipe0),
                    .MemRead(MemRead_id_pipe0),
                    .MemWrite(MemWrite_id_pipe0),
                    .MemtoReg(MemtoReg_id_pipe0),
                    .LwSizeSel(LwSizeSel_id_pipe0),
                    .ALUSrcA(ALUSrcA_id_pipe0),
                    .ALUSrcB(ALUSrcB_id_pipe0),
                    .ImmSrc(ImmSrc_id_pipe0),
                    .ALUControl(ALUControl_id_pipe0),
                    .MCycle(MCycle_id_pipe0),
                    .MCycleOp(MCycleOp_id_pipe0)
                );
    
    decode_unit decode_unit1(
                    .Instruction(Instr_id_pipe1),
                    .illegal_instruction(illegal_id_pipe1),
                    .Opcode(opcode_id_pipe1),
                    .Rs1(rs1_id_pipe1),
                    .uses_rs1(uses_rs1_id_pipe1),
                    .uses_rs2(uses_rs2_id_pipe1),
                    .csr_rvalid(csr_rvalid_id_pipe1),
                    .csr_wvalid(csr_wvalid_id_pipe1),
                    .Funct3(funct3_id_pipe1),
                    .Funct7(funct7_id_pipe1),
                    .RegWrite(RegWrite_id_pipe1),
                    .MemRead(MemRead_id_pipe1),
                    .MemWrite(MemWrite_id_pipe1),
                    .MemtoReg(MemtoReg_id_pipe1),
                    .LwSizeSel(LwSizeSel_id_pipe1),
                    .ALUSrcA(ALUSrcA_id_pipe1),
                    .ALUSrcB(ALUSrcB_id_pipe1),
                    .ImmSrc(ImmSrc_id_pipe1),
                    .ALUControl(ALUControl_id_pipe1),
                    .MCycle(MCycle_id_pipe1),
                    .MCycleOp(MCycleOp_id_pipe1)
                );    
                
    // Instantiate PC_Logic
	next_pc next_pc0(
                    .is_branch(is_cond_jump_mem_pipe0),
                    .Funct3(funct3_mem_pipe0),
                    .ALUFlags(ALUFlags_mem_pipe0),
                    .PCSrc(PCSrc_mem_pipe0)
	);

    next_pc next_pc1(
                    .is_branch(is_cond_jump_mem_pipe1),
                    .Funct3(funct3_mem_pipe1),
                    .ALUFlags(ALUFlags_mem_pipe1),
                    .PCSrc(PCSrc_mem_pipe1)
	);
                
    // Instantiate ALU        
    alu alu0(
                    .Src_A(Src_A_pipe0),
                    .Src_B(Src_B_pipe0),
                    .ALUControl(AluOp_ex_pipe0),
                    .ALUResult(ALUResult_ex_pipe0),
                    .ALUFlags(ALUFlags_ex_pipe0)
    );

    alu alu1(
                    .Src_A(Src_A_pipe1),
                    .Src_B(Src_B_pipe1),
                    .ALUControl(AluOp_ex_pipe1),
                    .ALUResult(ALUResult_ex_pipe1),
                    .ALUFlags(ALUFlags_ex_pipe1)
    );

    // Multi-Cycle unit for multiplication and division
    muldiv_unit #(.width(32)) muldiv_unit1(
                    .CLK(CLK),
                    .RESET(RESET),
                    .Start(MCycle_start), // Start signal from Decoder
                    .MCycleOp(MCycleOp_ex), // Multi-cycle operation from Decoder
                    .is_mulsu(is_mulsu_ex),
                    .Operand1(Src_A_MCycle),
                    .Operand2(Src_B_MCycle),
                    .Result1(MCycle_out_ex[31:0]), // LSW of Product / Quotient
                    .Result2(MCycle_out_ex[63:32]), // MSW of Product / Remainder - not needed in RV32I
                    .Busy(MCycle_Busy)
                );                
    
    // Instantiate ProgramCounter    
    pc_reg #(.PC_INIT(PC_INIT)) pc_reg1(
                    .CLK(CLK),
                    .RESET(RESET),
                    .WE_PC(WE_PC),
                    .PC_IN(PC_IN),
                    .PC(PC_reg)  
                );


   if_id_reg if_id_reg0(
   .clk(CLK),
   .rst(RESET),
   .en(IF_ID_en_pipe0),              // 0=hold (stall IF/ID)
   .flush(IF_ID_flush_pipe0),           // 1=insert NOP into ID


   // From IF stage
   .pc_if(pc_if_pipe0),
   .pcplus4_if(pcplus4_if_pipe0),
   .valid_if(1'b1),
   .valid_id(valid_id_pipe0),
   .instr_if(Instr_if_pipe0), 
   .branch_pred_if(branch_pred_if_pipe0),
   .branch_pred_target_if(branch_pred_target_if_pipe0),

   .is_jal_if(is_jal_if_pipe0),
   .is_jalr_if(is_jalr_if_pipe0),
   .is_cond_jump_if(is_cond_jump_if_pipe0),
   .is_ebreak_if(is_ebreak_if_pipe0),

   // To ID stage
   .pc_id(pc_id_pipe0),
   .pcplus4_id(pcplus4_id_pipe0),
   .instr_id(Instr_id_pipe0),

   .is_jal_id(is_jal_id_pipe0),
   .is_jalr_id(is_jalr_id_pipe0),
   .is_cond_jump_id(is_cond_jump_id_pipe0),

   .branch_pred_id(branch_pred_id_pipe0),
   .branch_pred_target_id(branch_pred_target_id_pipe0),
   .is_ebreak_id(is_ebreak_id_pipe0)
   );

   if_id_reg if_id_reg1(
   .clk(CLK),
   .rst(RESET),
   .en(IF_ID_en_pipe1),              // 0=hold (stall IF/ID)
   .flush(IF_ID_flush_pipe1),           // 1=insert NOP into ID


   // From IF stage
   .pc_if(pc_if_pipe1),
   .pcplus4_if(pcplus4_if_pipe1),
   .valid_if(1'b1),
   .valid_id(valid_id_pipe1),
   .instr_if(Instr_if_pipe1), 

   .is_jal_if(is_jal_if_pipe1),
   .is_jalr_if(is_jalr_if_pipe1),
   .is_cond_jump_if(is_cond_jump_if_pipe1),

   .branch_pred_if(branch_pred_if_pipe1),
   .branch_pred_target_if(branch_pred_target_if_pipe1),
   .is_ebreak_if(is_ebreak_if_pipe1),


   // To ID stage
   .pc_id(pc_id_pipe1),
   .pcplus4_id(pcplus4_id_pipe1),
   .instr_id(Instr_id_pipe1),

   .is_jal_id(is_jal_id_pipe1),
   .is_jalr_id(is_jalr_id_pipe1),
   .is_cond_jump_id(is_cond_jump_id_pipe1),

   .branch_pred_id(branch_pred_id_pipe1),
   .branch_pred_target_id(branch_pred_target_id_pipe1),
   .is_ebreak_id(is_ebreak_id_pipe1)
   );


   id_ex_reg id_ex_reg0(
   .clk(CLK),
   .rst(RESET),
   .en(ID_EX_en_pipe0),              // 0=hold (stall into EX)
   .flush(ID_EX_flush_pipe0),
        .rs1_forward_ex(Src_A_pipe0), .rs2_forward_ex(rs2_val_ex_forward_pipe0),           // 1=bubble (zero control signals)
   // From ID stage (data)
   .pc_id(pc_id_pipe0),
   .pcplus4_id(pcplus4_id_pipe0),
   .valid_id(valid_id_pipe0),
   .valid_ex(valid_ex_pipe0),
   .instruction_id(Instr_id_pipe0),
   .instruction_ex(instruction_ex_pipe0),
   .illegal_id(illegal_id_pipe0),
   .illegal_ex(illegal_ex_pipe0),
   .rs1_val_id(rs1_val_id_pipe0),
   .rs2_val_id(rs2_val_id_pipe0),
   .imm_id(ExtImm_id_pipe0),
   .rs1_idx_id(rs1_id_pipe0),
   .rs2_idx_id(rs2_id_pipe0),
   .rd_idx_id(rd_id_pipe0),
   .funct3_id(funct3_id_pipe0),
   .opcode_id(opcode_id_pipe0),

   .branch_pred_id(branch_pred_id_pipe0),
   .branch_pred_target_id(branch_pred_target_id_pipe0),
   .is_ebreak_id(is_ebreak_id_pipe0),

   .csr_rvalid_id(csr_rvalid_id_pipe0),
   .csr_rdata_id(csr_rdata_id_pipe0),
   .csr_addr_id(csr_addr_id_pipe0),
   .csr_wvalid_id(csr_wvalid_id_pipe0),
   .csr_rillegal_id(csr_rillegal_id_pipe0),

   // From ID stage (control)
   .RegWrite_id(RegWrite_id_pipe0),
   .MemWrite_id(MemWrite_id_pipe0),
   .MemRead_id(MemRead_id_pipe0),
   .MemToReg_id(MemtoReg_id_pipe0),
   .LwSizeSel_id(LwSizeSel_id_pipe0),
   .AluSrcA_id(ALUSrcA_id_pipe0),
   .AluSrcB_id(ALUSrcB_id_pipe0),
   .AluOp_id(ALUControl_id_pipe0),
   .MCycle_id(MCycle_id_pipe0),
   .MCycleOp_id(MCycleOp_id_pipe0),

   .is_cond_jump_id(is_cond_jump_id_pipe0),
   .is_jal_id(is_jal_id_pipe0),
   .is_jalr_id(is_jalr_id_pipe0),

   // To EX stage
   .pc_ex(pc_ex_pipe0),
   .pcplus4_ex(pcplus4_ex_pipe0),
   .rs1_val_ex(rs1_val_ex_pipe0),
   .rs2_val_ex(rs2_val_ex_pipe0),
   .imm_ex(imm_ex_pipe0),
   .rs1_idx_ex(rs1_idx_ex_pipe0),
   .rs2_idx_ex(rs2_idx_ex_pipe0),
   .rd_idx_ex(rd_idx_ex_pipe0),
   .funct3_ex(funct3_ex_pipe0),
   .opcode_ex(opcode_ex_pipe0),
   .is_cond_jump_ex(is_cond_jump_ex_pipe0),
   .is_jal_ex(is_jal_ex_pipe0),
   .is_jalr_ex(is_jalr_ex_pipe0),

   .csr_rvalid_ex(csr_rvalid_ex_pipe0),
   .csr_rdata_ex(csr_rdata_ex_pipe0),
   .csr_addr_ex(csr_addr_ex_pipe0),
   .csr_wvalid_ex(csr_wvalid_ex_pipe0),
   .csr_rillegal_ex(csr_rillegal_ex_pipe0),

   .RegWrite_ex(RegWrite_ex_pipe0),
   .MemWrite_ex(MemWrite_ex_pipe0),
   .MemRead_ex(MemRead_ex_pipe0),
   .MemToReg_ex(MemToReg_ex_pipe0),
   .LwSizeSel_ex(LwSizeSel_ex_pipe0),
   .AluSrcA_ex(AluSrcA_ex_pipe0),
   .AluSrcB_ex(AluSrcB_ex_pipe0),
   .AluOp_ex(AluOp_ex_pipe0),
   .MCycle_ex(MCycle_ex_pipe0),
   .MCycleOp_ex(MCycleOp_ex_pipe0),
   .branch_pred_ex(branch_pred_ex_pipe0),
   .branch_pred_target_ex(branch_pred_target_ex_pipe0),
   .is_ebreak_ex(is_ebreak_ex_pipe0)
   );


   id_ex_reg id_ex_reg1(
   .clk(CLK),
   .rst(RESET),
   .en(ID_EX_en_pipe1),              // 0=hold (stall into EX)
   .flush(ID_EX_flush_pipe1),
        .rs1_forward_ex(Src_A_pipe1), .rs2_forward_ex(rs2_val_ex_forward_pipe1),           // 1=bubble (zero control signals)
   // From ID stage (data)
   .pc_id(pc_id_pipe1),
   .pcplus4_id(pcplus4_id_pipe1),
   .valid_id(valid_id_pipe1),
   .valid_ex(valid_ex_pipe1),
   .instruction_id(Instr_id_pipe1),
   .instruction_ex(instruction_ex_pipe1),
   .illegal_id(illegal_id_pipe1),
   .illegal_ex(illegal_ex_pipe1),
   .rs1_val_id(rs1_val_id_pipe1),
   .rs2_val_id(rs2_val_id_pipe1),
   .imm_id(ExtImm_id_pipe1),
   .rs1_idx_id(rs1_id_pipe1),
   .rs2_idx_id(rs2_id_pipe1),
   .rd_idx_id(rd_id_pipe1),
   .funct3_id(funct3_id_pipe1),
   .opcode_id(opcode_id_pipe1),

   .branch_pred_id(branch_pred_id_pipe1),
   .branch_pred_target_id(branch_pred_target_id_pipe1),
   .is_ebreak_id(is_ebreak_id_pipe1),

   .csr_rvalid_id(csr_rvalid_id_pipe1),
   .csr_rdata_id(csr_rdata_id_pipe1),
   .csr_addr_id(csr_addr_id_pipe1),
   .csr_wvalid_id(csr_wvalid_id_pipe1),
   .csr_rillegal_id(csr_rillegal_id_pipe1),

   // From ID stage (control)
   .RegWrite_id(RegWrite_id_pipe1),
   .MemWrite_id(MemWrite_id_pipe1),
   .MemRead_id(MemRead_id_pipe1),
   .MemToReg_id(MemtoReg_id_pipe1),
   .LwSizeSel_id(LwSizeSel_id_pipe1),
   .AluSrcA_id(ALUSrcA_id_pipe1),
   .AluSrcB_id(ALUSrcB_id_pipe1),
   .AluOp_id(ALUControl_id_pipe1),
   .MCycle_id(MCycle_id_pipe1),
   .MCycleOp_id(MCycleOp_id_pipe1),
   .is_cond_jump_id(is_cond_jump_id_pipe1),
   .is_jal_id(is_jal_id_pipe1),
   .is_jalr_id(is_jalr_id_pipe1),

   // To EX stage
   .pc_ex(pc_ex_pipe1),
   .pcplus4_ex(pcplus4_ex_pipe1),
   .rs1_val_ex(rs1_val_ex_pipe1),
   .rs2_val_ex(rs2_val_ex_pipe1),
   .imm_ex(imm_ex_pipe1),
   .rs1_idx_ex(rs1_idx_ex_pipe1),
   .rs2_idx_ex(rs2_idx_ex_pipe1),
   .rd_idx_ex(rd_idx_ex_pipe1),
   .funct3_ex(funct3_ex_pipe1),
   .opcode_ex(opcode_ex_pipe1),
   .is_cond_jump_ex(is_cond_jump_ex_pipe1),
   .is_jal_ex(is_jal_ex_pipe1),
   .is_jalr_ex(is_jalr_ex_pipe1),

   .csr_rvalid_ex(csr_rvalid_ex_pipe1),
   .csr_rdata_ex(csr_rdata_ex_pipe1),
   .csr_addr_ex(csr_addr_ex_pipe1),
   .csr_wvalid_ex(csr_wvalid_ex_pipe1),
   .csr_rillegal_ex(csr_rillegal_ex_pipe1),

   .RegWrite_ex(RegWrite_ex_pipe1),
   .MemWrite_ex(MemWrite_ex_pipe1),
   .MemRead_ex(MemRead_ex_pipe1),
   .MemToReg_ex(MemToReg_ex_pipe1),
   .LwSizeSel_ex(LwSizeSel_ex_pipe1),
   .AluSrcA_ex(AluSrcA_ex_pipe1),
   .AluSrcB_ex(AluSrcB_ex_pipe1),
   .AluOp_ex(AluOp_ex_pipe1),
   .MCycle_ex(MCycle_ex_pipe1),
   .MCycleOp_ex(MCycleOp_ex_pipe1),

   .branch_pred_ex(branch_pred_ex_pipe1),
   .branch_pred_target_ex(branch_pred_target_ex_pipe1),
   .is_ebreak_ex(is_ebreak_ex_pipe1)
   );


   ex_mem_reg ex_mem_reg0(
   .clk(CLK),
   .rst(RESET),
   .en(EX_MEM_en_pipe0),              // 0=hold
   .flush(EX_MEM_flush_pipe0),           // 1=bubble (zero control)
   // From EX stage
   .pc_ex(pc_ex_pipe0),
   .pcplus4_ex(pcplus4_ex_pipe0),
   .alu_out_ex(alu_out_ex_pipe0),
   .csr_rvalid_ex(csr_rvalid_ex_pipe0),
   .csr_rdata_ex(csr_rdata_ex_pipe0),
   .csr_addr_ex(csr_addr_ex_pipe0),
   .csr_wdata_ex(csr_wdata_ex_pipe0),
   .csr_wvalid_ex(csr_wvalid_ex_pipe0),
   .csr_rillegal_ex(csr_rillegal_ex_pipe0),
   .csr_rvalid_mem(csr_rvalid_mem_pipe0),
   .csr_rdata_mem(csr_rdata_mem_pipe0),
   .csr_addr_mem(csr_waddr_mem_pipe0),
   .csr_wdata_mem(csr_wdata_mem_pipe0),
   .csr_wvalid_mem(csr_wvalid_mem_pipe0),
   .csr_rillegal_mem(csr_rillegal_mem_pipe0),
   .valid_ex(valid_ex_pipe0),
   .valid_mem(valid_mem_pipe0),
   .instruction_ex(instruction_ex_pipe0),
   .instruction_mem(instruction_mem_pipe0),
   .illegal_ex(illegal_ex_pipe0),
   .illegal_mem(illegal_mem_pipe0),
   .store_data_ex(store_data_ex_pipe0),
   .rd_idx_ex(rd_idx_ex_pipe0),
   .MCycle_ex(MCycle_ex_pipe0),
   .MCycle_Result_ex(MCycle_Result_ex_pipe0[31:0]),
   .funct3_ex(funct3_ex_pipe0),
   .opcode_ex(opcode_ex_pipe0),
   .RegWrite_ex(RegWrite_ex_pipe0),
   .MemWrite_ex(MemWrite_ex_pipe0),
   .MemRead_ex(MemRead_ex_pipe0),
   .MemToReg_ex(MemToReg_ex_pipe0),
   .LwSizeSel_ex(LwSizeSel_ex_pipe0),
   .ALUFlags_ex(ALUFlags_ex_pipe0),

   .is_cond_jump_ex(is_cond_jump_ex_pipe0),
   .is_jal_ex(is_jal_ex_pipe0),
   .is_jalr_ex(is_jalr_ex_pipe0),
   .PC_branch_ex(PC_branch_ex_pipe0),

   .branch_pred_ex(branch_pred_ex_pipe0),
   .branch_pred_target_ex(branch_pred_target_ex_pipe0),
   .is_ebreak_ex(is_ebreak_ex_pipe0),
   // To MEM stage
   .pc_mem(pc_mem_pipe0),
   .pcplus4_mem(pcplus4_mem_pipe0),
   .alu_out_mem(alu_out_mem_pipe0),
   .store_data_mem(store_data_mem_pipe0),
   .MCycle_mem(MCycle_mem_pipe0),
   .MCycle_Result_mem(MCycle_Result_mem_pipe0),
   .rd_idx_mem(rd_idx_mem_pipe0),
   .funct3_mem(funct3_mem_pipe0),
   .opcode_mem(opcode_mem_pipe0),
   .RegWrite_mem(RegWrite_mem_pipe0),
   .MemWrite_mem(MemWrite_mem_pipe0),
   .MemRead_mem(MemRead_mem_pipe0),
   .MemToReg_mem(MemToReg_mem_pipe0),
   .LwSizeSel_mem(LwSizeSel_mem_pipe0),
   .ALUFlags_mem(ALUFlags_mem_pipe0),

   .is_cond_jump_mem(is_cond_jump_mem_pipe0),
   .is_jal_mem(is_jal_mem_pipe0),
   .is_jalr_mem(is_jalr_mem_pipe0),
   .PC_branch_mem(PC_branch_mem_pipe0),

   .branch_pred_mem(branch_pred_mem_pipe0),
   .branch_pred_target_mem(branch_pred_target_mem_pipe0),
   .is_ebreak_mem(is_ebreak_mem_pipe0)
   );


   ex_mem_reg ex_mem_reg1(
   .clk(CLK),
   .rst(RESET),
   .en(EX_MEM_en_pipe1),              // 0=hold
   .flush(EX_MEM_flush_pipe1),           // 1=bubble (zero control)
   // From EX stage
   .pc_ex(pc_ex_pipe1),
   .pcplus4_ex(pcplus4_ex_pipe1),
   .alu_out_ex(alu_out_ex_pipe1),
   .csr_rvalid_ex(csr_rvalid_ex_pipe1),
   .csr_rdata_ex(csr_rdata_ex_pipe1),
   .csr_addr_ex(csr_addr_ex_pipe1),
   .csr_wdata_ex(csr_wdata_ex_pipe1),
   .csr_wvalid_ex(csr_wvalid_ex_pipe1),
   .csr_rillegal_ex(csr_rillegal_ex_pipe1),
   .csr_rvalid_mem(csr_rvalid_mem_pipe1),
   .csr_rdata_mem(csr_rdata_mem_pipe1),
   .csr_addr_mem(csr_waddr_mem_pipe1),
   .csr_wdata_mem(csr_wdata_mem_pipe1),
   .csr_wvalid_mem(csr_wvalid_mem_pipe1),
   .csr_rillegal_mem(csr_rillegal_mem_pipe1),
   .valid_ex(valid_ex_pipe1),
   .valid_mem(valid_mem_pipe1),
   .instruction_ex(instruction_ex_pipe1),
   .instruction_mem(instruction_mem_pipe1),
   .illegal_ex(illegal_ex_pipe1),
   .illegal_mem(illegal_mem_pipe1),
   .store_data_ex(store_data_ex_pipe1),
   .rd_idx_ex(rd_idx_ex_pipe1),
   .MCycle_ex(MCycle_ex_pipe1),
   .MCycle_Result_ex(MCycle_Result_ex_pipe1[31:0]),
   .funct3_ex(funct3_ex_pipe1),
   .opcode_ex(opcode_ex_pipe1),
   .RegWrite_ex(RegWrite_ex_pipe1),
   .MemWrite_ex(MemWrite_ex_pipe1),
   .MemRead_ex(MemRead_ex_pipe1),
   .MemToReg_ex(MemToReg_ex_pipe1),
   .LwSizeSel_ex(LwSizeSel_ex_pipe1),
   .ALUFlags_ex(ALUFlags_ex_pipe1),

   .is_cond_jump_ex(is_cond_jump_ex_pipe1),
   .is_jal_ex(is_jal_ex_pipe1),
   .is_jalr_ex(is_jalr_ex_pipe1),
   .PC_branch_ex(PC_branch_ex_pipe1),

   .branch_pred_ex(branch_pred_ex_pipe1),
   .branch_pred_target_ex(branch_pred_target_ex_pipe1),
   .is_ebreak_ex(is_ebreak_ex_pipe1),
   // To MEM stage
   .pc_mem(pc_mem_pipe1),
   .pcplus4_mem(pcplus4_mem_pipe1),
   .alu_out_mem(alu_out_mem_pipe1),
   .store_data_mem(store_data_mem_pipe1),
   .MCycle_mem(MCycle_mem_pipe1),
   .MCycle_Result_mem(MCycle_Result_mem_pipe1),
   .rd_idx_mem(rd_idx_mem_pipe1),
   .funct3_mem(funct3_mem_pipe1),
   .opcode_mem(opcode_mem_pipe1),
   .RegWrite_mem(RegWrite_mem_pipe1),
   .MemWrite_mem(MemWrite_mem_pipe1),
   .MemRead_mem(MemRead_mem_pipe1),
   .MemToReg_mem(MemToReg_mem_pipe1),
   .LwSizeSel_mem(LwSizeSel_mem_pipe1),
   .ALUFlags_mem(ALUFlags_mem_pipe1),

   .is_cond_jump_mem(is_cond_jump_mem_pipe1),
   .is_jal_mem(is_jal_mem_pipe1),
   .is_jalr_mem(is_jalr_mem_pipe1),
   .PC_branch_mem(PC_branch_mem_pipe1),

   .branch_pred_mem(branch_pred_mem_pipe1),
   .branch_pred_target_mem(branch_pred_target_mem_pipe1),
   .is_ebreak_mem(is_ebreak_mem_pipe1)
   );

   mem_wb_reg mem_wb_reg0(
   .clk(CLK),
   .rst(RESET),
   .en(MEM_WB_en_pipe0),              // 0=hold
   .flush(MEM_WB_flush_pipe0),           // 1=bubble (zero control)
   // From MEM stage
   .pcplus4_mem(pcplus4_mem_pipe0),
   .csr_rvalid_mem(csr_rvalid_mem_pipe0),
   .csr_rdata_mem(csr_rdata_mem_pipe0),
   .csr_rvalid_wb(csr_rvalid_wb_pipe0),
   .csr_rdata_wb(csr_rdata_wb_pipe0),
   .valid_mem(valid_mem_pipe0),
   .valid_wb(valid_wb_pipe0),
   .instruction_mem(instruction_mem_pipe0),
   .instruction_wb(instruction_wb_pipe0),
   .illegal_mem(illegal_mem_pipe0),
   .illegal_wb(illegal_wb_pipe0),
   .csr_wvalid_mem(csr_wvalid_mem_pipe0),
   .csr_wvalid_wb(csr_wvalid_wb_pipe0),
   .mem_rdata_mem(mem_rdata_mem_pipe0),
   .alu_out_mem(alu_out_mem_pipe0),
   .MCycle_mem(MCycle_mem_pipe0),
   .MCycle_Result_mem(MCycle_Result_mem_pipe0),
   .rd_idx_mem(rd_idx_mem_pipe0),
   .funct3_mem(funct3_mem_pipe0),
   .opcode_mem(opcode_mem_pipe0),
   .RegWrite_mem(RegWrite_mem_pipe0 && !csr_error_mem_pipe0),
   .MemToReg_mem(MemToReg_mem_pipe0),
   .is_ebreak_mem(is_ebreak_mem_pipe0),
   // To WB stage
   .pcplus4_wb(pcplus4_wb_pipe0),
   .mem_rdata_wb(mem_rdata_wb_pipe0),
   .alu_out_wb(alu_out_wb_pipe0),
   .MCycle_wb(MCycle_wb_pipe0),
   .MCycle_Result_wb(MCycle_Result_wb_pipe0),
   .rd_idx_wb(rd_idx_wb_pipe0),
   .funct3_wb(funct3_wb_pipe0),
   .opcode_wb(opcode_wb_pipe0),
   .RegWrite_wb(RegWrite_wb_pipe0),
   .MemToReg_wb(MemToReg_wb_pipe0),
   .is_ebreak_wb(is_ebreak_wb_pipe0)
   );


   mem_wb_reg mem_wb_reg1(
   .clk(CLK),
   .rst(RESET),
   .en(MEM_WB_en_pipe1),              // 0=hold
   .flush(MEM_WB_flush_pipe1),           // 1=bubble (zero control)
   // From MEM stage
   .pcplus4_mem(pcplus4_mem_pipe1),
   .csr_rvalid_mem(csr_rvalid_mem_pipe1),
   .csr_rdata_mem(csr_rdata_mem_pipe1),
   .csr_rvalid_wb(csr_rvalid_wb_pipe1),
   .csr_rdata_wb(csr_rdata_wb_pipe1),
   .valid_mem(valid_mem_pipe1),
   .valid_wb(valid_wb_pipe1),
   .instruction_mem(instruction_mem_pipe1),
   .instruction_wb(instruction_wb_pipe1),
   .illegal_mem(illegal_mem_pipe1),
   .illegal_wb(illegal_wb_pipe1),
   .csr_wvalid_mem(csr_wvalid_mem_pipe1),
   .csr_wvalid_wb(csr_wvalid_wb_pipe1),
   .mem_rdata_mem(mem_rdata_mem_pipe1),
   .alu_out_mem(alu_out_mem_pipe1),
   .MCycle_mem(MCycle_mem_pipe1),
   .MCycle_Result_mem(MCycle_Result_mem_pipe1),
   .rd_idx_mem(rd_idx_mem_pipe1),
   .funct3_mem(funct3_mem_pipe1),
   .opcode_mem(opcode_mem_pipe1),
   .RegWrite_mem(RegWrite_mem_pipe1 && !csr_error_mem_pipe1),
   .MemToReg_mem(MemToReg_mem_pipe1),
   .is_ebreak_mem(is_ebreak_mem_pipe1),
   // To WB stage
   .pcplus4_wb(pcplus4_wb_pipe1),
   .mem_rdata_wb(mem_rdata_wb_pipe1),
   .alu_out_wb(alu_out_wb_pipe1),
   .MCycle_wb(MCycle_wb_pipe1),
   .MCycle_Result_wb(MCycle_Result_wb_pipe1),
   .rd_idx_wb(rd_idx_wb_pipe1),
   .funct3_wb(funct3_wb_pipe1),
   .opcode_wb(opcode_wb_pipe1),
   .RegWrite_wb(RegWrite_wb_pipe1),
   .MemToReg_wb(MemToReg_wb_pipe1),
   .is_ebreak_wb(is_ebreak_wb_pipe1)
   );


   hazard_ctrl hazard_ctrl_inst(
    .csr_wait(csr_wait),
    .csr_split(csr_split),
    .csr_trap(csr_trap_fire),
    .csr_trap_pipe0(csr_trap_pipe0 || irq_fire),
    .system_redirect(mret_fire || fencei_fire),
    .id_uses_rs1_pipe0(uses_rs1_id_pipe0),
    .id_uses_rs2_pipe0(uses_rs2_id_pipe0),
    .id_uses_rs1_pipe1(uses_rs1_id_pipe1),
    .id_uses_rs2_pipe1(uses_rs2_id_pipe1),
    .if_is_branch_pipe0(is_branch_if_pipe0),
    .if_is_branch_pipe1(is_branch_if_pipe1),

    .id_rs1_pipe0(rs1_id_pipe0),
    .id_rs2_pipe0(rs2_id_pipe0),
    .id_rd_pipe0(rd_id_pipe0),
    .id_is_R_type_pipe0(is_R_type_id_pipe0),
    .id_is_cond_branch_pipe0(is_cond_jump_id_pipe0),
    .id_is_load_pipe0(MemtoReg_id_pipe0),
    .id_is_store_pipe0(id_is_store_pipe0),
    .id_regWrite_pipe0(RegWrite_id_pipe0),
    .id_is_MCycle_pipe0(MCycle_id_pipe0),

    .id_rs1_pipe1(rs1_id_pipe1),
    .id_rs2_pipe1(rs2_id_pipe1),
    .id_rd_pipe1(rd_id_pipe1),
    .id_is_R_type_pipe1(is_R_type_id_pipe1),
    .id_is_cond_branch_pipe1(is_cond_jump_id_pipe1),
    .id_is_load_pipe1(MemtoReg_id_pipe1),
    .id_is_store_pipe1(id_is_store_pipe1),
    .id_regWrite_pipe1(RegWrite_id_pipe1),
    .id_is_MCycle_pipe1(MCycle_id_pipe1),

    .ex_is_load_pipe0(MemToReg_ex_pipe0),
    .ex_RegWrite_pipe0(RegWrite_ex_pipe0),
    .ex_rd_id_pipe0(rd_idx_ex_pipe0),
    .ex_addr_pipe0(alu_out_ex_pipe0),
    .ex_is_store_pipe0(ex_is_store_pipe0),

    .ex_is_load_pipe1(MemRead_ex_pipe1),
    .ex_RegWrite_pipe1(RegWrite_ex_pipe1),
    .ex_rd_id_pipe1(rd_idx_ex_pipe1),
    .ex_addr_pipe1(alu_out_ex_pipe1),
    .ex_is_store_pipe1(ex_is_store_pipe1),


    .mem_is_load_pipe0(MemRead_mem_pipe0),
    .mem_rd_id_pipe0(rd_idx_mem_pipe0),

    .mem_is_load_pipe1(MemRead_mem_pipe1),
    .mem_rd_id_pipe1(rd_idx_mem_pipe1),

    .is_ebreak_wb(is_ebreak_wb),
    .imem_stall(imem_stall),
    .dmem_stall(dmem_stall),
    .longop_busy(MCycle_Busy),
    .mem_redirect(mem_redirect),
    .locked(locked),
    
    .pc_en(WE_PC),

    .IF_ID_en_pipe0(IF_ID_en_pipe0),
    .IF_ID_flush_pipe0(IF_ID_flush_pipe0),
    .ID_EX_en_pipe0(ID_EX_en_pipe0),
    .ID_EX_flush_pipe0(ID_EX_flush_pipe0),
    .EX_MEM_en_pipe0(EX_MEM_en_pipe0),
    .EX_MEM_flush_pipe0(EX_MEM_flush_pipe0),
    .MEM_WB_en_pipe0(MEM_WB_en_pipe0),
    .MEM_WB_flush_pipe0(MEM_WB_flush_pipe0),

    .IF_ID_en_pipe1(IF_ID_en_pipe1),
    .IF_ID_flush_pipe1(IF_ID_flush_pipe1),
    .ID_EX_en_pipe1(ID_EX_en_pipe1),
    .ID_EX_flush_pipe1(ID_EX_flush_pipe1),
    .EX_MEM_en_pipe1(EX_MEM_en_pipe1),
    .EX_MEM_flush_pipe1(EX_MEM_flush_pipe1),
    .MEM_WB_en_pipe1(MEM_WB_en_pipe1),
    .MEM_WB_flush_pipe1(MEM_WB_flush_pipe1)
   );

   forward_ctrl forward_ctrl_inst(
    .id_rs1_pipe0(rs1_id_pipe0),
    .id_rs2_pipe0(rs2_id_pipe0),

    .id_rs1_pipe1(rs1_id_pipe1),
    .id_rs2_pipe1(rs2_id_pipe1),

    .ex_rs1_pipe0(rs1_idx_ex_pipe0),
    .ex_rs2_pipe0(rs2_idx_ex_pipe0),

    .ex_rs1_pipe1(rs1_idx_ex_pipe1),
    .ex_rs2_pipe1(rs2_idx_ex_pipe1),

    .is_load_mem_pipe0(MemToReg_mem_pipe0),
    .mem_rd_pipe0(rd_idx_mem_pipe0),
    .mem_RegWrite_pipe0(RegWrite_mem_pipe0 && !csr_error_mem_pipe0 && !MEM_WB_flush_pipe0),
    .mem_MCycle_pipe0(MCycle_mem_pipe0),

    .is_load_mem_pipe1(MemToReg_mem_pipe1),
    .mem_rd_pipe1(rd_idx_mem_pipe1),
    .mem_RegWrite_pipe1(RegWrite_mem_pipe1 && !csr_error_mem_pipe1 && !MEM_WB_flush_pipe1),
    .mem_MCycle_pipe1(MCycle_mem_pipe1),

    .is_load_wb_pipe0(MemToReg_wb_pipe0),
    .wb_rd_pipe0(rd_idx_wb_pipe0),
    .wb_RegWrite_pipe0(RegWrite_wb_pipe0),
    .wb_MCycle_pipe0(MCycle_wb_pipe0),

    .is_load_wb_pipe1(MemToReg_wb_pipe1),
    .wb_rd_pipe1(rd_idx_wb_pipe1),
    .wb_RegWrite_pipe1(RegWrite_wb_pipe1),
    .wb_MCycle_pipe1(MCycle_wb_pipe1),

    .selA_id_pipe0(forward_selA_id_pipe0),
    .selB_id_pipe0(forward_selB_id_pipe0),

    .selA_id_pipe1(forward_selA_id_pipe1),
    .selB_id_pipe1(forward_selB_id_pipe1),

    .selA_ex_pipe0(forward_selA_ex_pipe0),
    .selB_ex_pipe0(forward_selB_ex_pipe0),

    .selA_ex_pipe1(forward_selA_ex_pipe1),
    .selB_ex_pipe1(forward_selB_ex_pipe1)
   );

   branch_predictor branch_predictor_inst(
    .clk(CLK),
    .pc(pc_if_branch_prediction),
    .is_jump(is_jump_if),
    .is_call(is_call_if),
    .is_return(is_return_if),
    .predict(branch_pred_if),
    .predict_target(branch_pred_target_if),
    .update_conditional(update_conditional_mem),
    .update_branch_conditional(update_branch_conditional_mem),
    .update_pc_conditional(update_pc_conditional_mem),
    .update_pc_index_conditional(update_pc_index_conditional_mem),
    .update_target_conditional(update_target_conditional_mem),
    .update_unconditional(update_unconditional_mem),
    .update_pc_unconditional(update_pc_unconditional_mem),
    .update_target_unconditional(update_target_unconditional_mem),
    .update_pc_index_unconditional(update_pc_index_unconditional_mem)
   );
endmodule
