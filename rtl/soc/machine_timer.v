`timescale 1ns/1ps

// Single-hart MMIO timer. IRQ outputs and time_value are synchronous to clk.
// 0x02000000 msip, 0x02004000 mtimecmp, 0x0200bff8 mtime (64-bit low/high).
module machine_timer(
    input clk, input rst,
    input [31:0] addr_pipe0, input [31:0] addr_pipe1,
    input [31:0] wdata_pipe0, input [31:0] wdata_pipe1,
    input [3:0] wstrb_pipe0, input [3:0] wstrb_pipe1,
    output reg [31:0] rdata_pipe0, output reg [31:0] rdata_pipe1,
    output hit_pipe0, output hit_pipe1,
    output irq_software, output irq_timer,
    output [63:0] time_value
);
    reg [63:0] mtime, mtimecmp;
    reg msip;
    reg [63:0] next_time, next_compare;
    reg next_msip, time_written;
    integer port_index, lane;
    reg [31:0] address, data;
    reg [3:0] strobe;
    function hit;
        input [31:0] addr;
        begin
            case ({addr[31:2],2'b0})
                32'h02000000,32'h02004000,32'h02004004,32'h0200bff8,32'h0200bffc: hit=1'b1;
                default:hit=1'b0;
            endcase
        end
    endfunction
    assign hit_pipe0=hit(addr_pipe0);
    assign hit_pipe1=hit(addr_pipe1);
    assign irq_software=msip;
    assign irq_timer=(mtime>=mtimecmp);
    assign time_value=mtime;
    always @(*) begin
        rdata_pipe0=0;rdata_pipe1=0;
        case ({addr_pipe0[31:2],2'b0})
            32'h02000000:rdata_pipe0={31'b0,msip};
            32'h02004000:rdata_pipe0=mtimecmp[31:0];
            32'h02004004:rdata_pipe0=mtimecmp[63:32];
            32'h0200bff8:rdata_pipe0=mtime[31:0];
            32'h0200bffc:rdata_pipe0=mtime[63:32];
            default:begin end
        endcase
        case ({addr_pipe1[31:2],2'b0})
            32'h02000000:rdata_pipe1={31'b0,msip};
            32'h02004000:rdata_pipe1=mtimecmp[31:0];
            32'h02004004:rdata_pipe1=mtimecmp[63:32];
            32'h0200bff8:rdata_pipe1=mtime[31:0];
            32'h0200bffc:rdata_pipe1=mtime[63:32];
            default:begin end
        endcase
    end
    always @(*) begin
        next_time=mtime;next_compare=mtimecmp;next_msip=msip;time_written=0;
        address=0;data=0;strobe=0;
        // Merge both byte writes in age order, even across the 64-bit halves.
        for(port_index=0;port_index<2;port_index=port_index+1)begin
            address=port_index==0 ? addr_pipe0:addr_pipe1;
            data=port_index==0 ? wdata_pipe0:wdata_pipe1;
            strobe=port_index==0 ? wstrb_pipe0:wstrb_pipe1;
            for(lane=0;lane<4;lane=lane+1)if(strobe[lane])begin
                case({address[31:2],2'b0})
                    32'h02000000:if(lane==0)next_msip=data[0];
                    32'h02004000:next_compare[lane*8 +:8]=data[lane*8 +:8];
                    32'h02004004:next_compare[32+lane*8 +:8]=data[lane*8 +:8];
                    32'h0200bff8:begin next_time[lane*8 +:8]=data[lane*8 +:8];time_written=1;end
                    32'h0200bffc:begin next_time[32+lane*8 +:8]=data[lane*8 +:8];time_written=1;end
                    default:begin end
                endcase
            end
        end
        if(!time_written)next_time=mtime+64'd1;
    end
    always @(posedge clk)begin
        if(rst)begin mtime<=0;mtimecmp<=64'hffffffffffffffff;msip<=0;end
        else begin mtime<=next_time;mtimecmp<=next_compare;msip<=next_msip;end
    end
endmodule
