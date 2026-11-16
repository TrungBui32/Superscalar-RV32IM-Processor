`timescale 1ns/1ps
// M-mode PMP check. Lowest-numbered entry matching any byte wins; a partial
// match faults, and unlocked entries bypass R/W/X in M-mode. End is exclusive.
module pmp_check(
    input [127:0] config_bytes,
    input [511:0] addresses,
    input [31:0] address,
    input [2:0] size,
    input [2:0] access_type, // X W R
    output reg allow,
    output reg [31:0] fault_address
);
    integer i, bit_index;
    reg found;
    reg [7:0] cfg;
    reg [31:0] encoded;
    reg [34:0] lower, upper, first_byte, end_byte, region_size;
    reg trailing;
    always @(*) begin
        allow=1; found=0; fault_address=address;
        first_byte={3'b0,address}; end_byte=first_byte+{32'b0,size};
        // The bus has 32 address bits; a split access may not wrap to zero.
        allow=(end_byte<=35'h100000000);
        cfg=0; encoded=0; lower=0; upper=0; region_size=0; trailing=0;
        for (i=0;i<16;i=i+1) begin
            cfg=config_bytes[i*8 +:8]; encoded=addresses[i*32 +:32];
            lower=0; upper=0; region_size=0; trailing=0;
            case (cfg[4:3])
                2'b01: begin // TOR
                    if (i!=0) lower={1'b0,addresses[(i-1)*32 +:32],2'b0};
                    upper={1'b0,encoded,2'b0};
                end
                2'b10: begin // NA4
                    lower={1'b0,encoded,2'b0}; upper=lower+35'd4;
                end
                2'b11: begin // NAPOT: n trailing ones encode 2^(n+3) bytes.
                    region_size=35'd8; trailing=1;
                    for (bit_index=0;bit_index<32;bit_index=bit_index+1)
                        if (trailing && encoded[bit_index]) region_size=region_size<<1;
                        else trailing=0;
                    lower={1'b0,encoded,2'b0} & ~(region_size-1);
                    upper=lower+region_size;
                end
                default: begin end
            endcase
            if (!found && cfg[4:3]!=0 && first_byte<upper && end_byte>lower) begin
                found=1;
                allow=allow && (first_byte>=lower && end_byte<=upper) &&
                      (!cfg[7] || ((cfg[2:0] & access_type)==access_type));
                if (first_byte>=lower && end_byte>upper) fault_address=upper[31:0];
            end
        end
    end
endmodule
