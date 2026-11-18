`timescale 1ns/1ps
// Behavioral models of the configured synchronous, READ_FIRST FPGA IP.
// CPU period=10ns, BRAM period=5ns with coincident rising edges.
module clk_wiz_0(input clk_in1,reset,output clk_out1,output reg clk_out2=1,output locked);
    assign clk_out1=clk_in1;
    assign locked=1'b1;
    always #2.5 clk_out2=~clk_out2;
endmodule
module c_counter_binary_0(input CLK,SCLR,output reg [31:0] Q=0);
    always @(posedge CLK)if(SCLR)Q<=0;else Q<=Q+1;
endmodule
module blk_mem_gen_0(input [12:0] addra,addrb,input clka,clkb,
    input [31:0] dina,dinb,output reg [31:0] douta,doutb,input ena,enb,rsta,rstb,wea,web);
    reg [31:0] mem[0:8191];
    always @(posedge clka)if(ena)begin douta<=rsta?0:mem[addra];if(wea)mem[addra]<=dina;end
    always @(posedge clkb)if(enb)begin doutb<=rstb?0:mem[addrb];if(web)mem[addrb]<=dinb;end
endmodule
module blk_mem_gen_1(input [11:0] addra,addrb,input clka,clkb,
    input [31:0] dina,dinb,output reg [31:0] douta,doutb,input ena,enb,rsta,rstb,input [3:0] wea,web);
    reg [31:0] mem[0:4095];
    integer la,lb;
    always @(posedge clka)if(ena)begin
        douta<=rsta?0:mem[addra];
        for(la=0;la<4;la++)if(wea[la])mem[addra][8*la+:8]<=dina[8*la+:8];
    end
    always @(posedge clkb)if(enb)begin
        doutb<=rstb?0:mem[addrb];
        for(lb=0;lb<4;lb++)if(web[lb])mem[addrb][8*lb+:8]<=dinb[8*lb+:8];
    end
endmodule
