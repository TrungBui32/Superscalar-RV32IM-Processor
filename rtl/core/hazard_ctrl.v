module hazard_ctrl (
  input wire csr_wait,
  input wire csr_split,
  input wire csr_trap,
  input wire system_redirect,
  input wire csr_trap_pipe0,
  input wire id_uses_rs1_pipe0,
  input wire id_uses_rs2_pipe0,
  input wire id_uses_rs1_pipe1,
  input wire id_uses_rs2_pipe1,

  input  wire       if_is_branch_pipe0,
  input  wire       if_is_branch_pipe1,
  // ---- IF/ID (current ID-stage instr) ----
  input  wire [4:0] id_rs1_pipe0,
  input  wire [4:0] id_rs2_pipe0,
  input  wire [4:0] id_rd_pipe0,
  input  wire       id_is_R_type_pipe0,  // 1 if the ID-stage instr is an R-type
  input  wire       id_is_cond_branch_pipe0,  // 1 if the ID-stage instr is a branch
  input  wire       id_is_load_pipe0,    // 1 if the ID-stage instr is an I-type load (LW/LH/LB)
  input  wire       id_is_store_pipe0,   // 1 if the ID-stage instr is an S-type (SW/SH/SB)
  input  wire       id_regWrite_pipe0,
  input  wire       id_is_MCycle_pipe0,   // 1 if the ID-stage instr is a MCycle instr

  input  wire [4:0] id_rs1_pipe1,
  input  wire [4:0] id_rs2_pipe1,
  input  wire [4:0] id_rd_pipe1,
  input  wire       id_is_R_type_pipe1,  // 1 if the ID-stage instr is an R-type
  input  wire       id_is_cond_branch_pipe1,  // 1 if the ID-stage instr is a branch
  input  wire       id_is_load_pipe1,    // 1 if the ID-stage instr is an I-type load (LW/LH/LB)
  input  wire       id_is_store_pipe1,   // 1 if the ID-stage instr is an S-type (SW/SH/SB)
  input  wire       id_regWrite_pipe1,
  input  wire       id_is_MCycle_pipe1,   // 1 if the ID-stage instr is a MCycle instr

  // ---- ID/EX (the older instr now in EX) ----
  input  wire       ex_is_load_pipe0,    // EX-stage instr is a load
  input  wire       ex_RegWrite_pipe0,   // EX-stage instr will write a GPR
  input  wire       ex_is_store_pipe0,   // EX-stage instr is a store
  input  wire [31:0] ex_addr_pipe0, // EX-stage instr address
  input  wire [4:0] ex_rd_id_pipe0,     // its destination register

  input  wire       ex_is_load_pipe1,    // EX-stage instr is a load
  input  wire       ex_RegWrite_pipe1,   // EX-stage instr will write
  input  wire       ex_is_store_pipe1,   // EX-stage instr is a store
  input  wire [31:0] ex_addr_pipe1, // EX-stage instr address
  input  wire [4:0] ex_rd_id_pipe1,     // its destination register

  // ---- EX/MEM (the older instr now in MEM) ----
  input  wire       mem_is_load_pipe0,    // MEM-stage instr is a load
  input  wire [4:0] mem_rd_id_pipe0,     // its destination register

  input  wire       mem_is_load_pipe1,    // MEM-stage instr is a load
  input  wire [4:0] mem_rd_id_pipe1,     // its destination register

  // ---- Structural / long-op / redirect ----
  input  wire       is_ebreak_wb, // EBREAK instruction in WB stage
  input  wire       imem_stall,
  input  wire       dmem_stall,
  input  wire       longop_busy,
  input  wire       mem_redirect,

  input wire locked, // wait for clocking wizard stable

  // ---- Pipeline controls out ----
  output reg        pc_en,
  output reg        IF_ID_en_pipe0,   
  output reg        IF_ID_en_pipe1,
  output reg        IF_ID_flush_pipe0,
  output reg        IF_ID_flush_pipe1,
  output reg        ID_EX_en_pipe0,
  output reg        ID_EX_en_pipe1,
  output reg        ID_EX_flush_pipe0,
  output reg        ID_EX_flush_pipe1,
  output reg        EX_MEM_en_pipe0,
  output reg        EX_MEM_en_pipe1,
  output reg        EX_MEM_flush_pipe0,
  output reg        EX_MEM_flush_pipe1,
  output reg        MEM_WB_en_pipe0,
  output reg        MEM_WB_en_pipe1,
  output reg        MEM_WB_flush_pipe0,
  output reg        MEM_WB_flush_pipe1
);
  // ---------------- Hazard conditions ----------------
  wire double_branch_if;
  assign double_branch_if = (if_is_branch_pipe0 && if_is_branch_pipe1) ? 1'b1 : 1'b0;
  
  // Check if the destination register of the older instruction in ID stage (pipe0) matches the destination register of the newer instruction in ID stage (pipe1)
  wire same_reg_write_write_id;
  assign same_reg_write_write_id = (id_regWrite_pipe0 && id_regWrite_pipe1 && (id_rd_pipe0 != 5'd0) && (id_rd_pipe0 == id_rd_pipe1)) ? 1'b1 : 1'b0;
  
  // Check if the destination register of the older instruction in ID stage (pipe0) matches either source register of the newer instruction in ID stage (pipe1)
  wire same_reg_read_write_id;
  assign same_reg_read_write_id = id_regWrite_pipe0 && (id_rd_pipe0 != 0) &&
      ((id_uses_rs1_pipe1 && id_rd_pipe0 == id_rs1_pipe1) ||
       (id_uses_rs2_pipe1 && id_rd_pipe0 == id_rs2_pipe1));
  
  // MCycle-use hazards from ID stage
  wire MCycle_use_id_pipe0;
  assign MCycle_use_id_pipe0 = id_is_MCycle_pipe0;
  wire MCycle_use_id_pipe1;
  assign MCycle_use_id_pipe1 = id_is_MCycle_pipe1;
  wire double_MCycle_use_id;
  assign double_MCycle_use_id = ((id_is_MCycle_pipe0 && id_is_MCycle_pipe1)) ? 1'b1 : 1'b0;

// Load-use hazards from EX stage
  wire load_use_ex_stage_pipe0;
  assign load_use_ex_stage_pipe0 = (ex_is_load_pipe0 && ex_rd_id_pipe0 != 0 &&
       ((id_uses_rs1_pipe0 && ex_rd_id_pipe0 == id_rs1_pipe0) ||
        (id_uses_rs2_pipe0 && ex_rd_id_pipe0 == id_rs2_pipe0))) ||
      (ex_is_load_pipe1 && ex_rd_id_pipe1 != 0 &&
       ((id_uses_rs1_pipe0 && ex_rd_id_pipe1 == id_rs1_pipe0) ||
        (id_uses_rs2_pipe0 && ex_rd_id_pipe1 == id_rs2_pipe0)));

  wire load_use_ex_stage_pipe1;
  assign load_use_ex_stage_pipe1 = (ex_is_load_pipe0 && ex_rd_id_pipe0 != 0 &&
       ((id_uses_rs1_pipe1 && ex_rd_id_pipe0 == id_rs1_pipe1) ||
        (id_uses_rs2_pipe1 && ex_rd_id_pipe0 == id_rs2_pipe1))) ||
      (ex_is_load_pipe1 && ex_rd_id_pipe1 != 0 &&
       ((id_uses_rs1_pipe1 && ex_rd_id_pipe1 == id_rs1_pipe1) ||
        (id_uses_rs2_pipe1 && ex_rd_id_pipe1 == id_rs2_pipe1)));

// 2) Memory access address conflicts
  wire same_addr_mem_ex;
  // Split accesses can overlap the next word. Conservatively serialize
  // adjacent words whenever either effective address has a byte offset.
  assign same_addr_mem_ex = (ex_addr_pipe0[31:2] == ex_addr_pipe1[31:2]) ||
      ((|ex_addr_pipe0[1:0] || |ex_addr_pipe1[1:0]) &&
       ((ex_addr_pipe0[31:2]+30'd1 == ex_addr_pipe1[31:2]) ||
        (ex_addr_pipe1[31:2]+30'd1 == ex_addr_pipe0[31:2])));

  wire same_addr_mem_write_ex;
  assign same_addr_mem_write_ex = ((ex_is_store_pipe0 && ex_is_store_pipe1) && same_addr_mem_ex) ? 1'b1 : 1'b0;

  wire same_addr_mem_write_load_ex;
  assign same_addr_mem_write_load_ex = ((ex_is_store_pipe0 && ex_is_load_pipe1) && same_addr_mem_ex) ? 1'b1 : 1'b0;

  wire same_addr_mem_load_write_ex;
  assign same_addr_mem_load_write_ex = ((ex_is_load_pipe0 && ex_is_store_pipe1) && same_addr_mem_ex) ? 1'b1 : 1'b0;
    


  // ---------------- Controls (priority) ----------------
always @(*) begin
    // ===== DEFAULTS: All assigned combinationally =====
    pc_en             = 1'b1;
    IF_ID_en_pipe0    = 1'b1;
    IF_ID_en_pipe1    = 1'b1;
    IF_ID_flush_pipe0 = 1'b0;
    IF_ID_flush_pipe1 = 1'b0;
    ID_EX_en_pipe0    = 1'b1;
    ID_EX_en_pipe1    = 1'b1;
    ID_EX_flush_pipe0 = 1'b0;
    ID_EX_flush_pipe1 = 1'b0;
    EX_MEM_en_pipe0   = 1'b1;
    EX_MEM_en_pipe1   = 1'b1;
    EX_MEM_flush_pipe0 = 1'b0;
    EX_MEM_flush_pipe1 = 1'b0;
    MEM_WB_en_pipe0   = 1'b1;
    MEM_WB_en_pipe1   = 1'b1;
    MEM_WB_flush_pipe0 = 1'b0;
    MEM_WB_flush_pipe1 = 1'b0;

    // ===== PRIORITY STRUCTURE (else if prevents conflicts) =====
    
    // Highest priority: Clock not stable
    if (!locked) begin
        pc_en          = 1'b0;
        IF_ID_en_pipe0 = 1'b0;
        IF_ID_en_pipe1 = 1'b0;
        ID_EX_en_pipe0 = 1'b0;
        ID_EX_en_pipe1 = 1'b0;
        EX_MEM_en_pipe0= 1'b0;
        EX_MEM_en_pipe1= 1'b0;
        MEM_WB_en_pipe0= 1'b0;
        MEM_WB_en_pipe1= 1'b0;
    end
    else if(is_ebreak_wb) begin
        pc_en             = 1'b0;
        IF_ID_en_pipe0    = 1'b0;
        IF_ID_en_pipe1    = 1'b0;
        ID_EX_en_pipe0    = 1'b0;
        ID_EX_en_pipe1    = 1'b0;
        EX_MEM_en_pipe0   = 1'b0;
        EX_MEM_en_pipe1   = 1'b0;
        MEM_WB_en_pipe0   = 1'b0;
        MEM_WB_en_pipe1   = 1'b0;
    end
    // Structural hazards
    else if (imem_stall || dmem_stall) begin
        pc_en          = 1'b0;
        IF_ID_en_pipe0 = 1'b0;
        IF_ID_en_pipe1 = 1'b0;
        ID_EX_en_pipe0 = 1'b0;
        ID_EX_en_pipe1 = 1'b0;
        EX_MEM_en_pipe0= 1'b0;
        EX_MEM_en_pipe1= 1'b0;
        MEM_WB_en_pipe0= 1'b0;
        MEM_WB_en_pipe1= 1'b0;
    end
    
    else if (longop_busy) begin
        pc_en          = 1'b0;
        IF_ID_en_pipe0 = 1'b0;
        IF_ID_en_pipe1 = 1'b0;
        ID_EX_en_pipe0 = 1'b0;
        ID_EX_en_pipe1 = 1'b0;
        EX_MEM_en_pipe0 = 1'b0;
        EX_MEM_en_pipe1 = 1'b0;
        MEM_WB_en_pipe0 = 1'b0;
        MEM_WB_en_pipe1 = 1'b0;
    end
    
    // Synchronous CSR fault: older WB may retire, but the faulting MEM
    // instruction and all younger instructions must have no side effects.
    else if (csr_trap) begin
        IF_ID_flush_pipe0 = 1'b1;
        IF_ID_flush_pipe1 = 1'b1;
        ID_EX_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
        EX_MEM_flush_pipe0 = 1'b1;
        EX_MEM_flush_pipe1 = 1'b1;
        MEM_WB_flush_pipe0 = csr_trap_pipe0;
        MEM_WB_flush_pipe1 = 1'b1;
    end
    else if(mem_redirect || system_redirect) begin
        pc_en             = 1'b1;
        IF_ID_flush_pipe0 = 1'b1;
        IF_ID_flush_pipe1 = 1'b1;
        ID_EX_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
        EX_MEM_flush_pipe0 = 1'b1;
        EX_MEM_flush_pipe1 = 1'b1;
    end
    
    else if (same_addr_mem_write_ex || same_addr_mem_load_write_ex || same_addr_mem_write_load_ex) begin
        pc_en             = 1'b0;
        IF_ID_en_pipe0    = 1'b0;
        IF_ID_en_pipe1    = 1'b0;
        ID_EX_en_pipe1    = 1'b0;
        ID_EX_flush_pipe0 = 1'b1;
        EX_MEM_flush_pipe1 = 1'b1;
    end
    // The CSR dependency unit requests a barrier for control writes/faults.
    // Data dependencies are handled by EX/MEM-to-ID CSR forwarding.
    else if (csr_wait) begin
        pc_en = 1'b0;
        IF_ID_en_pipe0 = 1'b0;
        IF_ID_en_pipe1 = 1'b0;
        ID_EX_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
    end
    else if(load_use_ex_stage_pipe0) begin
        pc_en             = 1'b0;
        IF_ID_en_pipe0    = 1'b0;
        IF_ID_en_pipe1    = 1'b0;
        ID_EX_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
    end
    
    else if(load_use_ex_stage_pipe1) begin
        pc_en             = 1'b0;
        IF_ID_en_pipe1    = 1'b0;
        IF_ID_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
    end
    // A CSR split must never bypass a load-use stall for its pipe0 operand.
    else if (csr_split) begin
        pc_en = 1'b0;
        IF_ID_en_pipe1 = 1'b0;
        IF_ID_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
    end
    // Data hazards - ID stage
    
    else if (same_reg_write_write_id) begin
        pc_en             = 1'b0;
        IF_ID_en_pipe1    = 1'b0;
        IF_ID_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
    end
    
    else if (same_reg_read_write_id) begin
        pc_en             = 1'b0;
        IF_ID_en_pipe1    = 1'b0;
        IF_ID_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
    end
    
    else if (double_MCycle_use_id) begin
        pc_en             = 1'b0;
        IF_ID_en_pipe1    = 1'b0;
        IF_ID_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
    end
    
    else if (MCycle_use_id_pipe0) begin
        pc_en             = 1'b0;
        IF_ID_en_pipe1    = 1'b0;
        IF_ID_flush_pipe0 = 1'b1;
        ID_EX_flush_pipe1 = 1'b1;
    end
    
    // IF stage - prediction/alignment
    else if (double_branch_if) begin
        pc_en            = 1'b1;
        IF_ID_flush_pipe1 = 1'b1;
    end
   
    else if (if_is_branch_pipe0) begin
        pc_en            = 1'b1;
        IF_ID_flush_pipe1 = 1'b1;
    end
end
endmodule
