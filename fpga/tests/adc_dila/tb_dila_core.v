`timescale 1ns/1ps
module tb_dila_core;
    reg clk=0;always #5 clk=~clk;
    reg [1:0] sv=0;
    reg rst_n=0,scan=0,phase_valid=1,cv=0,cw=0,run_ready=1,score=1;
    reg [31:0] ca=0,cd=0,cycle=1,live_phase=0;
    reg [63:0] tick=0;
    reg [193:0] tag=0;
    wire [1:0] sr,cr,ce,mv,ms,ml;
    reg [1:0] mr=0;
    wire [31:0] rd[0:1],md[0:1],mc[0:1],mf[0:1];
    wire [63:0] mt[0:1];wire [3:0] mk[0:1];wire [15:0] sid[0:1],mid[0:1];
    integer head[0:1],pt[0:1],wn[0:1],frag[0:1],cyc[0:1],seen[0:1];
    reg [197:0] held[0:1];reg stalled[0:1];
    integer j,n,c,words,fraglen,total;reg [31:0] exp,rv;
    reg [31:0] rnd=32'h12345678;
    always @(posedge clk)if(rst_n)begin tick<=tick+1;live_phase<=live_phase+32'h234567;end
    always @(negedge clk)begin rnd={rnd[30:0],rnd[31]^rnd[21]^rnd[1]^rnd[0]};mr=run_ready?rnd[1:0]:0;end
    genvar v;
    generate for(v=0;v<2;v=v+1)begin:cores
        dila_core #(.USE_CAPTURE_TAGS(1),.OUTPUT_FORMAT(v),.MAX_POINTS(1024),.SOURCE_ID(16'h30+v),.BASE_ADDR(32'h5000+v*256)) dut(
            .sys_clk(clk),.rst_sys_n(rst_n),.sample_valid(sv[v]),.sample_ready(sr[v]),.sample_data(32'd131072),.sample_flags(8'd0),
            .wms_scan_start(scan),.wms_cycle_id(cycle),.wms_sine_phase(live_phase),.wms_phase_valid(phase_valid),.timestamp_now(tick),.time_sync_valid(1'b1),
            .capture_tag(tag),.input_sample_rate_hz(32'd1000000),.expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),
            .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),.cfg_ready(cr[v]),.cfg_rdata(rd[v]),.cfg_error(ce[v]),
            .m_valid(mv[v]),.m_ready(mr[v]),.m_data(md[v]),.m_keep(mk[v]),.m_sof(ms[v]),.m_last(ml[v]),
            .m_source_id(sid[v]),.m_msg_id(mid[v]),.m_timestamp(mt[v]),.m_cycle_id(mc[v]),.m_flags(mf[v]));
    end endgenerate
    task write_reg;
        input [31:0] a,d;input bad;integer target;
        begin
            target=(a-32'h5000)/256;
            @(negedge clk);ca=a;cd=d;cv=1;cw=1;@(posedge clk);
            if(!cr[target] || ce[target]!==bad || cr[1-target] || ce[1-target])$fatal(1,"DILA cfg a=%h",a);
            @(negedge clk);cv=0;cw=0;
        end
    endtask
    task read_reg;
        input [31:0] a;output [31:0] d;integer target;
        begin target=(a-32'h5000)/256;@(negedge clk);ca=a;cv=1;cw=0;@(posedge clk);if(!cr[target]||ce[target])$fatal(1,"DILA read");d=rd[target];@(negedge clk);cv=0;end
    endtask
    task sample;
        input integer cvalue,index;
        reg [63:0] ct,st;reg [31:0] ci;reg [1:0] accepted;
        begin
            ct=cvalue*100000;st=ct+index*100;ci=cvalue;
            @(negedge clk);tag={2'b11,ct,st,32'd0,ci};sv=3;
            while(sv!=0)begin
                @(posedge clk);accepted=sv&sr;
                @(negedge clk);sv=sv&~accepted;
            end
            repeat(6)@(negedge clk);
        end
    endtask
    always @(posedge clk)if(rst_n && score)begin
        for(j=0;j<2;j=j+1)begin
            if(stalled[j] && (!mv[j] || held[j]!=={md[j],mk[j],ms[j],ml[j],sid[j],mid[j],mt[j],mc[j],mf[j]}))$fatal(1,"Core output stability");
            stalled[j]=mv[j]&&!mr[j];held[j]={md[j],mk[j],ms[j],ml[j],sid[j],mid[j],mt[j],mc[j],mf[j]};
            if(mv[j]&&mr[j])begin
                words=j==0?2:4;total=cyc[j]==3?10:600;fraglen=total-frag[j]*32<32?total-frag[j]*32:32;
                if(mc[j]!=cyc[j] || mt[j]!=cyc[j]*100000 || sid[j]!=16'h30+j || mid[j]!=16'h1001 || mk[j]!=15)$fatal(1,"Core cycle metadata");
                if(cyc[j]==3 && !mf[j][5])$fatal(1,"STOP did not mark partial");
                if(head[j]<8)begin
                    case(head[j])
                        0:exp=(j<<16)|2;1:exp=100000;2:exp=total;3:exp=(((total+31)/32)<<16)|frag[j];
                        4:exp=frag[j]*32;5:exp=fraglen;6:exp=words*4;default:exp=0;
                    endcase
                    if(md[j]!==exp || ms[j]!=(head[j]==0) || ml[j])$fatal(1,"Core header j=%d c=%d h=%d got=%h expected=%h",j,cyc[j],head[j],md[j],exp);
                    head[j]=head[j]+1;
                end else begin
                    if(j==0)exp=131071;
                    else if(wn[j]==0)exp=cyc[j]==1?131071:0;
                    else if(wn[j]==1)exp=cyc[j]==1?0:131071;
                    else exp=wn[j]==2?131071:0;
                    if(md[j]!==exp || ms[j])$fatal(1,"Core sample j=%d c=%d pt=%d word=%d got=%h expected=%h",j,cyc[j],pt[j],wn[j],md[j],exp);
                    if(ml[j]!==((pt[j]+1==frag[j]*32+fraglen)&&(wn[j]==words-1)))$fatal(1,"Core LAST");
                    if(wn[j]==words-1)begin
                        wn[j]=0;pt[j]=pt[j]+1;seen[j]=seen[j]+1;
                        if(pt[j]==total)begin pt[j]=0;frag[j]=0;head[j]=0;cyc[j]=cyc[j]+1;end
                        else if(pt[j]==frag[j]*32+fraglen)begin frag[j]=frag[j]+1;head[j]=0;end
                    end else wn[j]=wn[j]+1;
                end
            end
        end
    end
    initial begin #4000000;$fatal(1,"Core watchdog seen=%0d/%0d",seen[0],seen[1]);end
    initial begin
        for(j=0;j<2;j=j+1)begin head[j]=0;pt[j]=0;wn[j]=0;frag[j]=0;cyc[j]=1;seen[j]=0;stalled[j]=0;held[j]=0;end
        repeat(8)@(negedge clk);rst_n=1;
        write_reg(32'h501c,200000,1);write_reg(32'h500c,32'hffffffff,0);
        for(c=0;c<2;c=c+1)begin
            write_reg(32'h5020+c*256,c==0?7:5,0);write_reg(32'h501c+c*256,100000,0);write_reg(32'h5040+c*256,32,0);write_reg(32'h5004+c*256,4,0);
        end
        repeat(100)@(negedge clk);
        read_reg(32'h504c,rv);if(rv!=100000)$fatal(1,"Actual rate");
        write_reg(32'h5004,1,0);write_reg(32'h5104,1,0);
        @(negedge clk);scan=1;@(negedge clk);scan=0;
        for(n=0;n<6000;n=n+1)begin
            sample(1,n);
            if(n==1000)begin write_reg(32'h5114,32'h40000000,0);write_reg(32'h5104,5,0);write_reg(32'h5114,32'h80000000,0);end
        end
        if(cores[1].dut.phase1_active!=0)$fatal(1,"Commit applied within old tagged cycle");
        @(negedge clk);cycle=2;scan=1;@(negedge clk);scan=0;
        for(n=0;n<6000;n=n+1)sample(2,n);
        @(negedge clk);cycle=3;scan=1;@(negedge clk);scan=0;
        for(n=0;n<100;n=n+1)sample(3,n);
        @(negedge clk);phase_valid=0;
        write_reg(32'h5004,0,0);write_reg(32'h5104,0,0);
        wait(seen[0]==1210 && seen[1]==1210);
        score=0;write_reg(32'h5004,2,0);repeat(5)@(negedge clk);read_reg(32'h5038,rv);if(rv!=0)$fatal(1,"Core soft reset counter");
        $display("DILA_CORE_PASS dual_independent shadow_commit tagged_phase fragments stop_partial=PASS points=2420");$finish;
    end
endmodule
