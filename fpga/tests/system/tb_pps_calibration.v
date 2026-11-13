`timescale 1ns/1ps
module tb_pps_calibration;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,pin=0,clock_good=1,tagv=0,cv=0,cw=0;
    reg[31:0] ca=0,cd=0;wire cr,ce;wire[31:0] rd,seq,errors;
    reg[63:0] tag=64'd1700000000123456;
    wire[63:0] ticks,et,ut;wire valid,ep,uv;
    reg[31:0] got,saved_seq;reg[63:0] saved_tick,previous=0;
    integer i;reg tag_on=1;
    time_sync_core #(.SYS_CLK_HZ(1000),.CHECK_CLOCK_VALID(1)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.clock_valid(clock_good),.sync_in_async(pin),
        .gnss_time_tag(tag),.gnss_time_tag_valid(tagv),.timestamp_now(ticks),.sync_valid(valid),
        .sync_seq(seq),.sync_event_pulse(ep),.sync_event_tick(et),.sync_event_gnss_tag(ut),
        .sync_event_gnss_valid(uv),.error_status(errors),.cfg_valid(cv),.cfg_write(cw),
        .cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    always @(negedge clk)begin
        if(rst && clock_good && previous!=0 && ticks<previous)$fatal(1,"time went backwards");
        previous=ticks;
    end
    task wr;input[31:0] a,d;input e;begin
        @(negedge clk);cv=1;cw=1;ca=a;cd=d;#1;
        if(!cr || ce!==e)$fatal(1,"write %h error%0d",a,ce);
        @(negedge clk);cv=0;cw=0;
    end endtask
    task rr;input[31:0] a;begin
        @(negedge clk);cv=1;cw=0;ca=a;#1;got=rd;
        if(!cr || ce)$fatal(1,"read %h",a);
        @(negedge clk);cv=0;
    end endtask
    task edge_after;input integer period;begin
        // Schedule against the last captured event: asynchronous capture delay
        // stays identical so each measured interval is exactly period ticks.
        if(seq!=0)begin wait(ticks>=et+period-2);end
        @(negedge clk);pin=1;tagv=tag_on;
        repeat(5)@(negedge clk);pin=0;tagv=0;
        repeat(2)@(negedge clk);
    end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        edge_after(0);if(uv)$fatal(1,"latest serial tag falsely attached to PPS");
        edge_after(1001);edge_after(1001);
        rr('h1044);if(got[0])$fatal(1,"qualified too early");
        edge_after(1001);rr('h1044);if(!got[0] || got[1])$fatal(1,"PPS qualify/no automatic UTC");
        rr('h1048);if(got!=1001)$fatal(1,"calibrated rate %0d",got);
        saved_seq=seq;saved_tick=et;
        rr('h104c);if(got!=saved_seq)$fatal(1,"snapshot seq");
        wr('h1070,1700000000,0);wr('h1074,seq-1,0);wr('h1078,1,1);
        wr('h1074,seq,0);wr('h1078,1,0);
        edge_after(1001);if(!uv || ut!=64'd1700000001000000)$fatal(1,"UTC advance %d %b",ut,uv);
        // Snapshot remains frozen while another PPS arrives.
        rr('h104c);if(got!=saved_seq)$fatal(1,"torn snapshot seq");
        rr('h1050);if(got!=saved_tick[31:0])$fatal(1,"torn snapshot tick");
        rr('h1044);rr('h1058);if(got!=ut[31:0])$fatal(1,"UTC snapshot");
        edge_after(100);if(uv)$fatal(1,"glitch kept UTC valid");
        rr('h1044);if(got[1:0]!=0)$fatal(1,"glitch kept calibration");
        rr('h1064);if(got!=1)$fatal(1,"rejected period counter");
        edge_after(1001);edge_after(1001);edge_after(1001);
        rr('h1044);if(!got[0] || got[1])$fatal(1,"relock must require new UTC anchor");
        wr('h1074,seq,0);wr('h1078,1,0);
        repeat(2100)@(negedge clk);rr('h1044);
        if(got[2:0]!=0 || valid || uv)$fatal(1,"PPS timeout");
        edge_after(0);edge_after(1001);edge_after(1001);edge_after(1001);
        wr('h1074,seq,0);wr('h1078,1,0);
        tag_on=0;edge_after(1001);edge_after(1001);edge_after(1001);
        rr('h1044);if(!got[0] || !got[2] || got[1] || uv)$fatal(1,"stale UART must revoke UTC while PPS remains calibrated");
        wr('h1074,seq,0);wr('h1078,1,1);
        tag_on=1;edge_after(1001);rr('h1044);
        if(!got[0] || got[1])$fatal(1,"UART recovery must not auto anchor UTC");
        wr('h1074,seq,0);wr('h1078,1,0);
        wr('h1078,2,0);rr('h1044);if(got[1])$fatal(1,"explicit anchor revoke");
        wr('h1078,1,0);
        clock_good=0;repeat(3)@(negedge clk);rr('h1044);
        if(got[2:0]!=0 || !(errors&'h20))$fatal(1,"clock fault qualification");
        saved_tick=ticks;repeat(20)@(negedge clk);if(ticks!=saved_tick)$fatal(1,"clock pause");
        clock_good=1;wr('h1004,3,0);if(ticks<saved_tick)$fatal(1,"soft reset rewound");
        $display("tb_pps_calibration_PASS qualification drift snapshot anchor_sequence UTC_advance glitch timeout clock_fault monotonic stale_GNSS explicit_revoke");$finish;
    end
    initial begin #500000;$fatal(1,"timeout");end
endmodule
