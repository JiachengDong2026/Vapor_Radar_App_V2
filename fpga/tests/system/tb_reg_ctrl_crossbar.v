`timescale 1ns/1ps
module tb_reg_ctrl_crossbar;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,v=0,w=0;reg[31:0]a=0,d=0;reg[3:0]st=15;
    wire ready,err;wire[31:0]q,sa,sd;wire[3:0]ss,code;wire sw;
    wire[20:0]sv;reg[20:0]sr=0,se=0;reg[671:0]sq=0;reg[83:0]sc=0;wire[31:0]tc;
    integer i,commits=0,acks=0,limit;
    reg[167:0]pages=168'h807067666564636261605150414031302120100100;
    reg_ctrl_crossbar #(.TIMEOUT_CYCLES(8))dut(clk,rst,v,w,a,d,st,ready,err,q,sv,sw,sa,sd,ss,sr,se,sq,tc,sc,code);
    always @(posedge clk)if(rst)begin
        if((sv & sr)!=0 && sw)commits=commits+1;
        if(v && ready)acks=acks+1;
        if(ready && sv!=0)$fatal(1,"response reissues slave request");
    end
    task transfer;
        input[31:0]addr,data;
        input wr;
        input[3:0]expected_code;
        input[31:0]expected_data;
        begin
            @(negedge clk);v=1;w=wr;a=addr;d=data;#1;
            if(ready || sv!=0)$fatal(1,"request capture acknowledged early");
            limit=0;
            while(!ready && limit<15)begin @(negedge clk);limit=limit+1;end
            if(!ready || err!==(expected_code!=0) || code!==expected_code || q!==expected_data)
                $fatal(1,"response addr=%h err=%b code=%d q=%h expected=%d/%h",addr,err,code,q,expected_code,expected_data);
            @(negedge clk);v=0;#1;
            if(ready || sv!=0)$fatal(1,"idle response");
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=1;sr={21{1'b1}};
        for(i=0;i<21;i=i+1)begin
            sq[i*32+:32]=32'h1000+i;
            transfer({16'd0,pages[i*8+:8],8'h10},i,1,0,32'h1000+i);
        end
        if(commits!=21)$fatal(1,"page write side effects %d",commits);
        transfer('h12010,0,1,5,0);transfer('h2001,0,1,5,0);transfer('h9000,0,1,5,0);
        if(commits!=21)$fatal(1,"invalid address committed");
        se=21'd1<<3;sc[15:12]=7;
        transfer('h2000,0,0,7,'h1003);sc[15:12]=0;
        transfer('h2000,0,0,15,'h1003);se=0;
        // Request fields are captured; stored response survives slave changes.
        @(negedge clk);v=1;w=1;a='h2000;d='h12345678;st=5;sr=0;
        @(negedge clk);a='h3000;d=0;w=0;st=0;#1;
        if(sv!==(21'd1<<3) || sa!='h2000 || sd!='h12345678 || !sw || ss!=5 || ready)
            $fatal(1,"request not held");
        sr=21'd1<<3;
        @(negedge clk);sr=0;sq[127:96]='hdeadbeef;se={21{1'b1}};sc={21{4'd8}};#1;
        if(!ready || err || code || q!='h1003 || sv)$fatal(1,"response not retained");
        @(negedge clk);v=0;se=0;sc=0;
        if(commits!=22)$fatal(1,"write repeated during response");
        // Cancellation before any sampling edge does not create a transaction.
        @(negedge clk);v=1;a='h2000;w=1;#1;v=0;
        @(negedge clk);#1;if(sv || ready)$fatal(1,"pre-capture cancel");
        // Cancel a waiting request, then supply a late slave ready.
        @(negedge clk);v=1;
        @(negedge clk);v=0;sr={21{1'b1}};#1;if(sv || ready)$fatal(1,"issue cancel");
        repeat(2)@(negedge clk);
        if(commits!=22 || tc!=0)$fatal(1,"cancel caused side effect/timeout");
        // Cancel after slave commit: no rollback, no stale upstream ACK.
        @(negedge clk);v=1;
        @(negedge clk);
        @(negedge clk);v=0;#1;if(ready || sv)$fatal(1,"cancel leaked response");
        @(negedge clk);if(commits!=23)$fatal(1,"committed cancel rollback/duplicate");
        // At the timeout boundary slave_valid is suppressed even for late ready.
        @(negedge clk);v=1;sr=0;
        @(negedge clk);repeat(7)@(negedge clk);sr={21{1'b1}};#1;
        if(sv || ready)$fatal(1,"timeout deadline allowed commit/early ACK");
        @(negedge clk);#1;if(!ready || !err || code!=9 || tc!=1)$fatal(1,"timeout response");
        @(negedge clk);v=0;
        if(commits!=23)$fatal(1,"late-ready write committed");
        transfer('h2000,0,0,0,'hdeadbeef);
        // Continuous valid with address update immediately after each ACK.
        @(negedge clk);v=1;w=1;a='h2000;d=1;
        wait(ready);@(negedge clk);@(negedge clk);a='h3000;d=2;
        wait(ready);@(negedge clk);@(negedge clk);v=0;
        if(commits!=25 || tc!=1)$fatal(1,"continuous valid duplicate/lost request");
        // Reset aborts a pending transaction and clears its response/counter.
        @(negedge clk);v=1;sr=0;
        @(negedge clk);rst=0;
        @(negedge clk);v=0;rst=1;#1;
        if(sv || ready || tc)$fatal(1,"reset abort");
        $display("tb_reg_ctrl_crossbar_PASS pages=21 commits=%0d acks=%0d cancellation timeout_late_ready held_request_response continuous_valid",commits,acks);$finish;
    end
    initial begin #100000;$fatal(1,"watchdog");end
endmodule
