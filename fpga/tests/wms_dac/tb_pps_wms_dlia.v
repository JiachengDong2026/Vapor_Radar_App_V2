`timescale 1ns/1ps
// Full DAC SPI models + delayed conversion tags + two independent DLIA pipelines.
module tb_pps_wms_dlia;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,pps=0,qualified=1,host_ready=1;
    reg [63:0] tick=0,pps_tick=0;
    reg [31:0] pps_seq=0;
    always @(posedge clk)if(rst)tick<=tick+1;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire [2:0] ready,error;wire [31:0] rdata[0:2];
    assign cr=|ready;assign ce=|error;assign rd=rdata[0]|rdata[1]|rdata[2];
    cfg_test_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    wire [1:0] scan,pv,pm,aborted,tr,drained,ds,ss,sd,dr,dc,dl,mv,ml,ms,sr;
    wire [63:0] cycle,phase;wire [31:0] md[0:1],mc[0:1],mf[0:1];wire [63:0] mt[0:1];
    wire [19:0] code[0:1];
    wms_dac_dual wms(.sys_clk(clk),.rst_sys_n(rst),.enable(2'b11),.timestamp_now(tick),.time_sync_valid(1'b1),
        .pps_pulse(pps),.pps_qualified(qualified),.pps_tick(pps_tick),.pps_seq(pps_seq),.dlia_trigger_ready(tr),.dlia_scan_drained(drained),.pps_mode(pm),.scan_aborted(aborted),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(ready[0]),.cfg_rdata(rdata[0]),.cfg_error(error[0]),
        .scan_start(scan),.phase_valid(pv),.cycle_id(cycle),.sine_phase(phase),
        .dac_sclk(ds),.dac_sync_n(ss),.dac_sdin(sd),.dac_sdo(2'b00),.dac_rst_n(dr),.dac_clr_n(dc),.dac_ldac_n(dl));
    reg [63:0] start_tick[0:1];
    reg [193:0] cap[0:1];reg [4:0] delay_count=0;reg sv=0;
    integer samples[0:1],frames[0:1],starts[0:1],idx[0:1],writes[0:1];
    reg [31:0] golden[0:127];reg [31:0] rv;
    reg compare_frames=1,expect_abort=0,expect_fault=0;
    reg [31:0] input_rate=1000000;
    reg [959:0] unity_bank;integer w;
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:ch
        ad5791_model model(.sclk(ds[g]),.sync_n(ss[g]),.sdin(sd[g]),.rst_n(dr[g]),.clr_n(dc[g]),.ldac_n(dl[g]),.code(code[g]));
        dila_core #(.USE_CAPTURE_TAGS(1),.MAX_POINTS(512),.SOURCE_ID(16'h30+g),.BASE_ADDR(32'h5000+g*256)) core(
            .sys_clk(clk),.rst_sys_n(rst),.sample_valid(sv),.sample_ready(sr[g]),.sample_data(32'd131072),.sample_flags(8'd0),
            .capture_tag(cap[g]),.input_sample_rate_hz(input_rate),.expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),
            .wms_scan_start(scan[g]),.wms_cycle_id(cycle[g*32+:32]),.wms_sine_phase(phase[g*32+:32]),.wms_phase_valid(pv[g]),
            .timestamp_now(tick),.time_sync_valid(1'b1),.pps_mode(pm[g]),.scan_aborted(aborted[g]),.trigger_ready(tr[g]),.scan_drained(drained[g]),
            .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(ready[g+1]),.cfg_rdata(rdata[g+1]),.cfg_error(error[g+1]),
            .m_valid(mv[g]),.m_ready(host_ready),.m_data(md[g]),.m_sof(ms[g]),.m_last(ml[g]),.m_cycle_id(mc[g]),.m_flags(mf[g]),.m_timestamp(mt[g]));
        always @(posedge clk)if(rst)begin
            if(scan[g])begin start_tick[g]=tick;starts[g]=starts[g]+1;writes[g]=0;
                if(pm[g] && phase[g*32+:32]!=32'h12345678)$fatal(1,"phase did not restart");end
            if(sv && pv[g] && cap[g][192] && !sr[g])$fatal(1,"ADC sample blocked");
            if(sv && sr[g] && cap[g][192])samples[g]=samples[g]+1;
            if(wms.channels[g].channel.sample_applied && wms.channels[g].channel.tx_window)writes[g]=writes[g]+1;
            if(mv[g] && host_ready && compare_frames)begin
                if(mt[g]!=start_tick[g] || mc[g]!=starts[g])$fatal(1,"frame association");
                if(mf[g][5]!==expect_abort || (mf[g][4] && !expect_fault))$fatal(1,"normal/abort flags %h",mf[g]);
                if(ms[g])idx[g]=0;
                if(!expect_abort)begin
                    if(idx[g]==2 && md[g]!=(g==0?16:8))$fatal(1,"point count %d %d",g,md[g]);
                    if(frames[g]==0)golden[g*64+idx[g]]=md[g];
                    if(frames[g]==1 && md[g]!==golden[g*64+idx[g]])$fatal(1,"independent filter reset mismatch %d %d",g,idx[g]);
                end
                idx[g]=idx[g]+1;
                if(ml[g])frames[g]=frames[g]+1;
            end
        end
    end endgenerate
    always @(posedge clk)if(rst)begin
        sv<=0;
        if(tick%100==0)begin
            cap[0]<={1'b1,pv[0],start_tick[0],tick,phase[31:0],cycle[31:0]};
            cap[1]<={1'b1,pv[1],start_tick[1],tick,phase[63:32],cycle[63:32]};
            delay_count<=15;
        end else if(delay_count!=0)begin delay_count<=delay_count-1'b1;if(delay_count==1)sv<=1;end
    end
    task pulse;
        begin
            @(negedge clk);while(tick%100!=0)@(negedge clk);
            pps_tick=tick;pps_seq=pps_seq+1;pps=1;@(negedge clk);pps=0;
        end
    endtask
    integer k;
    initial begin
        for(k=0;k<2;k=k+1)begin starts[k]=0;frames[k]=0;samples[k]=0;writes[k]=0;idx[k]=0;start_tick[k]=0;cap[k]=0;end
        repeat(8)@(negedge clk);rst=1;repeat(1000)@(negedge clk);
        for(k=0;k<2;k=k+1)begin
            bus.read32('h204c+k*256,rv);if(rv!=0)$fatal(1,"reset default mode");
            bus.read32('h2084+k*256,rv);if(rv!=32'h50505301)$fatal(1,"PPS API");
            bus.expect_error(1,'h2084+k*256,1);bus.expect_error(1,'h204c+k*256,2);
            bus.write32('h3004+k*256,1);
            bus.write32('h2010+k*256,k==0?6250000:12500000);
            bus.write32('h201c+k*256,20000000);bus.write32('h2024+k*256,32'h12345678);
            bus.write32('h204c+k*256,1);bus.write32('h2050+k*256,32'h10000000);
            bus.write32('h2004+k*256,4);
            bus.write32('h501c+k*256,100000);bus.write32('h5004+k*256,4);
        end
        repeat(200)@(negedge clk);
        bus.write32('h5004,1);bus.write32('h5104,1);bus.write32('h2004,1);bus.write32('h2104,1);
        wait(wms.channels[0].channel.wms.armed && wms.channels[1].channel.wms.armed);
        repeat(2000)@(negedge clk);if(starts[0] || starts[1] || samples[0] || samples[1])$fatal(1,"no PPS should wait");
        if(code[0]!=20'd589823 || code[1]!=20'd589823)$fatal(1,"waiting DAC code %d",code[0]);
        qualified=0;pulse;repeat(100)@(negedge clk);if(starts[0])$fatal(1,"unqualified PPS");qualified=1;
        host_ready=0;pulse;wait(scan==3);#1;
        if(start_tick[0]!=start_tick[1])$fatal(1,"two channel start skew");
        bus.expect_error(1,'h204c,0);bus.expect_error(1,'h2004,5);
        bus.expect_error(1,'h5004,5);bus.write32('h500c,32'hffffffff);
        pulse; // busy trigger must not restart or queue
        wait(pv==0);repeat(200)@(negedge clk);
        if(writes[0]!=16 || writes[1]!=8 || samples[0]!=160 || samples[1]!=80)$fatal(1,"one scan counts writes=%d/%d samples=%d/%d",writes[0],writes[1],samples[0],samples[1]);
        if(starts[0]!=1 || starts[1]!=1)$fatal(1,"busy retrigger");
        pulse;repeat(100)@(negedge clk);if(starts[0]!=1)$fatal(1,"drain retrigger");
        host_ready=1;wait(frames[0]==1 && frames[1]==1);
        wait(wms.channels[0].channel.wms.armed && wms.channels[1].channel.wms.armed);
        bus.read32('h205c,rv);if(rv!=2)$fatal(1,"missed count %d",rv);
        bus.read32('h2088,rv);if(rv!=1)$fatal(1,"unqualified count");
        pulse;wait(frames[0]==2 && frames[1]==2);
        wait(wms.channels[0].channel.wms.armed && wms.channels[1].channel.wms.armed);
        bus.read32('h207c,rv);if(rv!=2)$fatal(1,"completed count");
        // Disable mid-scan restores idle, drains a partial frame, no queued restart.
        expect_abort=1;pulse;wait(scan[0]);repeat(3500)@(negedge clk);
        bus.write32('h2004,0);bus.write32('h2104,0);wait(frames[0]==3 && frames[1]==3);
        wait(!wms.channels[0].channel.wms.burst_busy && !wms.channels[1].channel.wms.burst_busy);
        bus.read32('h2080,rv);if(rv!=1)$fatal(1,"abort count");
        // A custom SOS input-rate fault must not strand the ordered end marker.
        unity_bank=0;for(w=0;w<4;w=w+1)unity_bank[w*240+:48]=48'd70368744177664;
        for(k=0;k<2;k=k+1)begin
            bus.write32('h5060+k*256,2);
            for(w=0;w<30;w=w+1)bus.write32('h5068+k*256+w*4,unity_bank[w*32+:32]);
            bus.write32('h5004+k*256,5);
        end
        repeat(200)@(negedge clk);
        bus.write32('h2004,1);bus.write32('h2104,1);
        wait(wms.channels[0].channel.wms.armed && wms.channels[1].channel.wms.armed);
        expect_fault=1;pulse;wait(scan[0]);repeat(3500)@(negedge clk);input_rate=500000;
        wait(frames[0]==4 && frames[1]==4);
        wait(!wms.channels[0].channel.wms.burst_busy && !wms.channels[1].channel.wms.burst_busy);
        bus.read32('h500c,rv);if(!rv[8])$fatal(1,"missing custom rate fault");
        input_rate=1000000;bus.write32('h500c,32'hffffffff);bus.write32('h510c,32'hffffffff);
        bus.write32('h2004,0);bus.write32('h2104,0);
        compare_frames=0;
        bus.write32('h204c,0);bus.write32('h214c,0);
        bus.write32('h2004,1);bus.write32('h2104,1);
        wait(starts[0]>=6 && starts[1]>=6); // autonomous scan remains available
        bus.write32('h2004,0);bus.write32('h2104,0);
        $display("PPS_WMS_DLIA_PASS default/arming/dual-start/one-scan/phase-reset/filter-reset/qualification/missed/drain/abort/rate-fault/legacy");$finish;
    end
    initial begin #5000000;$fatal(1,"PPS timeout frames=%d/%d starts=%d/%d busy=%b open=%b close=%b end=%b",frames[0],frames[1],starts[0],starts[1],wms.channels[0].channel.wms.burst_busy,ch[0].core.burst_open,ch[0].core.burst_close,ch[0].core.burst_end_seen);end
endmodule
