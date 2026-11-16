`timescale 1ns/1ps
// Split an unaligned halfword/word into byte transactions on an existing port.
// The request remains stable in MEM until busy drops and the pipeline retires it.
// PMP/trigger checks cover the original full access before request is asserted.
module misaligned_access(
    input clk, input rst,
    input request, input step, input retire,
    input [2:0] size,
    input [31:0] address, input [31:0] store_data,
    input [31:0] read_data,
    output busy,
    output [31:0] bus_address,
    output [31:0] bus_store_data,
    output reg [31:0] load_data
);
    reg [1:0] index;
    reg done;
    assign busy=request && !done;
    assign bus_address=address+{30'b0,index};
    assign bus_store_data=store_data >> (index*8);
    always @(posedge clk) begin
        if (rst || !request || retire) begin
            index<=0; done<=0; load_data<=0;
        end else if (step && !done) begin
            load_data[index*8 +:8]<=read_data[7:0];
            if ({1'b0,index}+3'd1==size) done<=1;
            else index<=index+1'b1;
        end
    end
endmodule
