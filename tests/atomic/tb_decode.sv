`timescale 1ns/1ps
module tb_atomic_decode;
    reg [31:0] insn=0;
    wire illegal, atomic_valid, regwrite, mr, mt, u1, u2;
    wire [2:0] mw;
    integer f,w,o,r,n=0; reg expected;
    decode_unit dut(.Instruction(insn),.Opcode(insn[6:0]),.Funct3(insn[14:12]),
        .Funct7(insn[31:25]),.Rs1(insn[19:15]),.illegal_instruction(illegal),
        .atomic_valid(atomic_valid),.RegWrite(regwrite),.MemRead(mr),.MemWrite(mw),
        .MemtoReg(mt),.uses_rs1(u1),.uses_rs2(u2));
    initial begin
        for(f=0;f<32;f++) for(w=0;w<8;w++) for(o=0;o<4;o++) for(r=0;r<2;r++)begin
            insn=(f<<27)|(o<<25)|(r<<20)|(7<<15)|(w<<12)|(9<<7)|7'h2f; #1;
            expected=w==2 && (f==0 || f==1 || (f==2 && r==0) || f==3 || f==4 ||
                f==8 || f==12 || f==16 || f==20 || f==24 || f==28);
            if(atomic_valid!==expected || illegal!==!expected || regwrite!==expected ||
               mt!==expected || u1!==expected || u2!==(expected && f!=2) || mr || mw)
                $fatal(1,"decode insn=%h legal=%b atomic=%b",insn,!illegal,atomic_valid);
            n++;
        end
        $display("PASS atomic decode %0d encodings",n);$finish;
    end
endmodule
