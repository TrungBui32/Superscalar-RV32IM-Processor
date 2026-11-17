// Late MEM faults may leave speculative operand forwarding enabled:
// all younger stages must hold while blocked, then be killed at trap acceptance.
module trap_squash_property(
    input  fault0,
    input  fault1,
    input  csr_wait,
    input  csr_split,
    input  system_redirect,
    input  id_uses_rs1_pipe0,
    input  id_uses_rs2_pipe0,
    input  id_uses_rs1_pipe1,
    input  id_uses_rs2_pipe1,
    input  if_is_branch_pipe0,
    input  if_is_branch_pipe1,
    input [4:0] id_rs1_pipe0,
    input [4:0] id_rs2_pipe0,
    input [4:0] id_rd_pipe0,
    input  id_is_R_type_pipe0,
    input  id_is_cond_branch_pipe0,
    input  id_is_load_pipe0,
    input  id_is_store_pipe0,
    input  id_regWrite_pipe0,
    input  id_is_MCycle_pipe0,
    input [4:0] id_rs1_pipe1,
    input [4:0] id_rs2_pipe1,
    input [4:0] id_rd_pipe1,
    input  id_is_R_type_pipe1,
    input  id_is_cond_branch_pipe1,
    input  id_is_load_pipe1,
    input  id_is_store_pipe1,
    input  id_regWrite_pipe1,
    input  id_is_MCycle_pipe1,
    input  ex_is_load_pipe0,
    input  ex_RegWrite_pipe0,
    input  ex_is_store_pipe0,
    input [31:0] ex_addr_pipe0,
    input [4:0] ex_rd_id_pipe0,
    input  ex_is_load_pipe1,
    input  ex_RegWrite_pipe1,
    input  ex_is_store_pipe1,
    input [31:0] ex_addr_pipe1,
    input [4:0] ex_rd_id_pipe1,
    input  mem_is_load_pipe0,
    input [4:0] mem_rd_id_pipe0,
    input  mem_is_load_pipe1,
    input [4:0] mem_rd_id_pipe1,
    input  is_ebreak_wb,
    input  imem_stall,
    input  dmem_stall,
    input  longop_busy,
    input  mem_redirect,
    input  locked,
    output equivalent
);
    wire advancing=locked && !is_ebreak_wb && !imem_stall && !dmem_stall && !longop_busy;
    wire  pc_en;
    wire  IF_ID_en_pipe0;
    wire  IF_ID_en_pipe1;
    wire  IF_ID_flush_pipe0;
    wire  IF_ID_flush_pipe1;
    wire  ID_EX_en_pipe0;
    wire  ID_EX_en_pipe1;
    wire  ID_EX_flush_pipe0;
    wire  ID_EX_flush_pipe1;
    wire  EX_MEM_en_pipe0;
    wire  EX_MEM_en_pipe1;
    wire  EX_MEM_flush_pipe0;
    wire  EX_MEM_flush_pipe1;
    wire  MEM_WB_en_pipe0;
    wire  MEM_WB_en_pipe1;
    wire  MEM_WB_flush_pipe0;
    wire  MEM_WB_flush_pipe1;
    hazard_ctrl dut(
        .csr_wait(csr_wait),
        .csr_split(csr_split),
        .csr_trap(advancing && (fault0 || fault1)),
        .system_redirect(system_redirect),
        .csr_trap_pipe0(fault0),
        .id_uses_rs1_pipe0(id_uses_rs1_pipe0),
        .id_uses_rs2_pipe0(id_uses_rs2_pipe0),
        .id_uses_rs1_pipe1(id_uses_rs1_pipe1),
        .id_uses_rs2_pipe1(id_uses_rs2_pipe1),
        .if_is_branch_pipe0(if_is_branch_pipe0),
        .if_is_branch_pipe1(if_is_branch_pipe1),
        .id_rs1_pipe0(id_rs1_pipe0),
        .id_rs2_pipe0(id_rs2_pipe0),
        .id_rd_pipe0(id_rd_pipe0),
        .id_is_R_type_pipe0(id_is_R_type_pipe0),
        .id_is_cond_branch_pipe0(id_is_cond_branch_pipe0),
        .id_is_load_pipe0(id_is_load_pipe0),
        .id_is_store_pipe0(id_is_store_pipe0),
        .id_regWrite_pipe0(id_regWrite_pipe0),
        .id_is_MCycle_pipe0(id_is_MCycle_pipe0),
        .id_rs1_pipe1(id_rs1_pipe1),
        .id_rs2_pipe1(id_rs2_pipe1),
        .id_rd_pipe1(id_rd_pipe1),
        .id_is_R_type_pipe1(id_is_R_type_pipe1),
        .id_is_cond_branch_pipe1(id_is_cond_branch_pipe1),
        .id_is_load_pipe1(id_is_load_pipe1),
        .id_is_store_pipe1(id_is_store_pipe1),
        .id_regWrite_pipe1(id_regWrite_pipe1),
        .id_is_MCycle_pipe1(id_is_MCycle_pipe1),
        .ex_is_load_pipe0(ex_is_load_pipe0),
        .ex_RegWrite_pipe0(ex_RegWrite_pipe0),
        .ex_is_store_pipe0(ex_is_store_pipe0),
        .ex_addr_pipe0(ex_addr_pipe0),
        .ex_rd_id_pipe0(ex_rd_id_pipe0),
        .ex_is_load_pipe1(ex_is_load_pipe1),
        .ex_RegWrite_pipe1(ex_RegWrite_pipe1),
        .ex_is_store_pipe1(ex_is_store_pipe1),
        .ex_addr_pipe1(ex_addr_pipe1),
        .ex_rd_id_pipe1(ex_rd_id_pipe1),
        .mem_is_load_pipe0(mem_is_load_pipe0),
        .mem_rd_id_pipe0(mem_rd_id_pipe0),
        .mem_is_load_pipe1(mem_is_load_pipe1),
        .mem_rd_id_pipe1(mem_rd_id_pipe1),
        .is_ebreak_wb(is_ebreak_wb),
        .imem_stall(imem_stall),
        .dmem_stall(dmem_stall),
        .longop_busy(longop_busy),
        .mem_redirect(mem_redirect),
        .locked(locked),
        .pc_en(pc_en),
        .IF_ID_en_pipe0(IF_ID_en_pipe0),
        .IF_ID_en_pipe1(IF_ID_en_pipe1),
        .IF_ID_flush_pipe0(IF_ID_flush_pipe0),
        .IF_ID_flush_pipe1(IF_ID_flush_pipe1),
        .ID_EX_en_pipe0(ID_EX_en_pipe0),
        .ID_EX_en_pipe1(ID_EX_en_pipe1),
        .ID_EX_flush_pipe0(ID_EX_flush_pipe0),
        .ID_EX_flush_pipe1(ID_EX_flush_pipe1),
        .EX_MEM_en_pipe0(EX_MEM_en_pipe0),
        .EX_MEM_en_pipe1(EX_MEM_en_pipe1),
        .EX_MEM_flush_pipe0(EX_MEM_flush_pipe0),
        .EX_MEM_flush_pipe1(EX_MEM_flush_pipe1),
        .MEM_WB_en_pipe0(MEM_WB_en_pipe0),
        .MEM_WB_en_pipe1(MEM_WB_en_pipe1),
        .MEM_WB_flush_pipe0(MEM_WB_flush_pipe0),
        .MEM_WB_flush_pipe1(MEM_WB_flush_pipe1)
    );
    wire killed=IF_ID_flush_pipe0 && IF_ID_flush_pipe1 &&
        ID_EX_flush_pipe0 && ID_EX_flush_pipe1 && EX_MEM_flush_pipe0 && EX_MEM_flush_pipe1 &&
        MEM_WB_flush_pipe1 && (MEM_WB_flush_pipe0==fault0);
    wire held=!pc_en && !IF_ID_en_pipe0 && !IF_ID_en_pipe1 &&
        !ID_EX_en_pipe0 && !ID_EX_en_pipe1 && !EX_MEM_en_pipe0 && !EX_MEM_en_pipe1 &&
        !MEM_WB_en_pipe0 && !MEM_WB_en_pipe1;
    assign equivalent=!(fault0 || fault1) || (advancing ? killed : held);
endmodule

// Interrupts drain EX/MEM first. Each split-access request implies its MEM
// validity; refresh blocks only live MEM work. Prove that these internal stalls
// cannot alter interrupt acceptance once that empty-pipeline condition holds.
module irq_readiness_property(
    input external_ready, refresh_pending, irq_pending, wb_pending,
    input ex0, ex1, mem0, mem1,
    input split_request0, split_request1, split_done0, split_done1,
    output equivalent
);
    wire busy0=mem0 && split_request0 && !split_done0;
    wire busy1=mem1 && split_request1 && !split_done1;
    wire refresh_block=refresh_pending && (mem0 || mem1);
    wire older_pending=ex0 || ex1 || mem0 || mem1;
    wire original=external_ready && !busy0 && !busy1 && !refresh_block &&
        !refresh_pending && irq_pending && !older_pending && !wb_pending;
    wire optimized=external_ready && !refresh_pending && irq_pending &&
        !older_pending && !wb_pending;
    assign equivalent=original==optimized;
endmodule
