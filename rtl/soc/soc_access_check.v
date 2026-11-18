`timescale 1ns/1ps
// Physical address map of the connected SoC, independent of request strobes.
// Check the entire transfer; RAM addresses above the real backing store fault.
module soc_access_check(
    input [31:0] pc,
    input [31:0] address0, address1,
    input [2:0] size0, size1,
    input [1:0] write_intent,
    output [1:0] fetch_fault, data_fault
);
    function fetch_ok;
        input [31:0] address;
        begin fetch_ok = address >= 32'h00400000 && address <= 32'h00407ffc; end
    endfunction
    function data_ok;
        input [31:0] address;
        input [2:0] size;
        input write_access;
        reg [32:0] last_byte;
        reg timer_word;
        begin
            last_byte = {1'b0,address} + {30'b0,size} - 33'd1;
            case ({address[31:2],2'b0})
                32'h02000000,32'h02004000,32'h02004004,
                32'h0200bff8,32'h0200bffc: timer_word=1;
                default: timer_word=0;
            endcase
            data_ok = (size==1 || size==2 || size==4) && !last_byte[32] &&
                ((address>=32'h10010000 && last_byte<33'h010014000) ||
                 (timer_word && last_byte[31:2]==address[31:2]) ||
                 (!write_access && (address==32'hffff0008 || address==32'hffff00a0)) ||
                 (write_access && address==32'hffff000c));
        end
    endfunction
    assign fetch_fault = {!fetch_ok(pc+32'd4) || pc>32'hfffffffb, !fetch_ok(pc)};
    assign data_fault = {!data_ok(address1,size1,write_intent[1]),
                         !data_ok(address0,size0,write_intent[0])};
endmodule
