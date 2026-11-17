`timescale 1ns/1ps
module tb_muldiv;
parameter W=32;
reg ready=0;
reg clk=0,rst=1,start=0,su=0;reg[1:0]op=0;reg[W-1:0]a=0,b=0;wire[W-1:0]lo,hi;wire busy;
always #5 clk=~clk;
muldiv_unit #(.width(W)) dut(
    .CLK(clk), .RESET(rst), .Start(start), .MCycleOp(op), .is_mulsu(su),
    .Operand1(a), .Operand2(b), .Result1(lo), .Result2(hi),
    .Busy(busy), .ResultReady(ready)
);
integer hold_cycles, h;
integer k,m,x,y,checks=0,latency,seed=32'h671923ab;
reg[31:0]random_a,random_b;reg[W-1:0]edgev[0:7];
function[63:0] next_random(input[31:0]v);next_random=(v*32'd1664525+32'd1013904223)&64'hffffffff;endfunction
reg signed[63:0]sa,sb,prod;reg[2*W-1:0]want;reg[W-1:0]q,r;
task check(input[W-1:0]ax,bx,input integer mode);
 begin
 @(negedge clk);ready=0;a=ax;b=bx;su=mode==4;op=mode==4?1:mode;start=1;
 #1;
 if(!busy)$fatal(1,"Busy did not assert with Start");
 sa=$signed(ax);sb=$signed(bx);
 case(mode)
  0:begin prod=sa*sb;want=prod;end
  1:want=$unsigned(ax)*$unsigned(bx);
  4:begin sb={1'b0,bx};prod=sa*sb;want=prod;end
  2:begin
   if(bx==0)begin q={W{1'b1}};r=ax;end
   else begin q=sa/sb;r=sa%sb;end
   want={r,q};
  end
  3:begin if(bx==0)begin q={W{1'b1}};r=ax;end else begin q=$unsigned(ax)/$unsigned(bx);r=$unsigned(ax)%$unsigned(bx);end want={r,q};end
 endcase
 @(posedge clk);#1;@(negedge clk);latency=0;
 // The requester may change its operands and opcode after acceptance.
 a=~ax;b=~bx;op=~op;su=~su;
 while(busy && latency<90)begin @(posedge clk);#1;latency++;end
 if(busy || {hi,lo}!==want)$fatal(1,"W=%0d mode=%0d a=%h b=%h got=%h want=%h latency=%0d",W,mode,ax,bx,{hi,lo},want,latency);
 if (mode==0 || mode==1 || mode==4) begin
  if(latency!=2)$fatal(1,"multiply latency %0d",latency);
 end else if (bx==0 || ax==0 || bx==1 || (mode==2 && bx=={W{1'b1}})) begin
  if(latency!=1)$fatal(1,"fast division latency %0d",latency);
 end else if(latency!=(W+3)/4+1)$fatal(1,"division latency %0d",latency);
 // Keep Start high and withhold consumption across completion. Nothing may replay.
 hold_cycles=checks%4;
 for(h=0;h<hold_cycles;h++)begin
  @(posedge clk);#1;
  if(busy || {hi,lo}!==want)$fatal(1,"response changed under backpressure");
 end
 checks++;
 @(negedge clk);ready=1;@(posedge clk);#1;
 @(negedge clk);start=0;ready=0;
 end
endtask
// Reset must abandon in-flight and completed requests without a stale response.
task reset_request(input integer delay_cycles, input [1:0] mode);
 begin
  @(negedge clk);start=1;ready=0;op=mode;su=0;a=5;b=3;
  @(posedge clk);#1;
  repeat(delay_cycles)@(negedge clk);
  rst=1;start=0;
  @(posedge clk);#1;
  if(busy || lo!==0 || hi!==0)$fatal(1,"reset did not discard response");
  @(negedge clk);rst=0;
  @(posedge clk);#1;
  if(busy)$fatal(1,"request restarted after reset");
 end
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 reset_request(1,0);reset_request(2,0);reset_request(3,0);
 reset_request(1,2);reset_request(3,2);reset_request(12,2);
 edgev[0]=0;edgev[1]=1;edgev[2]={W{1'b1}};edgev[3]={1'b1,{W-1{1'b0}}};edgev[4]={1'b0,{W-1{1'b1}}};edgev[5]=2;edgev[6]=3;edgev[7]=5;
 for(m=0;m<5;m++)for(x=0;x<8;x++)for(y=0;y<8;y++)check(edgev[x],edgev[y],m);
 if(W<=8)begin for(m=0;m<5;m++)for(x=0;x<(1<<W);x++)for(y=0;y<(1<<W);y++)check(x,y,m);end
 else begin for(k=0;k<4000;k++)begin seed=next_random(seed);random_a=seed;seed=next_random(seed);random_b=seed;for(m=0;m<5;m++)check(random_a,random_b,m);end end
 $display("PASS W=%0d checks=%0d last accept-to-result=%0d cycles",W,checks,latency);$finish;
end
endmodule
