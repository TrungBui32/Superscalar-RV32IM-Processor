`timescale 1ns/1ps
module tb_machine_timer;
    reg clk=0,rst=1;
    reg [31:0] addr_pipe0=0,addr_pipe1=0,wdata_pipe0=0,wdata_pipe1=0;
    reg [3:0] wstrb_pipe0=0,wstrb_pipe1=0;
    wire [31:0] rdata_pipe0,rdata_pipe1;
    wire hit_pipe0,hit_pipe1,irq_software,irq_timer;
    wire [63:0] time_value;
    machine_timer dut(.*);
    always #5 clk=~clk;
    task write_word(input [31:0] addr,value);
        begin @(negedge clk);addr_pipe0=addr;wdata_pipe0=value;wstrb_pipe0=15;
        @(negedge clk);wstrb_pipe0=0;end
    endtask
    initial begin
        @(negedge clk);rst=0;
        if(irq_timer || irq_software)$fatal(1,"reset IRQ");
        write_word('h02000000,1);if(!irq_software)$fatal(1,"software set");
        write_word('h02000000,0);if(irq_software)$fatal(1,"software clear");
        // Simultaneous writes to both halves must merge.
        @(negedge clk);addr_pipe0='h02004000;addr_pipe1='h02004004;
        wdata_pipe0=20;wdata_pipe1=0;wstrb_pipe0=15;wstrb_pipe1=15;
        @(negedge clk);wstrb_pipe0=0;wstrb_pipe1=0;
        if(dut.mtimecmp!==20)$fatal(1,"dual-port compare write");
        wait(time_value>=20);#1;if(!irq_timer)$fatal(1,"timer compare");
        write_word('h02004004,32'hffffffff);if(irq_timer)$fatal(1,"timer clear");
        @(negedge clk);addr_pipe0='h02004000;wdata_pipe0='h0000aa00;wstrb_pipe0=2;
        @(negedge clk);wstrb_pipe0=0;
        if(dut.mtimecmp[15:8]!=='haa || dut.mtimecmp[7:0]!==20)$fatal(1,"byte mask");
        @(negedge clk);addr_pipe0='h0200bff8;addr_pipe1='h0200bffc;
        wdata_pipe0=32'hffffffff;wdata_pipe1='h1234;wstrb_pipe0=15;wstrb_pipe1=15;
        @(negedge clk);wstrb_pipe0=0;wstrb_pipe1=0;
        if(time_value!==64'h00001234ffffffff)$fatal(1,"time write merge");
        @(negedge clk);if(time_value!==64'h0000123500000000)$fatal(1,"time rollover");
        addr_pipe0='h0200bff8;addr_pipe1='h0200bffc;#1;
        if(!hit_pipe0 || !hit_pipe1 || rdata_pipe0!==0 || rdata_pipe1!=='h1235)$fatal(1,"time read");
        addr_pipe0='hdeadbeef;#1;if(hit_pipe0)$fatal(1,"decode");
        $display("PASS: timer MMIO, byte masks, dual-port writes, IRQs, 64-bit rollover");$finish;
    end
    initial begin #10000;$fatal(1,"timer timeout");end
endmodule
