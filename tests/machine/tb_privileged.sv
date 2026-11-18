`timescale 1ns/1ps
module tb_machine_mode;
    reg clk=0,rst=1,irq_software=0,irq_timer=0,irq_external=0;
    reg imem_ready=1,dmem_ready=1;
    reg [63:0] time_value=64'h123456789abcdef0;
    reg [31:0] rom[0:511];
    wire [31:0] pc;
    reg [159:0] scenario="ecall";
    integer ignored,i,traps=0,returns=0,stores=0,h=384,irq_code=7,slot=0,fault_index=8;
    reg [31:0] saved_pc[0:7],saved_cause[0:7],saved_value[0:7];
    reg [31:0] saved_loop=0;
    reg irq_case=0;
    reg irq_raised=0;
    reg [63:0] first_trap_instret=0;
    integer observed_traps=0;
    always @(negedge clk) if(!rst && traps>observed_traps) begin
        if(observed_traps==0) first_trap_instret=dut.csr_inst.minstret;
        observed_traps=traps;
    end
    core #(.PC_INIT(0),.SUPPORT_MISALIGNED(0)) dut (
        .CLK(clk),.RESET(rst),.locked(1'b1),.imem_fault(2'b0), .dmem_fault(2'b0), .imem_ready(imem_ready),.dmem_ready(dmem_ready),
        .irq_software(irq_software),.irq_timer(irq_timer),.irq_external(irq_external),.time_value(time_value),
        .Instr_pipe0(rom[pc[10:2]]),.Instr_pipe1(rom[pc[10:2]+9'd1]),
        .ReadData_in_pipe0(32'h25),.ReadData_in_pipe1(32'h25),
        .PC(pc),.MemRead(),.MemWrite_out_pipe0(),.MemWrite_out_pipe1(),.ALUResult_pipe0(),.ALUResult_pipe1(),
        .WriteData_out_pipe0(),.WriteData_out_pipe1(),.LwSizeSel_pipe0(),.LwSizeSel_pipe1()
    );
    always #5 clk=~clk;
    function [31:0] ci(input [2:0] f,input [4:0] rd,input [11:0] a,input [4:0] src);
        ci={a,src,f,rd,7'h73};
    endfunction
    function [31:0] ai(input [4:0] rd,rs,input [11:0] imm); ai={imm,rs,3'b0,rd,7'h13};endfunction
    task ck(input integer regno,input [31:0] value);
        if(dut.reg_file_inst.RegBank[regno]!==value)
            $fatal(1,"%0s x%0d=%h expected=%h",scenario,regno,dut.reg_file_inst.RegBank[regno],value);
    endtask
    always @(posedge clk) if(!rst) begin
        if(dut.csr_trap_fire) begin
            if(traps>=8) $fatal(1,"repeated trap loop");
            saved_pc[traps]=dut.csr_trap_pc;saved_cause[traps]=dut.trap_cause;saved_value[traps]=dut.trap_value;
            saved_loop=dut.reg_file_inst.RegBank[21];traps++;
        end
        if(dut.mret_fire) returns++;
        if(dut.MemWrite_out_pipe0 || dut.MemWrite_out_pipe1) stores++;
        if((!imem_ready || !dmem_ready) && (dut.csr_trap_fire || dut.mret_fire ||
            dut.csr_wfire_mem_pipe0 || dut.csr_wfire_mem_pipe1)) $fatal(1,"side effect during stall");
    end
    initial begin
        ignored=$value$plusargs("case=%s",scenario);
        ignored=$value$plusargs("slot=%d",slot);
        for(i=0;i<512;i++)rom[i]=32'h13;
        rom[0]=ai(30,0,'h600);rom[1]=ci(1,0,'h305,30);
        rom[2]=ai(1,0,'h123);rom[3]=ci(1,0,'h340,1);
        rom[9]=ai(20,0,77);rom[40]=ai(31,0,1);
        case(scenario)
            "ecall","trap_stall","sync_irq":rom[8]=32'h00000073;
            "ebreak":rom[8]=32'h00100073;
            "illegal":rom[8]=32'hffffffff;
            "zero":rom[8]=0;
            "system":rom[8]=32'h20200073; // Unsupported HRET encoding.
            "unsupported":rom[8]=ci(2,2,'h600,0);
            "load_align":rom[8]={12'd2,5'b0,3'b010,5'd2,7'h03};
            "store_align":rom[8]=32'h00102123; // sw x1,2(x0)
            "jump_align":rom[8]=32'h0020006f; // jal x0,+2
            "fence":begin rom[8]=32'h0000100f;rom[10]=32'h0000000f;rom[11]=32'h10500073;end
            "fence_pipe1":begin rom[9]=32'h0000100f;rom[10]=ai(20,0,77);rom[11]=32'h0000000f;rom[12]=32'h10500073;end
            "mret","mret_pipe1":begin
                rom[4]=ai(3,0,'h80);rom[5]=ci(2,0,'h300,3);
                rom[6]=ai(2,0,48);rom[7]=ci(1,0,'h341,2);rom[8]=32'h30200073;
                rom[9]=ci(5,0,'h340,7);rom[12]=ai(20,0,77);
            end
            "counters":begin
                rom[0]=ci(2,1,'hb02,0);rom[1]=ci(2,2,'hb02,0);
                rom[2]=ci(5,0,'hb02,7);rom[3]=ci(2,3,'hb02,0);
                rom[4]=ci(2,4,'hc02,0);rom[5]=ci(2,5,'h301,0);
                rom[6]=ci(2,6,'hc01,0);rom[7]=ci(2,7,'hc81,0);
            end
            "timer","software","external","priority","vectored","retrigger","irq_masked","irq_global_masked":begin
                irq_case=1;
                if(scenario=="software")irq_code=3;
                if(scenario=="external" || scenario=="priority" || scenario=="vectored")irq_code=11;
                if(scenario=="vectored")begin rom[0]=ai(30,0,'h601);h=384+11;end
                rom[4]=ai(2,0,'h888);rom[5]=ci(1,0,'h304,2);rom[6]=ci(5,0,'h300,8);
                rom[8]=ai(21,21,1);rom[9]=32'hffdff06f; // loop to word8
                if(scenario=="irq_global_masked")begin rom[6]=ci(5,0,'h300,0);rom[9]=ai(31,0,1);end
                if(scenario=="irq_masked")begin
                    rom[5]=ci(5,0,'h304,0);rom[9]=ai(31,0,1);
                end
            end
            default:$fatal(1,"unknown case %0s",scenario);
        endcase
        if(slot==1)begin
            rom[9]=rom[8];rom[8]=32'h13;rom[10]=ai(20,0,77);fault_index=9;
        end
        if(scenario=="mret_pipe1")begin rom[8]=32'h13;rom[9]=32'h30200073;rom[10]=ci(5,0,'h340,7);end
        if(scenario=="sync_irq")begin
            rom[4]=ai(2,0,'h80);rom[5]=ci(1,0,'h304,2);rom[6]=ci(5,0,'h300,8);
        end
        rom[h+0]=ci(2,10,'h342,0);rom[h+1]=ci(2,11,'h341,0);
        rom[h+2]=ci(2,12,'h343,0);rom[h+3]=ci(2,13,'h300,0);rom[h+4]=ci(2,14,'h341,0);
        rom[h+5]=32'h00054663; // blt x10,x0,+12: interrupts resume without skipping an instruction.
        rom[h+6]=ai(14,14,4);rom[h+7]=ci(1,0,'h341,14);rom[h+8]=32'h30200073;
        repeat(3)@(negedge clk);rst=0;
        if(irq_case && scenario!="irq_masked" && scenario!="irq_global_masked") begin
            wait(returns >= (scenario=="retrigger" ? 2 : 1));
            wait(dut.reg_file_inst.RegBank[21]>saved_loop);
        end else wait(dut.reg_file_inst.RegBank[31]==1);
        @(negedge clk);
        if(irq_case && scenario!="irq_masked" && scenario!="irq_global_masked")begin
            if(traps != (scenario=="retrigger"?2:1))$fatal(1,"wrong interrupt count %0d",traps);
            if(saved_cause[0]!== (32'h80000000|irq_code))$fatal(1,"wrong interrupt cause %h",saved_cause[0]);
            if(saved_pc[0]!==32 && saved_pc[0]!==36)$fatal(1,"imprecise interrupt PC %h",saved_pc[0]);
            if(dut.csr_inst.mstatus!==32'h88)$fatal(1,"MRET did not restore interrupt state");
        end else if(scenario=="irq_masked" || scenario=="irq_global_masked")begin if(!irq_raised || traps!=0)$fatal(1,"disabled IRQ taken");end
        else if(scenario=="mret" || scenario=="mret_pipe1")begin
            if(traps!=0 || returns!=1)$fatal(1,"wrong MRET flow");
            ck(20,77);if(dut.csr_inst.mscratch!==32'h123 || dut.csr_inst.mstatus!==32'h88)$fatal(1,"MRET state");
        end else if(scenario=="counters")begin
            ck(1,0);ck(2,1);ck(3,7);ck(4,8);ck(5,'h40141101);ck(6,'h9abcdef0);ck(7,'h12345678);
        end else if(scenario=="fence" || scenario=="fence_pipe1")begin if(traps!=0)$fatal(1,"FENCE/WFI trapped");ck(20,77);end
        else begin
            if(traps!=(scenario=="sync_irq"?2:1) || returns!=traps)$fatal(1,"trap/return count %0d/%0d",traps,returns);
            if(saved_pc[0]!==4*fault_index)$fatal(1,"wrong synchronous mepc %h",saved_pc[0]);
            case(scenario)
                "ecall","trap_stall","sync_irq":if(saved_cause[0]!==11)$fatal(1,"ECALL cause");
                "ebreak":if(saved_cause[0]!==3 || saved_value[0]!==4*fault_index)$fatal(1,"EBREAK cause/value");
                "load_align":if(saved_cause[0]!==4 || saved_value[0]!==2)$fatal(1,"load misalign");
                "store_align":if(saved_cause[0]!==6 || saved_value[0]!==2)$fatal(1,"store misalign");
                "jump_align":if(saved_cause[0]!==0 || saved_value[0]!==4*fault_index+2)$fatal(1,"jump misalign");
                default:if(saved_cause[0]!==2 || saved_value[0]!==rom[fault_index])$fatal(1,"illegal cause/mtval");
            endcase
            if(scenario=="sync_irq" && saved_cause[1]!==32'h80000007)$fatal(1,"IRQ lost after synchronous fault");
            if((scenario=="ecall" || scenario=="ebreak" || scenario=="illegal" || scenario=="zero") && first_trap_instret!==fault_index)
                $fatal(1,"faulting instruction retired or older instruction lost: %0d",first_trap_instret);
            ck(20,77);if(stores!=0)$fatal(1,"faulting store escaped");
        end
        $display("PASS: machine %0s",scenario);$finish;
    end
    initial begin
        wait(!rst);
        if(irq_case)begin
            if(scenario=="irq_global_masked")wait(dut.csr_inst.mie!=0);
            else wait(dut.csr_inst.mstatus[3]);
            if(scenario=="irq_masked" || scenario=="irq_global_masked") wait(pc>=32 && pc<128);
            else wait((dut.valid_mem_pipe0 && dut.pc_mem_pipe0==32) ||
                      (dut.valid_mem_pipe1 && dut.pc_mem_pipe1==32));
            @(negedge clk);
            irq_raised=1;
            case(scenario)
                "software":irq_software=1;
                "external","vectored":irq_external=1;
                "priority":begin irq_software=1;irq_timer=1;irq_external=1;end
                default:irq_timer=1;
            endcase
            if(scenario!="irq_masked" && scenario!="irq_global_masked")begin
                wait(traps >= (scenario=="retrigger"?2:1));@(negedge clk);
                irq_software=0;irq_timer=0;irq_external=0;
            end
        end else if(scenario=="sync_irq")begin
            wait(dut.valid_ex_pipe0 && dut.instruction_ex_pipe0==32'h00000073);
            @(negedge clk);irq_timer=1;
            wait(traps==2);@(negedge clk);irq_timer=0;
        end else if(scenario=="trap_stall")begin
            wait(dut.csr_trap_pipe0 || dut.csr_trap_pipe1);@(negedge clk);
            imem_ready=0;dmem_ready=0;repeat(3)@(negedge clk);imem_ready=1;dmem_ready=1;
        end
    end
    initial begin #50000;$fatal(1,"timeout machine %0s pc=%h",scenario,pc);end
endmodule
