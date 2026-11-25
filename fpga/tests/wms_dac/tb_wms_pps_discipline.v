`timescale 1ns/1ps
// Accelerated 100 kHz system clock: 100 Hz sweeps, 10 kHz DAC updates.
module tb_wms_pps_discipline;
    reg clk=0; always #5 clk=~clk;
    reg rst=0,pps=0,qualified=0;
    reg [1:0] enabled=0;
    reg [63:0] tick=0,stamp=0;
    reg [31:0] seq=0,rv;
    always @(posedge clk) if(rst)tick<=tick+1;
    wire cv,cw;wire [31:0] ca,cd,r0,r1;wire [3:0] cs;
    wire [1:0] ack,err,disc,ready,scan,one,sv,win,first;
    cfg_test_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(|ack),.cfg_rdata(ack[0]?r0:r1),.cfg_error(|err));
    wire [31:0] step[0:1],phase[0:1];
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:channels
        reg applied=0,applied_window=0;
        always @(posedge clk)begin applied<=sv[g];if(sv[g])applied_window<=win[g];end
        wire [31:0] rd;
        if(g==0)assign r0=rd;else assign r1=rd;
        wms_wavegen #(.SYS_CLK_HZ(100000),.BASE_ADDR('h2000+256*g)) w(
            .sys_clk(clk),.rst_sys_n(rst),.enable(enabled[g]),.timestamp_now(tick),.time_sync_valid(qualified),
            .transport_ready(1'b1),.max_update_hz(32'd10000),.pps_pulse(pps),.pps_qualified(qualified),.pps_tick(stamp),.pps_seq(seq),
            .disciplined(disc[g]),.lane_ready(ready[g]),.peer_ready(!disc[1-g] || ready[1-g]),
            .sample_applied(applied),.applied_window(applied_window),.sample_window(win[g]),.sample_first(first[g]),
            .pps_mode(one[g]),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(ack[g]),.cfg_rdata(rd),.cfg_error(err[g]),
            .dac_sample_valid(sv[g]),.dac_sample_ready(1'b1),.scan_start(scan[g]));
        assign step[g]=w.disciplined_step;assign phase[g]=w.saw_phase;
    end endgenerate
    integer scans=0,last_scan=0,spacing,last_write=0,writes=0;
    reg [31:0] old_phase;reg check_phase=0;
    always @(negedge clk)if(rst)begin
        if(scan!=0 && scan!=3)$fatal(1,"start skew");
        if(|one)$fatal(1,"unexpected burst mode for DLIA");
        if(scans>0 && enabled==3)begin
            if(sv[0]!==sv[1] || phase[0]!==phase[1])$fatal(1,"lanes diverged");
            if(check_phase && phase[0]!=old_phase)begin
                if((phase[0]-old_phase)<41500000 || (phase[0]-old_phase)>44500000)$fatal(1,"DDS jump or stalled phase");
                if((phase[0]<old_phase)!==scan[0])$fatal(1,"scan marker not at natural wrap");
            end
        end
        old_phase=phase[0];check_phase=scans>0;
        if(sv[0] && win[0])begin
            if(writes && tick-last_write!=10)$fatal(1,"DAC sample cadence");
            writes=writes+1;last_write=tick;
        end
        if(scan==3)begin
            spacing=tick-last_scan;
            if(scans && (spacing<980 || spacing>1020))$fatal(1,"truncated or stretched cycle %d",spacing);
            last_scan=tick;scans=scans+1;
        end
    end
    task pulse;input integer delay_ticks;input good;
        begin repeat(delay_ticks-1)@(negedge clk);seq=seq+1;stamp=tick;qualified=good;pps=1;@(negedge clk);pps=0;end
    endtask
    integer ch,i,old_count;reg [31:0] hold_step;
    initial begin
        repeat(8)@(negedge clk);rst=1;
        for(ch=0;ch<2;ch=ch+1)begin
            bus.write32('h2010+ch*256,100000);bus.write32('h201c+ch*256,1000000);
            bus.write32('h2028+ch*256,10000);bus.write32('h2004+ch*256,4);
            repeat(30)@(negedge clk);bus.write32('h204c+ch*256,2);
            bus.read32('h208c+ch*256,rv);if(rv!==32'h50504301)$fatal(1,"capability");
            bus.write32('h2004+ch*256,1);
        end
        enabled=1;pulse(150,1);if(scans)$fatal(1,"peer not ready");
        enabled=3;pulse(150,0);if(scans)$fatal(1,"unqualified PPS");
        pulse(50,1);repeat(4)pulse(100300,1);
        for(i=0;i<3;i=i+1)begin
            old_count=scans;pulse(100300,1);
            if(scans-old_count!=100 || (tick-last_scan>25 && tick-last_scan<975))$fatal(1,"100 Hz phase lock %d %d",scans-old_count,tick-last_scan);
        end
        repeat(100)@(negedge clk);hold_step=step[0];qualified=0;old_count=scans;pulse(200800,0);
        if(scans-old_count<199 || step[0]!=hold_step)$fatal(1,"holdover");
        pulse(99500,1);pulse(99500,1);pulse(99500,1);pulse(99500,1);
        if(step[0]<=hold_step)$fatal(1,"opposite clock drift not corrected");
        bus.read32('h2090,rv);if(rv!=3)$fatal(1,"tracking status");
        bus.expect_error(1,'h204c,0);bus.expect_error(1,'h2004,5);
        $display("WMS_PPS_DISCIPLINE_PASS complete cycles=%d DAC writes=%d",scans,writes);$finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule
