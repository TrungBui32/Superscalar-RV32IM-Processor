`timescale 1ns/1ps

// RV32IMA with M/S/U privilege. satp implements Bare only; no MMU or H-mode.
module csr #(
    parameter [31:0] HART_ID = 0
)(
    input clk, input rst,
    input trap_valid, input [31:0] trap_pc,
    input [31:0] trap_cause, input [31:0] trap_value,
    input mret_valid, input sret_valid,
    output reg [1:0] current_privilege,
    output [1:0] data_privilege,
    output allow_sret, allow_wfi,
    output [31:0] supervisor_return_pc,
    input irq_software, input irq_timer, input irq_external,
    input [63:0] time_value,
    input [1:0] retire_count,
    output [31:0] trap_vector,
    output [31:0] return_pc,
    output [127:0] pmp_config,
    output [511:0] pmp_address,
    output [63:0] trigger_control,
    output [63:0] trigger_address,
    output trigger_enable,
    output interrupt_pending,
    output [31:0] interrupt_cause,
    // Oldest first: MEM0, MEM1, EX0, EX1. Inputs are final write intent.
    input [3:0] forward_valid,
    input [47:0] forward_addr,
    input [127:0] forward_data,
    input [11:0] csr_raddr_pipe0, input [11:0] csr_waddr_pipe0,
    input [31:0] csr_wdata_pipe0,
    input [11:0] csr_raddr_pipe1, input [11:0] csr_waddr_pipe1,
    input [31:0] csr_wdata_pipe1,
    input csr_rvalid_pipe0, input csr_rvalid_pipe1,
    input csr_wvalid_pipe0, input csr_wvalid_pipe1,
    output reg [31:0] csr_rdata_pipe0, output reg [31:0] csr_rdata_pipe1,
    output csr_rillegal_pipe0, output csr_rillegal_pipe1,
    output csr_willegal_pipe0, output csr_willegal_pipe1
);
    // Machine trap setup
    localparam CSR_MSTATUS    = 12'h300;
    localparam CSR_MISA       = 12'h301;
    localparam CSR_MEDELEG    = 12'h302;
    localparam CSR_MIDELEG    = 12'h303;
    localparam CSR_MIE        = 12'h304;
    localparam CSR_MTVEC      = 12'h305;
    localparam CSR_MCOUNTEREN = 12'h306;

    // Machine trap handling
    localparam CSR_MSCRATCH   = 12'h340;
    localparam CSR_MEPC       = 12'h341;
    localparam CSR_MCAUSE     = 12'h342;
    localparam CSR_MTVAL      = 12'h343;
    localparam CSR_MIP        = 12'h344;
    localparam CSR_MTINST     = 12'h34A;
    localparam CSR_MTVAL2     = 12'h34B;

    // Supervisor trap setup
    localparam CSR_SSTATUS    = 12'h100;
    localparam CSR_SIE        = 12'h104;
    localparam CSR_STVEC      = 12'h105;
    localparam CSR_SCOUNTEREN = 12'h106;

    // Supervisor trap handling
    localparam CSR_SSCRATCH   = 12'h140;
    localparam CSR_SEPC       = 12'h141;
    localparam CSR_SCAUSE     = 12'h142;
    localparam CSR_STVAL      = 12'h143;
    localparam CSR_SIP        = 12'h144;
    localparam CSR_SATP = 12'h180;
    localparam CSR_SENVCFG = 12'h10a;
    localparam CSR_MENVCFG = 12'h30a;
    localparam CSR_MENVCFGH = 12'h31a;
    localparam CSR_SCOUNTOVF  = 12'hDA0;


    localparam CSR_MSTATUSH = 12'h310;
    localparam CSR_MCOUNTINHIBIT = 12'h320;
    localparam CSR_MCYCLE = 12'hB00;
    localparam CSR_MINSTRET = 12'hB02;
    localparam CSR_MCYCLEH = 12'hB80;
    localparam CSR_MINSTRETH = 12'hB82;
    localparam CSR_CYCLE = 12'hC00;
    localparam CSR_TIME = 12'hC01;
    localparam CSR_INSTRET = 12'hC02;
    localparam CSR_CYCLEH = 12'hC80;
    localparam CSR_TIMEH = 12'hC81;
    localparam CSR_INSTRETH = 12'hC82;
    localparam CSR_MVENDORID = 12'hF11;
    localparam CSR_MARCHID = 12'hF12;
    localparam CSR_MIMPID = 12'hF13;
    localparam CSR_MHARTID = 12'hF14;
    localparam CSR_MCONFIGPTR = 12'hF15;

    localparam [1:0] PRIV_U=2'b00, PRIV_S=2'b01, PRIV_M=2'b11;
    localparam [31:0] MISA_VALUE = 32'h4014_1101; // RV32 I+M+A+S+U.
    // Little endian, no FP/vector, no virtual memory: TVM/SUM/MXR are read-only 0.
    localparam [31:0] MSTATUS_MASK = 32'h0062_19aa;
    localparam [31:0] SSTATUS_MASK = 32'h0000_0122; // SPP, SPIE, SIE.
    localparam [31:0] MIE_MASK = 32'h0000_0aaa;
    localparam [31:0] SIRQ_MASK = 32'h0000_0222;
    localparam [31:0] MEDELEG_MASK = 32'h0000_03ff; // Implemented sync causes 0..9.
    reg [31:0] mstatus, mie, mtvec, mscratch, mepc, mcause, mtval;
    reg [31:0] medeleg, mideleg, mcounteren, scounteren;
    reg [31:0] stvec, sscratch, sepc, scause, stval;
    reg [31:0] supervisor_pending;
    assign data_privilege = current_privilege==PRIV_M && mstatus[17] ? mstatus[12:11] : current_privilege;
    assign allow_sret = current_privilege==PRIV_M || (current_privilege==PRIV_S && !mstatus[22]);
    assign allow_wfi = current_privilege==PRIV_M || (current_privilege==PRIV_S && !mstatus[21]);
    assign supervisor_return_pc=sepc;
    // Sixteen entries, 4-byte granularity (G=0), 34-bit physical address encoding.
    reg [7:0] pmpcfg [0:15];
    reg [31:0] pmpaddr [0:15];
    genvar pmp_index;
    generate for (pmp_index=0; pmp_index<16; pmp_index=pmp_index+1) begin: pmp_outputs
        assign pmp_config[pmp_index*8 +:8] = pmpcfg[pmp_index];
        assign pmp_address[pmp_index*32 +:32] = pmpaddr[pmp_index];
    end endgenerate
    // Two native address triggers: mcontrol type 2, equality, before timing,
    // action=breakpoint, M mode only. No external Debug Mode is advertised.
    reg tselect;
    reg [31:0] tdata1 [0:1];
    reg [31:0] tdata2 [0:1];
    reg [7:0] tcontrol;
    assign trigger_control={tdata1[1],tdata1[0]};
    assign trigger_address={tdata2[1],tdata2[0]};
    assign trigger_enable=tcontrol[3] && current_privilege==PRIV_M;
    reg [2:0] mcountinhibit;
    reg [63:0] mcycle, minstret;
    wire [31:0] misa = MISA_VALUE;
    wire [31:0] mip = {20'b0, irq_external, 3'b0, irq_timer, 3'b0, irq_software, 3'b0} |
                             supervisor_pending;
    wire [31:0] machine_interrupts = mip & mie & ~mideleg &
        {32{current_privilege!=PRIV_M || mstatus[3]}};
    wire [31:0] supervisor_interrupts = mip & mie & mideleg &
        {32{current_privilege==PRIV_U || (current_privilege==PRIV_S && mstatus[1])}};
    wire [31:0] eligible_interrupts = |machine_interrupts ? machine_interrupts : supervisor_interrupts;
    assign interrupt_pending = |eligible_interrupts;
    assign interrupt_cause = eligible_interrupts[11] ? 32'h8000_000b :
                             eligible_interrupts[3] ? 32'h8000_0003 :
                             eligible_interrupts[7] ? 32'h8000_0007 :
                             eligible_interrupts[9] ? 32'h8000_0009 :
                             eligible_interrupts[1] ? 32'h8000_0001 : 32'h8000_0005;
    wire trap_to_supervisor = current_privilege!=PRIV_M && trap_cause[30:5]==0 &&
        (trap_cause[31] ? mideleg[trap_cause[4:0]] : medeleg[trap_cause[4:0]]);
    wire [31:0] selected_tvec=trap_to_supervisor ? stvec : mtvec;
    assign trap_vector = {selected_tvec[31:2],2'b00} +
        ((trap_cause[31] && selected_tvec[1:0] == 2'b01) ? {trap_cause[29:0],2'b00} : 32'b0);
    assign return_pc = mepc;

    function csr_address_exists;
        input [11:0] addr;
        begin
            case (addr)
                CSR_MSTATUS, CSR_MISA, CSR_MIE, CSR_MTVEC, CSR_MSTATUSH,
                CSR_MCOUNTEREN, CSR_MCOUNTINHIBIT, CSR_MEDELEG, CSR_MIDELEG,
                CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SCOUNTEREN,
                CSR_SSCRATCH, CSR_SEPC, CSR_SCAUSE, CSR_STVAL, CSR_SIP, CSR_SATP,
                CSR_MENVCFG, CSR_MENVCFGH, CSR_SENVCFG,
                CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP,
                CSR_MCYCLE, CSR_MCYCLEH, CSR_MINSTRET, CSR_MINSTRETH,
                CSR_CYCLE, CSR_CYCLEH, CSR_INSTRET, CSR_INSTRETH, CSR_TIME, CSR_TIMEH,
                CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID, CSR_MCONFIGPTR:
                    csr_address_exists = 1'b1;
                default: csr_address_exists = (addr >= 12'h3a0 && addr <= 12'h3a3) ||
                    (addr >= 12'h3b0 && addr <= 12'h3bf) ||
                    addr == 12'h7a0 || addr == 12'h7a1 || addr == 12'h7a2 ||
                    addr == 12'h7a4 || addr == 12'h7a5;
            endcase
        end
    endfunction

    function csr_accessible;
        input [11:0] addr;
        input [1:0] privilege;
        input [31:0] status, machine_counteren, supervisor_counteren;
        reg [4:0] counter_bit;
        begin
            csr_accessible=csr_address_exists(addr) && privilege>=addr[9:8];
            if (addr==CSR_SATP && privilege==PRIV_S && status[20]) csr_accessible=0;
            if (addr==CSR_CYCLE || addr==CSR_CYCLEH || addr==CSR_TIME ||
                addr==CSR_TIMEH || addr==CSR_INSTRET || addr==CSR_INSTRETH) begin
                counter_bit = {3'b0,addr[1:0]};
                if (privilege!=PRIV_M && !machine_counteren[counter_bit]) csr_accessible=0;
                if (privilege==PRIV_U && !supervisor_counteren[counter_bit]) csr_accessible=0;
            end
        end
    endfunction

    // A single normalization function is shared by commit and forwarding.
    function [31:0] normalize_write;
        input [11:0] addr;
        input [31:0] value;
        begin
            case (addr)
                CSR_MSTATUS: normalize_write = (value & MSTATUS_MASK & ~32'h1800) |
                    (value[12:11]==2'b10 ? 32'b0 : (value & 32'h1800));
                CSR_SSTATUS: normalize_write = value & SSTATUS_MASK;
                CSR_MEDELEG: normalize_write = value & MEDELEG_MASK;
                CSR_MIDELEG: normalize_write = value & SIRQ_MASK;
                CSR_SIE: normalize_write = value & mideleg & MIE_MASK;
                CSR_SIP: normalize_write = value & mideleg & 32'h2;
                CSR_MIP: normalize_write = value & SIRQ_MASK;
                CSR_MISA: normalize_write = MISA_VALUE;
                CSR_MIE: normalize_write = value & MIE_MASK;
                CSR_MTVEC, CSR_STVEC: normalize_write = {value[31:2],1'b0,(value[1:0] == 2'b01)};
                CSR_MEPC, CSR_SEPC: normalize_write = {value[31:2],2'b0};
                CSR_MCOUNTINHIBIT: normalize_write = value & 32'h5;
                CSR_MCOUNTEREN, CSR_SCOUNTEREN: normalize_write = value & 32'h7;
                CSR_MSTATUSH, CSR_MENVCFG, CSR_MENVCFGH, CSR_SENVCFG, CSR_SATP: normalize_write = 0;
                default: normalize_write = value;
            endcase
        end
    endfunction

    function [11:0] backing_address;
        input [11:0] addr;
        begin
            case (addr)
                CSR_SSTATUS: backing_address=CSR_MSTATUS;
                CSR_SIE: backing_address=CSR_MIE;
                CSR_SIP: backing_address=CSR_MIP;
                CSR_CYCLE: backing_address = CSR_MCYCLE;
                CSR_CYCLEH: backing_address = CSR_MCYCLEH;
                CSR_INSTRET: backing_address = CSR_MINSTRET;
                CSR_INSTRETH: backing_address = CSR_MINSTRETH;
                default: backing_address = addr;
            endcase
        end
    endfunction

    function [31:0] forward_value;
        input [11:0] addr;
        input [31:0] value;
        input [3:0] valid;
        input [47:0] addresses;
        input [127:0] values;
        integer i;
        reg [31:0] base, incoming;
        reg [11:0] target;
        begin
            case (backing_address(addr))
                CSR_MSTATUS: base=mstatus;
                CSR_MIE: base=mie;
                CSR_MIP: base=mip;
                default: base=value;
            endcase
            for (i=0;i<4;i=i+1) begin
                target=addresses[12*i +:12];
                incoming=normalize_write(target,values[32*i +:32]);
                if (valid[i] && csr_accessible(target,current_privilege,mstatus,mcounteren,scounteren) &&
                    !(target>=12'h3a0 && target<=12'h3bf) && target[11:4]!=8'h7a &&
                    target[11:10]!=2'b11 && backing_address(addr)==backing_address(target)) begin
                    case(target)
                        CSR_SSTATUS: base=(base & ~SSTATUS_MASK) | incoming;
                        CSR_SIE: base=(base & ~(mideleg & MIE_MASK)) | incoming;
                        CSR_SIP: base=(base & ~(mideleg & 32'h2)) | incoming;
                        CSR_MIP: base=(base & ~SIRQ_MASK) | incoming;
                        default: base=incoming;
                    endcase
                end
            end
            case(addr)
                CSR_SSTATUS: forward_value=base & SSTATUS_MASK;
                CSR_SIE, CSR_SIP: forward_value=base & mideleg;
                default: forward_value=base;
            endcase
        end
    endfunction

    assign csr_rillegal_pipe0 = !rst && csr_rvalid_pipe0 && !csr_accessible(csr_raddr_pipe0,current_privilege,mstatus,mcounteren,scounteren);
    assign csr_willegal_pipe0 = !rst && csr_wvalid_pipe0 &&
        (!csr_accessible(csr_waddr_pipe0,current_privilege,mstatus,mcounteren,scounteren) || csr_waddr_pipe0[11:10] == 2'b11);
    always @(*) begin
        csr_rdata_pipe0 = 0;
        if (!rst && csr_rvalid_pipe0) begin
            case (csr_raddr_pipe0)
                12'h7a0: csr_rdata_pipe0 = {31'b0,tselect};
                12'h7a1: csr_rdata_pipe0 = tdata1[tselect];
                12'h7a2: csr_rdata_pipe0 = tdata2[tselect];
                12'h7a4: csr_rdata_pipe0 = 32'h4; // type 2 supported
                12'h7a5: csr_rdata_pipe0 = {24'b0,tcontrol};
                CSR_SSTATUS: csr_rdata_pipe0 = mstatus & SSTATUS_MASK;
                CSR_SIE: csr_rdata_pipe0 = mie & mideleg;
                CSR_SIP: csr_rdata_pipe0 = mip & mideleg;
                CSR_MEDELEG: csr_rdata_pipe0 = medeleg;
                CSR_MIDELEG: csr_rdata_pipe0 = mideleg;
                CSR_MCOUNTEREN: csr_rdata_pipe0 = mcounteren;
                CSR_SCOUNTEREN: csr_rdata_pipe0 = scounteren;
                CSR_STVEC: csr_rdata_pipe0 = stvec;
                CSR_SSCRATCH: csr_rdata_pipe0 = sscratch;
                CSR_SEPC: csr_rdata_pipe0 = sepc;
                CSR_SCAUSE: csr_rdata_pipe0 = scause;
                CSR_STVAL: csr_rdata_pipe0 = stval;
                CSR_MSTATUS: csr_rdata_pipe0 = mstatus;
                CSR_MISA: csr_rdata_pipe0 = misa;
                CSR_MIE: csr_rdata_pipe0 = mie;
                CSR_MTVEC: csr_rdata_pipe0 = mtvec;
                CSR_MSCRATCH: csr_rdata_pipe0 = mscratch;
                CSR_MEPC: csr_rdata_pipe0 = mepc;
                CSR_MCAUSE: csr_rdata_pipe0 = mcause;
                CSR_MTVAL: csr_rdata_pipe0 = mtval;
                CSR_MIP: csr_rdata_pipe0 = mip;
                CSR_MHARTID: csr_rdata_pipe0 = HART_ID;
                CSR_MCOUNTINHIBIT: csr_rdata_pipe0 = {29'b0,mcountinhibit};
                CSR_MCYCLE: csr_rdata_pipe0 = mcycle[31:0];
                CSR_CYCLE: csr_rdata_pipe0 = mcycle[31:0];
                CSR_MCYCLEH: csr_rdata_pipe0 = mcycle[63:32];
                CSR_CYCLEH: csr_rdata_pipe0 = mcycle[63:32];
                CSR_MINSTRET: csr_rdata_pipe0 = minstret[31:0];
                CSR_INSTRET: csr_rdata_pipe0 = minstret[31:0];
                CSR_MINSTRETH: csr_rdata_pipe0 = minstret[63:32];
                CSR_INSTRETH: csr_rdata_pipe0 = minstret[63:32];
                CSR_TIME: csr_rdata_pipe0 = time_value[31:0];
                CSR_TIMEH: csr_rdata_pipe0 = time_value[63:32];
                default: begin
                    if (csr_raddr_pipe0 >= 12'h3a0 && csr_raddr_pipe0 <= 12'h3a3)
                        csr_rdata_pipe0 = pmp_config[csr_raddr_pipe0[1:0]*32 +:32];
                    else if (csr_raddr_pipe0 >= 12'h3b0 && csr_raddr_pipe0 <= 12'h3bf)
                        csr_rdata_pipe0 = pmpaddr[csr_raddr_pipe0[3:0]];
                end
            endcase
            if (!csr_rillegal_pipe0)
                csr_rdata_pipe0 = forward_value(csr_raddr_pipe0, csr_rdata_pipe0,
                                                     forward_valid, forward_addr, forward_data);
        end
    end

    assign csr_rillegal_pipe1 = !rst && csr_rvalid_pipe1 && !csr_accessible(csr_raddr_pipe1,current_privilege,mstatus,mcounteren,scounteren);
    assign csr_willegal_pipe1 = !rst && csr_wvalid_pipe1 &&
        (!csr_accessible(csr_waddr_pipe1,current_privilege,mstatus,mcounteren,scounteren) || csr_waddr_pipe1[11:10] == 2'b11);
    always @(*) begin
        csr_rdata_pipe1 = 0;
        if (!rst && csr_rvalid_pipe1) begin
            case (csr_raddr_pipe1)
                12'h7a0: csr_rdata_pipe1 = {31'b0,tselect};
                12'h7a1: csr_rdata_pipe1 = tdata1[tselect];
                12'h7a2: csr_rdata_pipe1 = tdata2[tselect];
                12'h7a4: csr_rdata_pipe1 = 32'h4; // type 2 supported
                12'h7a5: csr_rdata_pipe1 = {24'b0,tcontrol};
                CSR_SSTATUS: csr_rdata_pipe1 = mstatus & SSTATUS_MASK;
                CSR_SIE: csr_rdata_pipe1 = mie & mideleg;
                CSR_SIP: csr_rdata_pipe1 = mip & mideleg;
                CSR_MEDELEG: csr_rdata_pipe1 = medeleg;
                CSR_MIDELEG: csr_rdata_pipe1 = mideleg;
                CSR_MCOUNTEREN: csr_rdata_pipe1 = mcounteren;
                CSR_SCOUNTEREN: csr_rdata_pipe1 = scounteren;
                CSR_STVEC: csr_rdata_pipe1 = stvec;
                CSR_SSCRATCH: csr_rdata_pipe1 = sscratch;
                CSR_SEPC: csr_rdata_pipe1 = sepc;
                CSR_SCAUSE: csr_rdata_pipe1 = scause;
                CSR_STVAL: csr_rdata_pipe1 = stval;
                CSR_MSTATUS: csr_rdata_pipe1 = mstatus;
                CSR_MISA: csr_rdata_pipe1 = misa;
                CSR_MIE: csr_rdata_pipe1 = mie;
                CSR_MTVEC: csr_rdata_pipe1 = mtvec;
                CSR_MSCRATCH: csr_rdata_pipe1 = mscratch;
                CSR_MEPC: csr_rdata_pipe1 = mepc;
                CSR_MCAUSE: csr_rdata_pipe1 = mcause;
                CSR_MTVAL: csr_rdata_pipe1 = mtval;
                CSR_MIP: csr_rdata_pipe1 = mip;
                CSR_MHARTID: csr_rdata_pipe1 = HART_ID;
                CSR_MCOUNTINHIBIT: csr_rdata_pipe1 = {29'b0,mcountinhibit};
                CSR_MCYCLE: csr_rdata_pipe1 = mcycle[31:0];
                CSR_CYCLE: csr_rdata_pipe1 = mcycle[31:0];
                CSR_MCYCLEH: csr_rdata_pipe1 = mcycle[63:32];
                CSR_CYCLEH: csr_rdata_pipe1 = mcycle[63:32];
                CSR_MINSTRET: csr_rdata_pipe1 = minstret[31:0];
                CSR_INSTRET: csr_rdata_pipe1 = minstret[31:0];
                CSR_MINSTRETH: csr_rdata_pipe1 = minstret[63:32];
                CSR_INSTRETH: csr_rdata_pipe1 = minstret[63:32];
                CSR_TIME: csr_rdata_pipe1 = time_value[31:0];
                CSR_TIMEH: csr_rdata_pipe1 = time_value[63:32];
                default: begin
                    if (csr_raddr_pipe1 >= 12'h3a0 && csr_raddr_pipe1 <= 12'h3a3)
                        csr_rdata_pipe1 = pmp_config[csr_raddr_pipe1[1:0]*32 +:32];
                    else if (csr_raddr_pipe1 >= 12'h3b0 && csr_raddr_pipe1 <= 12'h3bf)
                        csr_rdata_pipe1 = pmpaddr[csr_raddr_pipe1[3:0]];
                end
            endcase
            if (!csr_rillegal_pipe1)
                csr_rdata_pipe1 = forward_value(csr_raddr_pipe1, csr_rdata_pipe1,
                                                     forward_valid, forward_addr, forward_data);
        end
    end

    wire write0 = csr_wvalid_pipe0 && !csr_willegal_pipe0 && !trap_valid && !mret_valid && !sret_valid;
    wire write1 = csr_wvalid_pipe1 && !csr_willegal_pipe1 && !trap_valid && !mret_valid && !sret_valid;
    // Control writes and xRET are serialized by the core. One CSR per group.
    always @(posedge clk) begin
        if (rst) begin
            current_privilege<=PRIV_M; mstatus<=32'h1800;
            mie<=0; mtvec<=0; mscratch<=0; mepc<=0; mcause<=0; mtval<=0;
            medeleg<=0; mideleg<=0; mcounteren<=0; scounteren<=0;
            stvec<=0; sscratch<=0; sepc<=0; scause<=0; stval<=0; supervisor_pending<=0;
        end else if (trap_valid) begin
            if (trap_to_supervisor) begin
                sepc<={trap_pc[31:2],2'b0}; scause<=trap_cause; stval<=trap_value;
                mstatus[8]<=current_privilege==PRIV_S;
                mstatus[5]<=mstatus[1]; mstatus[1]<=0;
                current_privilege<=PRIV_S;
            end else begin
                mepc<={trap_pc[31:2],2'b0}; mcause<=trap_cause; mtval<=trap_value;
                mstatus[12:11]<=current_privilege;
                mstatus[7]<=mstatus[3]; mstatus[3]<=0;
                current_privilege<=PRIV_M;
            end
        end else if (mret_valid) begin
            current_privilege<=mstatus[12:11];
            mstatus[3]<=mstatus[7]; mstatus[7]<=1; mstatus[12:11]<=PRIV_U;
            if (mstatus[12:11]!=PRIV_M) mstatus[17]<=0;
        end else if (sret_valid) begin
            current_privilege<=mstatus[8] ? PRIV_S : PRIV_U;
            mstatus[1]<=mstatus[5]; mstatus[5]<=1; mstatus[8]<=0; mstatus[17]<=0;
        end else begin
            if (write0) begin
                case (csr_waddr_pipe0)
                    CSR_MSTATUS: mstatus<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MIE: mie<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MTVEC: mtvec<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MSCRATCH: mscratch<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MEPC: mepc<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MCAUSE: mcause<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MTVAL: mtval<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MEDELEG: medeleg<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MIDELEG: mideleg<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_MCOUNTEREN: mcounteren<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_SCOUNTEREN: scounteren<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_STVEC: stvec<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_SSCRATCH: sscratch<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_SEPC: sepc<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_SCAUSE: scause<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_STVAL: stval<=normalize_write(csr_waddr_pipe0,csr_wdata_pipe0);
                    CSR_SSTATUS: mstatus<=(mstatus & ~SSTATUS_MASK) | normalize_write(CSR_SSTATUS,csr_wdata_pipe0);
                    CSR_SIE: mie<=(mie & ~(mideleg & MIE_MASK)) | normalize_write(CSR_SIE,csr_wdata_pipe0);
                    CSR_MIP: supervisor_pending<=normalize_write(CSR_MIP,csr_wdata_pipe0);
                    CSR_SIP: supervisor_pending<=(supervisor_pending & ~(mideleg & 32'h2)) | normalize_write(CSR_SIP,csr_wdata_pipe0);
                    default: begin end
                endcase
            end
            if (write1) begin
                case (csr_waddr_pipe1)
                    CSR_MSTATUS: mstatus<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MIE: mie<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MTVEC: mtvec<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MSCRATCH: mscratch<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MEPC: mepc<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MCAUSE: mcause<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MTVAL: mtval<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MEDELEG: medeleg<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MIDELEG: mideleg<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_MCOUNTEREN: mcounteren<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_SCOUNTEREN: scounteren<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_STVEC: stvec<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_SSCRATCH: sscratch<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_SEPC: sepc<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_SCAUSE: scause<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_STVAL: stval<=normalize_write(csr_waddr_pipe1,csr_wdata_pipe1);
                    CSR_SSTATUS: mstatus<=(mstatus & ~SSTATUS_MASK) | normalize_write(CSR_SSTATUS,csr_wdata_pipe1);
                    CSR_SIE: mie<=(mie & ~(mideleg & MIE_MASK)) | normalize_write(CSR_SIE,csr_wdata_pipe1);
                    CSR_MIP: supervisor_pending<=normalize_write(CSR_MIP,csr_wdata_pipe1);
                    CSR_SIP: supervisor_pending<=(supervisor_pending & ~(mideleg & 32'h2)) | normalize_write(CSR_SIP,csr_wdata_pipe1);
                    default: begin end
                endcase
            end
        end
    end

    function [31:0] trigger_normalize;
        input [31:0] value;
        begin trigger_normalize = value[31:28] == 4'h2 ?
            32'h20000000 | (value & 32'h47) : 32'b0; end
    endfunction
    always @(posedge clk) begin
        if (rst) begin
            tselect<=0; tdata1[0]<=0; tdata1[1]<=0;
            tdata2[0]<=0; tdata2[1]<=0; tcontrol<=0;
        end else if (trap_valid && !trap_to_supervisor) begin
            tcontrol <= {tcontrol[3],7'b0}; // MPTE=MTE; MTE=0 prevents recursive traps.
        end else if (mret_valid) begin
            tcontrol <= 8'h80 | {4'b0,tcontrol[7],3'b0};
        end else begin
            if (write0) begin
                case (csr_waddr_pipe0)
                    12'h7a0: if (csr_wdata_pipe0<2) tselect<=csr_wdata_pipe0[0];
                    12'h7a1: tdata1[tselect]<=trigger_normalize(csr_wdata_pipe0);
                    12'h7a2: tdata2[tselect]<=csr_wdata_pipe0;
                    12'h7a5: tcontrol<=csr_wdata_pipe0[7:0] & 8'h88;
                    default: begin end
                endcase
            end
            if (write1) begin
                case (csr_waddr_pipe1)
                    12'h7a0: if (csr_wdata_pipe1<2) tselect<=csr_wdata_pipe1[0];
                    12'h7a1: tdata1[tselect]<=trigger_normalize(csr_wdata_pipe1);
                    12'h7a2: tdata2[tselect]<=csr_wdata_pipe1;
                    12'h7a5: tcontrol<=csr_wdata_pipe1[7:0] & 8'h88;
                    default: begin end
                endcase
            end
        end
    end

    function [7:0] pmp_normalize;
        input [7:0] value;
        // W=1/R=0 is reserved; coerce W to zero. Reserved bits read zero.
        begin pmp_normalize = value & 8'h9d | {6'b0,(value[1] & value[0]),1'b0}; end
    endfunction
    integer pmp_i;
    always @(posedge clk) begin
        for (pmp_i=0; pmp_i<16; pmp_i=pmp_i+1) begin
            if (rst) begin pmpcfg[pmp_i]<=0; pmpaddr[pmp_i]<=0; end
            else begin
                if (!pmpcfg[pmp_i][7]) begin
                    if (write0 && csr_waddr_pipe0 == {10'h0e8,pmp_i[3:2]})
                        pmpcfg[pmp_i] <= pmp_normalize(csr_wdata_pipe0[(pmp_i%4)*8 +:8]);
                    if (write1 && csr_waddr_pipe1 == {10'h0e8,pmp_i[3:2]})
                        pmpcfg[pmp_i] <= pmp_normalize(csr_wdata_pipe1[(pmp_i%4)*8 +:8]);
                end
                // A locked TOR entry also locks the preceding address register.
                if (!pmpcfg[pmp_i][7] &&
                    (pmp_i==15 || (pmpcfg[(pmp_i+1)%16] & 8'h98) != 8'h88)) begin
                    if (write0 && csr_waddr_pipe0 == {8'h3b,pmp_i[3:0]}) pmpaddr[pmp_i]<=csr_wdata_pipe0;
                    if (write1 && csr_waddr_pipe1 == {8'h3b,pmp_i[3:0]}) pmpaddr[pmp_i]<=csr_wdata_pipe1;
                end
            end
        end
    end

    wire cycle_write0 = write0 && (csr_waddr_pipe0 == CSR_MCYCLE || csr_waddr_pipe0 == CSR_MCYCLEH);
    wire cycle_write1 = write1 && (csr_waddr_pipe1 == CSR_MCYCLE || csr_waddr_pipe1 == CSR_MCYCLEH);
    wire instret_write0 = write0 && (csr_waddr_pipe0 == CSR_MINSTRET || csr_waddr_pipe0 == CSR_MINSTRETH);
    wire instret_write1 = write1 && (csr_waddr_pipe1 == CSR_MINSTRET || csr_waddr_pipe1 == CSR_MINSTRETH);
    always @(posedge clk) begin
        if (rst) begin mcycle<=0; minstret<=0; mcountinhibit<=0; end
        else begin
            if (cycle_write1)
                mcycle <= csr_waddr_pipe1 == CSR_MCYCLE ? {mcycle[63:32],csr_wdata_pipe1} : {csr_wdata_pipe1,mcycle[31:0]};
            else if (cycle_write0)
                mcycle <= csr_waddr_pipe0 == CSR_MCYCLE ? {mcycle[63:32],csr_wdata_pipe0} : {csr_wdata_pipe0,mcycle[31:0]};
            else if (!mcountinhibit[0]) mcycle <= mcycle + 64'd1;
            if (instret_write1)
                minstret <= csr_waddr_pipe1 == CSR_MINSTRET ? {minstret[63:32],csr_wdata_pipe1} : {csr_wdata_pipe1,minstret[31:0]};
            else if (instret_write0)
                minstret <= csr_waddr_pipe0 == CSR_MINSTRET ? {minstret[63:32],csr_wdata_pipe0} : {csr_wdata_pipe0,minstret[31:0]};
            else if (!mcountinhibit[2]) minstret <= minstret + {62'b0,retire_count};
            if (write0 && csr_waddr_pipe0 == CSR_MCOUNTINHIBIT) mcountinhibit <= csr_wdata_pipe0[2:0] & 3'b101;
            if (write1 && csr_waddr_pipe1 == CSR_MCOUNTINHIBIT) mcountinhibit <= csr_wdata_pipe1[2:0] & 3'b101;
        end
    end
endmodule
