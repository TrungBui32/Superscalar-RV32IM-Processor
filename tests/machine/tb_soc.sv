`timescale 1ns/1ps
module tb_machine_soc_precision;
    reg clk=0,rst=1;
    wire [7:0] tx;
    wire txvalid;
    integer i,chars=0,traps=0,cycles=0;
    soc_top dut(.CLK(clk),.RESET(rst),.DIP(16'b0),.PB(3'b0),
        .UART_TX(tx),.UART_TX_valid(txvalid),.UART_TX_ready(1'b1),
        .UART_RX(8'b0),.UART_RX_valid(1'b0),.ACCEL_Data(32'b0),.ACCEL_DReady(1'b0));
    always #5 clk=~clk;
    function [31:0] ai(input [4:0] rd,rs,input [11:0] imm);ai={imm,rs,3'b0,rd,7'h13};endfunction
    function [31:0] sw(input [4:0] rs,base,input [11:0] imm);sw={imm[11:5],rs,base,3'b010,imm[4:0],7'h23};endfunction
    always @(negedge clk)if(!rst && txvalid)begin
        if(tx!==8'h42 || chars!=0)$fatal(1,"UART selected wrong pipe or leaked a younger store: tx=%h count=%0d",tx,chars);
        chars++;
    end
    always @(posedge clk)if(!rst)begin
        cycles++;
        if(dut.core_inst.csr_trap_fire)begin
            traps++;
            if(dut.core_inst.trap_cause!==7 || dut.core_inst.trap_value!==32'h20000000)$fatal(1,"SoC access fault cause/value");
        end
        if(cycles==100)begin
            if(chars!=1 || traps!=1 || dut.DMEM.mem[0]!==32'haa)$fatal(1,"SoC precision chars=%0d traps=%0d ram=%h",chars,traps,dut.DMEM.mem[0]);
            $display("PASS full SoC dual-store routing and younger MMIO cancellation");$finish;
        end
    end
    initial begin
        for(i=0;i<8192;i++)dut.IROM.mem[i]=32'h13;
        for(i=0;i<4096;i++)dut.DMEM.mem[i]=0;
        dut.IROM.mem[0]={20'hffff0,5'd10,7'h37}; // a0=UART page
        dut.IROM.mem[1]=ai(10,10,12);
        dut.IROM.mem[2]={20'h10010,5'd11,7'h37}; // a1=DMEM
        dut.IROM.mem[3]=ai(12,0,'haa);
        dut.IROM.mem[4]=ai(13,0,'h42);
        dut.IROM.mem[5]={20'h00400,5'd14,7'h37};
        dut.IROM.mem[6]=ai(14,14,'h100);
        dut.IROM.mem[7]={12'h305,5'd14,3'b001,5'd0,7'h73};
        // Simultaneous unrelated stores: UART must use pipe1's data.
        dut.IROM.mem[8]=sw(12,11,0);
        dut.IROM.mem[9]=sw(13,10,0);
        dut.IROM.mem[10]={20'h20000,5'd15,7'h37};
        dut.IROM.mem[11]=32'h13;
        // Older invalid store must cancel younger UART store.
        dut.IROM.mem[12]=sw(12,15,0);
        dut.IROM.mem[13]=sw(13,10,0);
        dut.IROM.mem[64]=32'h0000006f;
        repeat(4)@(negedge clk);rst=0;
    end
endmodule
