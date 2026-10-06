`timescale 1ns/1ps
module tb_cfg_crossbar_pipeline;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;reg[2:0]v=0;reg[95:0]a=0,d=0;
    wire[2:0]ready,err;wire[95:0]q;wire[11:0]codes;
    wire bv,bw,br,be;wire[31:0]ba,bd,bq;wire[3:0]bs,bc;
    wire[1:0]sv;wire sw;wire[31:0]sa,sd;wire[3:0]ss;wire[31:0]tc;
    reg allow=0;wire[1:0]sr={allow,allow};
    wire[63:0]sq={sd^32'hb0000000,sd^32'ha0000000};
    integer commits=0,acks=0,phase=0,i,cycle=0;
    integer sent[0:2];integer committed[0:2];
    reg[31:0]expected;
    cfg_bus_arbiter arb(.sys_clk(clk),.rst_sys_n(rst),.s_valid(v),.s_write(3'b111),.s_addr(a),.s_wdata(d),.s_wstrb(12'hfff),
        .s_ready(ready),.s_error(err),.s_rdata(q),.s_error_code(codes),.m_valid(bv),.m_write(bw),.m_addr(ba),.m_wdata(bd),.m_wstrb(bs),
        .m_ready(br),.m_error(be),.m_rdata(bq),.m_error_code(bc));
    reg_ctrl_crossbar #(.N(2),.PAGE_MAP(16'h3020),.TIMEOUT_CYCLES(8)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.cfg_valid(bv),.cfg_write(bw),.cfg_addr(ba),.cfg_wdata(bd),.cfg_wstrb(bs),
        .cfg_ready(br),.cfg_error(be),.cfg_rdata(bq),.cfg_error_code(bc),.slave_valid(sv),.slave_write(sw),.slave_addr(sa),.slave_wdata(sd),
        .slave_wstrb(ss),.slave_ready(sr),.slave_error(2'b00),.slave_rdata(sq),.slave_error_code(8'd0),.timeout_count(tc));
    always @(posedge clk)if(rst)begin
        cycle=cycle+1;
        if((sv&sr)!=0)begin
            commits=commits+1;
            if(phase==4)begin
                if(sd[31:16]>2 || sd[15:0]!=committed[sd[31:16]])$fatal(1,"duplicate/stale side effect %h",sd);
                committed[sd[31:16]]=committed[sd[31:16]]+1;
            end
        end
        for(i=0;i<3;i=i+1)if(ready[i])begin
            if(!v[i])$fatal(1,"ACK canceled master %d",i);
            acks=acks+1;
            if(phase==1 || phase==2 || phase==3)begin
                if(i!=1 || err[i] || q[i*32+:32]!=(32'hb0000000^32'h00010000))$fatal(1,"stale response after cancellation");
                v[i]<=0;
            end else if(phase==4)begin
                expected=d[i*32+:32] ^ (a[i*32+:32]=='h2000 ? 32'ha0000000:32'hb0000000);
                if(err[i] || codes[i*4+:4]!=0 || q[i*32+:32]!==expected)$fatal(1,"response routing master=%d q=%h expected=%h",i,q[i*32+:32],expected);
                sent[i]=sent[i]+1;
                if(sent[i]==16)v[i]<=0;
                else begin
                    d[i*32+:32]<=(i<<16)|sent[i];
                    a[i*32+:32]<=sent[i]%2 ? 'h3000:'h2000;
                end
            end
        end
    end
    task reset_bus;
        begin
            @(negedge clk);rst=0;v=0;allow=0;
            repeat(2)@(negedge clk);rst=1;
            a={32'h2000,32'h3000,32'h2000};d={32'h20000,32'h10000,32'h0};
        end
    endtask
    initial begin
        for(i=0;i<3;i=i+1)begin sent[i]=0;committed[i]=0;end
        reset_bus();phase=1;
        // Master 2 withdraws while still queued, then master 0 cancels ISSUE.
        @(negedge clk);v=3'b111;
        wait(sv[0]);@(negedge clk);v[2]=0;v[0]=0;allow=1;
        wait(v==0);repeat(3)@(negedge clk);
        if(commits!=1 || acks!=1 || tc)$fatal(1,"queued/ISSUE cancellation");
        reset_bus();phase=2;
        // Cancel master 0 after its slave commit, before upstream handshake.
        @(negedge clk);v=3'b011;allow=1;
        wait(br);@(negedge clk);v[0]=0;
        wait(v==0);repeat(3)@(negedge clk);
        if(commits!=3 || acks!=2)$fatal(1,"post-commit cancellation");
        reset_bus();phase=3;
        // Master timeout withdraws at the crossbar deadline; late-ready cannot commit.
        @(negedge clk);v=3'b011;
        wait(sv[0]);repeat(7)@(negedge clk);
        @(negedge clk);v[0]=0;allow=1;
        wait(v==0);repeat(3)@(negedge clk);
        if(commits!=4 || acks!=3)$fatal(1,"deadline cancellation");
        reset_bus();phase=4;
        @(negedge clk);v=3'b111;allow=1;
        // All masters keep valid high across 16 changing requests each.
        wait(v==0);repeat(3)@(negedge clk);
        if(commits!=52 || acks!=51)$fatal(1,"count commits=%d acks=%d",commits,acks);
        for(i=0;i<3;i=i+1)if(sent[i]!=16 || committed[i]!=16)$fatal(1,"lost master=%d",i);
        $display("tb_cfg_crossbar_pipeline_PASS competing=48 commits=%0d acks=%0d queued_issue_postcommit_deadline_cancellation",commits,acks);$finish;
    end
    initial begin #100000;$fatal(1,"watchdog phase=%d v=%b",phase,v);end
endmodule
