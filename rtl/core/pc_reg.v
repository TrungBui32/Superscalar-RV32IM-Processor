`timescale 1ns / 1ps


module pc_reg #(
    parameter PC_INIT = 32'h00400000
)(
    input CLK,
    input RESET,
    input WE_PC,    // write enable, for multi-cycle operations and pipelining
    input [31:0] PC_IN,
    output reg [31:0] PC  
    );
    
    initial begin 
        PC <= PC_INIT;
    end
    
    always@( posedge CLK )
    begin
        if(RESET)
            PC <= PC_INIT;
        else if(WE_PC)
            PC <= PC_IN;        
    end
    
endmodule










