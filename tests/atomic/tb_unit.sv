`timescale 1ns/1ps
module tb_atomic_unit;
    reg clk=0,rst=1; always #5 clk=~clk;
    reg req=0, aq=0, rl=0, take=0, grant=0, inv=0, clear=0;
    reg [4:0] op=0; reg [31:0] addr=0,operand=0;
    wire ready,valid,exception,lock,bv,br,bw,rv,rr;
    wire [31:0] result,tval,ba,bd; wire [4:0] cause;wire [3:0] bs;
    reg [31:0] mem[0:3];
    reg pending=0,bus_error=0;
    reg [31:0] response_data=0;
    integer delay_left=0,cycles=0,reads=0,writes=0,checks=0,order=0;
    integer error_kind=0;
    wire accept_bus=bv && br;
    assign br=!pending && (cycles%4!=0);
    assign rv=pending && delay_left==0;
    atomic_unit dut(.clk(clk),.rst(rst),.req_valid(req),.req_ready(ready),
        .req_funct5(op),.req_aq(aq),.req_rl(rl),.req_addr(addr),.req_operand(operand),
        .rsp_valid(valid),.rsp_ready(take),.rsp_result(result),.rsp_exception(exception),
        .rsp_cause(cause),.rsp_tval(tval),.lock_req(lock),.lock_grant(grant),
        .mem_req_valid(bv),.mem_req_ready(br),.mem_req_write(bw),.mem_req_addr(ba),
        .mem_req_wdata(bd),.mem_req_wstrb(bs),.mem_rsp_valid(rv),.mem_rsp_ready(rr),
        .mem_rsp_rdata(response_data),.mem_rsp_error(bus_error),
        .invalidate_reservation(inv),.clear_reservation(clear));
    always @(posedge clk) begin
        cycles++;
        if(cycles>3000000)$fatal(1,"unit timeout");
        if(rst)begin pending<=0;delay_left<=0;end
        else begin
            if(pending && delay_left>0)delay_left<=delay_left-1;
            if(rv && rr)pending<=0;
            if(accept_bus)begin
                if(!lock || !grant || ba[1:0]!=0)$fatal(1,"unowned/unaligned request");
                if(bw && bs!==4'b1111)$fatal(1,"non-word write");
                pending<=1;delay_left<=cycles%3+1;
                response_data<=mem[ba[3:2]];
                bus_error<=(error_kind==1 && !bw)||(error_kind==2 && bw);
                if(bw)begin
                    writes++;
                    if(error_kind!=2)mem[ba[3:2]]<=bd;
                end else reads++;
            end
        end
    end
    reg hold_bus=0,hold_rsp=0;
    reg [68:0] held_bus;reg [69:0] held_rsp;
    always @(posedge clk) if(!rst)begin
        if(hold_bus && (!bv || {bw,ba,bd,bs}!==held_bus))$fatal(1,"bus payload changed under stall");
        if(hold_rsp && (!valid || {exception,cause,result,tval}!==held_rsp))$fatal(1,"response changed under stall");
        hold_bus<=bv&&!br;held_bus<={bw,ba,bd,bs};
        hold_rsp<=valid&&!take;held_rsp<={exception,cause,result,tval};
    end else begin hold_bus<=0;hold_rsp<=0;end
    task launch(input[4:0] f,input[31:0] a,b);
        begin
            @(negedge clk);while(!ready)@(negedge clk);
            req=1;op=f;addr=a;operand=b;aq=order[1];rl=order[0];take=0;grant=0;
            @(posedge clk);#1;
            @(negedge clk);req=0;op=~f;addr=~a;operand=~b;
            // Ownership may be delayed independently of request acceptance.
            repeat(checks%3)begin @(negedge clk);if(bv)$fatal(1,"request before grant");end
            grant=1;
        end
    endtask
    task finish(input[31:0] expected,input integer fault);
        integer j;
        begin
            wait(valid);#1;
            if(exception!==(fault!=0) || (fault!=0 && cause!==fault[4:0]) ||
               (fault==0 && result!==expected))
                $fatal(1,"result=%h expected=%h exception=%b cause=%0d expected cause=%0d",result,expected,exception,cause,fault);
            for(j=0;j<checks%4;j++)@(negedge clk);
            take=1;@(posedge clk);#1;@(negedge clk);take=0;grant=0;checks++;
        end
    endtask
    function[31:0] expected_modify(input integer f,input[31:0] a,b);
        begin
            case(f)
             0:expected_modify=a+b;1:expected_modify=b;4:expected_modify=a^b;
             8:expected_modify=a|b;12:expected_modify=a&b;
             16:expected_modify=$signed(a)<$signed(b)?a:b;
             20:expected_modify=$signed(a)>$signed(b)?a:b;
             24:expected_modify=a<b?a:b;28:expected_modify=a>b?a:b;
             default:expected_modify=0;
            endcase
        end
    endfunction
    integer ops[0:8];reg[31:0] edges[0:7];reg[31:0] a,b,want,seed=32'h72159123;
    integer i,j,k,f,rb,wb;
    initial begin
        for(i=0;i<4;i++)mem[i]=0;
        ops[0]=0;ops[1]=1;ops[2]=4;ops[3]=8;ops[4]=12;ops[5]=16;ops[6]=20;ops[7]=24;ops[8]=28;
        edges[0]=0;edges[1]=1;edges[2]='hffffffff;edges[3]='h80000000;
        edges[4]='h7fffffff;edges[5]='haaaaaaaa;edges[6]='h55555555;edges[7]=2;
        repeat(4)@(negedge clk);rst=0;
        for(order=0;order<4;order++)for(f=0;f<9;f++)for(k=0;k<128;k++)begin
            if(k<64)begin a=edges[k/8];b=edges[k%8];end
            else begin seed=seed*1664525+1013904223;a=seed;seed=seed*1664525+1013904223;b=seed;end
            @(negedge clk);mem[0]=a;want=expected_modify(ops[f],a,b);rb=reads;wb=writes;
            launch(ops[f],0,b);finish(a,0);
            if(mem[0]!==want || reads!=rb+1 || writes!=wb+1)$fatal(1,"AMO write f=%0d got=%h want=%h",ops[f],mem[0],want);
        end
        // SC without LR, successful SC, failed SC consumes the reservation,
        // LR to x0 equivalently still creates a reservation (rd is core-owned).
        launch(3,0,99);finish(1,0);
        mem[0]=42;launch(2,0,0);finish(42,0);launch(3,0,43);finish(0,0);
        launch(3,0,44);finish(1,0);if(mem[0]!=43)$fatal(1,"SC replay");
        launch(2,0,0);finish(43,0);launch(3,4,55);finish(1,0);launch(3,0,44);finish(1,0);
        // A newer LR replaces the older reservation.
        mem[1]=17;launch(2,0,0);finish(43,0);launch(2,4,0);finish(17,0);
        launch(3,4,18);finish(0,0);
        // Store snoop and explicit context clear must invalidate.
        for(i=0;i<2;i++)begin
            launch(2,0,0);finish(43,0);
            @(negedge clk);if(i==0)inv=1;else clear=1;
            @(negedge clk);inv=0;clear=0;
            launch(3,0,44);finish(1,0);
        end
        // LR result held by the consumer while an external write is observed.
        launch(2,0,0);wait(valid);@(negedge clk);inv=1;@(negedge clk);inv=0;finish(43,0);
        launch(3,0,44);finish(1,0);
        // Invalidate after SC was accepted but before ownership is granted.
        launch(2,0,0);finish(43,0);
        @(negedge clk);req=1;op=3;addr=0;operand=44;grant=0;take=0;
        @(posedge clk);#1;@(negedge clk);req=0;inv=1;
        @(posedge clk);#1;@(negedge clk);inv=0;grant=1;
        finish(1,0);
        if(mem[0]!==43)$fatal(1,"SC used a stale reservation while awaiting grant");
        // Bus faults: AMO read and write failures are store/AMO access faults.
        error_kind=1;launch(0,0,1);finish(0,7);launch(2,0,0);finish(0,5);
        error_kind=2;launch(1,0,7);finish(0,7);error_kind=0;
        wb=writes;rb=reads;
        launch(2,1,0);finish(0,4);launch(3,2,0);finish(0,6);
        launch(0,3,0);finish(0,6);launch(31,0,0);finish(0,2);
        if(reads!=rb || writes!=wb)$fatal(1,"fault generated memory side effect");
        // Reset abandons an outstanding request and clears the reservation.
        launch(2,0,0);finish(43,0);launch(0,0,1);
        @(negedge clk);rst=1;repeat(2)@(negedge clk);rst=0;
        launch(3,0,99);finish(1,0);
        $display("PASS atomic unit checks=%0d reads=%0d writes=%0d",checks,reads,writes);$finish;
    end
endmodule
