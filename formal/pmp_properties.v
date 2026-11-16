// Combinational PMP contracts, independent of the implementation's word-domain
// comparisons and prefix decoder. No clocks, solver assumptions or test vectors.
module pmp_check_equivalence(
    input [31:0] address,
    input [2:0] size, access_type, permissions,
    input enabled, locked,
    input [32:0] low_word, high_word,
    output equivalent
);
    wire [34:0] lower={low_word,2'b00}, upper={high_word,2'b00};
    wire [127:0] cfg={120'b0,locked,4'b0,permissions};
    wire allow;
    wire [31:0] fault_address;
    pmp_check dut(.config_bytes(cfg),.active_entries({15'b0,enabled}),
        .lower_bounds({525'b0,lower}),.upper_bounds({525'b0,upper}),
        .address(address),.size(size),.access_type(access_type),
        .allow(allow),.fault_address(fault_address));
    wire [34:0] first_byte={3'b0,address};
    wire [34:0] end_byte=first_byte+{32'b0,size};
    wire intersects=enabled && first_byte<upper && end_byte>lower;
    wire contained=first_byte>=lower && end_byte<=upper;
    wire reference_allow=end_byte<=35'h100000000 &&
        (!intersects || (contained && (!locked || (permissions & access_type)==access_type)));
    wire [31:0] reference_fault=(intersects && first_byte>=lower && end_byte>upper) ?
                                upper[31:0] : address;
    // The decoder marks empty ranges inactive. These are the RV32 access sizes.
    wire valid=(size==1 || size==2 || size==4) && (!enabled || low_word<high_word);
    assign equivalent=!valid || (allow==reference_allow && fault_address==reference_fault);
endmodule

module pmp_decode_equivalence(
    input [31:0] encoded, previous,
    input [1:0] mode,
    output equivalent
);
    wire [559:0] lower,upper;
    wire [15:0] active;
    pmp_decode dut(.config_bytes({112'b0,3'b0,mode,11'b0}),
        .addresses({448'b0,encoded,previous}),.active_entries(active),
        .lower_bounds(lower),.upper_bounds(upper));
    // Reference uses the arithmetic NAPOT mask and full byte-address bounds.
    wire [31:0] increment=encoded+32'd1;
    wire [34:0] mask={1'b0,(encoded ^ increment),2'b11};
    wire [34:0] napot_lower={1'b0,encoded,2'b00} & ~mask;
    wire [34:0] reference_lower=mode==1 ? {1'b0,previous,2'b00} :
        mode==2 ? {1'b0,encoded,2'b00} : mode==3 ? napot_lower : 35'b0;
    wire [34:0] reference_upper=mode==1 ? {1'b0,encoded,2'b00} :
        mode==2 ? {1'b0,encoded,2'b00}+35'd4 :
        mode==3 ? napot_lower+mask+35'd1 : 35'b0;
    wire reference_active=mode!=0 && (mode!=1 || previous<encoded);
    assign equivalent=lower[35 +:35]==reference_lower &&
        upper[35 +:35]==reference_upper && active[1]==reference_active;
endmodule
