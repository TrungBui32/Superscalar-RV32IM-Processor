`timescale 1ns / 1ps

// One outstanding request. Start is a request level; Busy rises immediately.
// A completed result is retained until ResultReady, even if Start stays high.
module muldiv_unit #(
    parameter width = 32
) (
    input CLK,
    input RESET,
    input Start,
    input [1:0] MCycleOp, // 00: signed MUL, 01: unsigned MUL, 10: DIV, 11: DIVU
    input is_mulsu,      // 01 with signed Operand1 and unsigned Operand2
    input [width-1:0] Operand1,
    input [width-1:0] Operand2,
    output reg [width-1:0] Result1, // Product low / quotient
    output reg [width-1:0] Result2, // Product high / remainder
    output wire Busy,
    input ResultReady           // EX advances or discards this instruction
);
    localparam [2:0] IDLE = 0, MUL_PRODUCT = 1, MUL_RESULT = 2,
                     DIV_STEP = 3, DIV_RESULT = 4, DIV_FAST = 5, DONE = 6;
    localparam COUNT_WIDTH = $clog2(width + 1);
    reg [2:0] state;
    wire request_fire = state == IDLE && Start && !RESET;
    assign Busy = !RESET && ((state == IDLE && Start) ||
                             (state != IDLE && state != DONE));

    // One extra signed bit represents both unsigned and signed operands.
    // Operand, product and result registers give a two-cycle multiply latency
    // after acceptance. Only the multiplier is marked for DSP inference.
    reg signed [width:0] mul_a, mul_b;
    (* use_dsp = "yes" *) reg signed [2*width+1:0] product;
    always @(posedge CLK) begin
        if (request_fire && !MCycleOp[1]) begin
            mul_a <= {(MCycleOp == 2'b00 || is_mulsu) && Operand1[width-1], Operand1};
            mul_b <= {(MCycleOp == 2'b00) && Operand2[width-1], Operand2};
        end
        if (state == MUL_PRODUCT)
            product <= mul_a * mul_b;
    end

    // Four non-restoring binary division steps per cycle. Both signs and
    // divisor forms are captured once; execution never uses live request data.
    reg [2*width:0] partial;
    reg [width:0] divisor, neg_divisor;
    reg quotient_sign, remainder_sign;
    reg [COUNT_WIDTH-1:0] bits_left;
    wire signed_divide = MCycleOp == 2'b10;
    wire [width-1:0] magnitude_a = signed_divide && Operand1[width-1] ?
                                  -Operand1 : Operand1;
    wire [width-1:0] magnitude_b = signed_divide && Operand2[width-1] ?
                                  -Operand2 : Operand2;
    reg [2*width:0] partial_next;
    reg negative_partial;
    integer i;
    always @(*) begin
        partial_next = partial;
        negative_partial = 1'b0;
        for (i = 0; i < 4; i = i + 1) begin
            // The constant condition removes this mux for widths divisible by 4.
            if (width % 4 == 0 || {{(32-COUNT_WIDTH){1'b0}}, bits_left} > i) begin
                negative_partial = partial_next[2*width];
                partial_next = {partial_next[2*width-1:0], 1'b0};
                partial_next[2*width:width] = partial_next[2*width:width] +
                                              (negative_partial ? divisor : neg_divisor);
                partial_next[0] = !partial_next[2*width];
            end
        end
    end
    wire [width-1:0] remainder_magnitude = partial[2*width] ?
                      partial[2*width-1:width] + divisor[width-1:0] :
                      partial[2*width-1:width];

    always @(posedge CLK) begin
        if (RESET) begin
            state <= IDLE;
            Result1 <= 0;
            Result2 <= 0;
            partial <= 0;
            divisor <= 0;
            neg_divisor <= 0;
            bits_left <= 0;
            quotient_sign <= 0;
            remainder_sign <= 0;
        end else begin
            case (state)
                IDLE: if (Start) begin
                    if (!MCycleOp[1]) begin
                        state <= MUL_PRODUCT;
                    end else begin
                        partial <= {{(width+1){1'b0}}, magnitude_a};
                        divisor <= {1'b0, magnitude_b};
                        neg_divisor <= -{1'b0, magnitude_b};
                        quotient_sign <= signed_divide && (Operand1[width-1] ^ Operand2[width-1]);
                        remainder_sign <= signed_divide && Operand1[width-1];
                        bits_left <= width;
                        if (magnitude_b == 0 || magnitude_b == 1 || magnitude_a == 0)
                            state <= DIV_FAST;
                        else
                            state <= DIV_STEP;
                    end
                end
                MUL_PRODUCT: state <= MUL_RESULT;
                MUL_RESULT: begin
                    {Result2, Result1} <= product[2*width-1:0];
                    state <= DONE;
                end
                DIV_FAST: begin
                    if (divisor == 0) begin
                        Result1 <= {width{1'b1}};
                        Result2 <= remainder_sign ? -partial[width-1:0] : partial[width-1:0];
                    end else begin
                        Result1 <= quotient_sign ? -partial[width-1:0] : partial[width-1:0];
                        Result2 <= 0;
                    end
                    state <= DONE;
                end
                DIV_STEP: begin
                    partial <= partial_next;
                    if (bits_left <= 4) begin
                        bits_left <= 0;
                        state <= DIV_RESULT;
                    end else
                        bits_left <= bits_left - 4;
                end
                DIV_RESULT: begin
                    Result1 <= quotient_sign ? -partial[width-1:0] : partial[width-1:0];
                    Result2 <= remainder_sign ? -remainder_magnitude : remainder_magnitude;
                    state <= DONE;
                end
                DONE: if (ResultReady) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
