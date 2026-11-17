`timescale 1ns/1ps
// Blocking RV32 Zaamo + Zalrsc engine. The arbiter must drain older work and
// exclude every other writer while lock_req/lock_grant hold ownership.
// Once granted, ownership must be retained until lock_req drops.
// req/rsp and memory req/rsp are independent valid/ready handshakes.
module atomic_unit(
    input wire clk, rst,
    input wire req_valid,
    output wire req_ready,
    input wire [4:0] req_funct5,
    input wire req_aq, req_rl,
    input wire [31:0] req_addr, req_operand,
    output wire rsp_valid,
    input wire rsp_ready,
    output reg [31:0] rsp_result,
    output reg rsp_exception,
    output reg [4:0] rsp_cause,
    output reg [31:0] rsp_tval,
    output wire lock_req,
    input wire lock_grant,
    output wire mem_req_valid,
    input wire mem_req_ready,
    output wire mem_req_write,
    output wire [31:0] mem_req_addr, mem_req_wdata,
    output wire [3:0] mem_req_wstrb,
    input wire mem_rsp_valid,
    output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata,
    input wire mem_rsp_error,
    // Conservative invalidation on ANY observed committed store also covers
    // physical RAM aliases. Constrained LR/SC loops contain no such stores.
    input wire invalidate_reservation,
    input wire clear_reservation
);
    localparam [4:0] LR=5'b00010, SC=5'b00011;
    localparam [2:0] IDLE=0, LOCK=1, READ_REQ=2, READ_WAIT=3,
                     WRITE_REQ=4, WRITE_WAIT=5, RESPONSE=6;
    reg [2:0] state;
    reg [4:0] op;
    reg [31:0] address, operand, write_data;
    reg reservation_valid, sc_candidate;
    reg [29:0] reservation_word;
    // Every operation is fully serialized, imposing at least the ordering
    // required by all aq/rl combinations. The bits do not change arithmetic.
    wire request_fire = req_valid && req_ready;
    wire invalidated = invalidate_reservation || clear_reservation;
    assign req_ready = !rst && state == IDLE;
    assign rsp_valid = !rst && state == RESPONSE;
    assign lock_req = !rst && state != IDLE && state != RESPONSE;
    assign mem_req_valid = !rst && lock_grant &&
        (state == READ_REQ || state == WRITE_REQ);
    assign mem_req_write = state == WRITE_REQ;
    assign mem_req_addr = address;
    assign mem_req_wdata = write_data;
    assign mem_req_wstrb = mem_req_write ? 4'b1111 : 4'b0000;
    assign mem_rsp_ready = !rst && (state == READ_WAIT || state == WRITE_WAIT);

    function legal_op;
        input [4:0] f;
        begin
            case (f)
                5'b00000,5'b00001,LR,SC,5'b00100,5'b01000,
                5'b01100,5'b10000,5'b10100,5'b11000,5'b11100: legal_op=1'b1;
                default: legal_op=1'b0;
            endcase
        end
    endfunction
    function [31:0] modify;
        input [4:0] f;
        input [31:0] old_value, value;
        begin
            case (f)
                5'b00001: modify=value;
                5'b00000: modify=old_value+value;
                5'b00100: modify=old_value^value;
                5'b01000: modify=old_value|value;
                5'b01100: modify=old_value&value;
                5'b10000: modify=$signed(old_value)<$signed(value) ? old_value:value;
                5'b10100: modify=$signed(old_value)>$signed(value) ? old_value:value;
                5'b11000: modify=old_value<value ? old_value:value;
                5'b11100: modify=old_value>value ? old_value:value;
                default: modify=value;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state<=IDLE; op<=0; address<=0; operand<=0; write_data<=0;
            rsp_result<=0; rsp_exception<=0; rsp_cause<=0; rsp_tval<=0;
            reservation_valid<=0; reservation_word<=0; sc_candidate<=0;
        end else begin
            if (invalidated) begin
                reservation_valid<=0;
                sc_candidate<=0;
            end
            case (state)
                IDLE: if (request_fire) begin
                    op<=req_funct5; address<=req_addr; operand<=req_operand;
                    write_data<=req_operand;
                    rsp_result<=0; rsp_exception<=0; rsp_cause<=0; rsp_tval<=req_addr;
                    sc_candidate<=reservation_valid && !invalidated &&
                                  reservation_word==req_addr[31:2];
                    if (req_funct5==LR || req_funct5==SC) reservation_valid<=0;
                    if (!legal_op(req_funct5)) begin
                        rsp_exception<=1; rsp_cause<=2; state<=RESPONSE;
                    end else if (req_addr[1:0]!=0) begin
                        rsp_exception<=1; rsp_cause<=req_funct5==LR ? 4:6;
                        state<=RESPONSE;
                    end else state<=LOCK;
                end
                LOCK: if (lock_grant) begin
                    if (op==SC) begin
                        if (sc_candidate && !invalidated) state<=WRITE_REQ;
                        else begin rsp_result<=1; state<=RESPONSE; end
                    end else state<=READ_REQ;
                end
                READ_REQ: if (mem_req_valid && mem_req_ready) state<=READ_WAIT;
                READ_WAIT: if (mem_rsp_valid && mem_rsp_ready) begin
                    if (mem_rsp_error) begin
                        rsp_exception<=1; rsp_cause<=op==LR ? 5:7;
                        state<=RESPONSE;
                    end else begin
                        rsp_result<=mem_rsp_rdata;
                        if (op==LR) begin
                            reservation_word<=address[31:2];
                            reservation_valid<=!invalidated;
                            state<=RESPONSE;
                        end else begin
                            write_data<=modify(op,mem_rsp_rdata,operand);
                            state<=WRITE_REQ;
                        end
                    end
                end
                WRITE_REQ: begin
                    if (mem_req_valid && mem_req_ready) state<=WRITE_WAIT;
                end
                WRITE_WAIT: if (mem_rsp_valid && mem_rsp_ready) begin
                    if (op==SC) rsp_result<=0;
                    if (mem_rsp_error) begin rsp_exception<=1; rsp_cause<=7; end
                    state<=RESPONSE;
                end
                RESPONSE: if (rsp_ready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
