`timescale 1ns/1ps
module tb_access_map;
    reg [31:0] pc=32'h400000,a0=0,a1=0;
    reg [2:0] size0=4,size1=4;
    reg [1:0] writes=0;
    wire [1:0] ff,df;
    integer checks=0;
    soc_access_check dut(pc,a0,a1,size0,size1,writes,ff,df);
    task ck(input [31:0] addr,input [2:0] size,input wr,input ok);
        begin a0=addr;a1=addr;size0=size;size1=size;writes={2{wr}};#1;
            if(df!=={2{!ok}})$fatal(1,"map addr=%h size=%0d wr=%0d fault=%b",addr,size,wr,df);
            checks++;
        end
    endtask
    initial begin
        #1;if(ff!==0)$fatal(1,"valid fetch");
        pc='h407ffc;#1;if(ff!==2)$fatal(1,"ROM last pair");
        pc='h408000;#1;if(ff!==3)$fatal(1,"ROM overflow");
        pc='hffff_fffc;#1;if(ff!==3)$fatal(1,"ROM wrap");
        ck('h10010000,4,0,1);ck('h10013ffc,4,1,1);
        ck('h10013fff,1,1,1);ck('h10013fff,2,0,0);
        ck('h10014000,4,0,0);ck('h1001ffff,1,1,0);
        ck('hffff0008,4,0,1);ck('hffff0008,4,1,0);
        ck('hffff000c,1,1,1);ck('hffff000c,4,0,0);
        ck('hffff00a0,4,0,1);ck('hffff00a0,4,1,0);
        ck('hffff0000,4,0,0);ck('hffff0020,4,1,0);
        ck('h02000000,4,1,1);ck('h02000003,1,1,1);
        ck('h02000003,2,0,0);ck('h02004000,4,1,1);
        ck('h02004004,4,0,1);ck('h02004008,4,0,0);
        ck('h0200bff8,4,0,1);ck('h0200bffc,4,1,1);
        ck('h0200bfff,2,0,0);ck('hffffffff,4,1,0);
        ck('h10010000,0,0,0);ck('h10010000,3,0,0);
        $display("PASS access map %0d data checks plus fetch boundaries",checks);$finish;
    end
endmodule
