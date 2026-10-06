`timescale 1ns/1ps
module tb_wms_dac_dual;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;reg [1:0] enable=3;
    wire [63:0] ts,cycles,phases;wire sync;
    wire [1:0] scan,running,pv,changed,sclk,sync_n,sdin,reset_n,clr_n,ldac_n;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire [19:0] code0,code1;wire [31:0] frames0,frames1;
    reg [31:0] data,old_count;integer n;
    cfg_test_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    time_sync_stub timebase(.clk(clk),.rst_n(rst),.timestamp_now(ts),.time_sync_valid(sync),.time_sync_seq(),.sync_event_pulse());
    wms_dac_dual dut(.sys_clk(clk),.rst_sys_n(rst),.enable(enable),.timestamp_now(ts),.time_sync_valid(sync),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),
        .scan_start(scan),.cycle_id(cycles),.sine_phase(phases),.wms_running(running),.phase_valid(pv),.config_changed(changed),
        .dac_sclk(sclk),.dac_sync_n(sync_n),.dac_sdin(sdin),.dac_sdo(2'b0),.dac_rst_n(reset_n),.dac_clr_n(clr_n),.dac_ldac_n(ldac_n));
    ad5791_model model0(.sclk(sclk[0]),.sync_n(sync_n[0]),.sdin(sdin[0]),.rst_n(reset_n[0]),.clr_n(clr_n[0]),.ldac_n(ldac_n[0]),
        .code(code0),.control(),.clear_code(),.last_frame(),.frame_count(frames0));
    ad5791_model model1(.sclk(sclk[1]),.sync_n(sync_n[1]),.sdin(sdin[1]),.rst_n(reset_n[1]),.clr_n(clr_n[1]),.ldac_n(ldac_n[1]),
        .code(code1),.control(),.clear_code(),.last_frame(),.frame_count(frames1));
    initial begin
        repeat(5)@(negedge clk);rst=1;repeat(1000)@(negedge clk);
        bus.read32('h2100,data);if(data!=='h00110103)$fatal(1,"CHANNEL1_ID");
        bus.outside('h10002000);bus.outside('h3200);
        bus.write32('h3004,1);bus.write32('h3104,1);
        bus.write32('h2014,0);bus.write32('h2020,0);bus.write32('h2018,'hc0000000);
        bus.write32('h2010,10000000);bus.write32('h201c,20000000);
        bus.write32('h2028,609757);bus.expect_error(1,'h2004,5);bus.write32('h200c,'hffffffff);
        bus.write32('h2028,600000);
        bus.write32('h2114,0);bus.write32('h2120,0);bus.write32('h2118,'h40000000);
        bus.write32('h2110,5000000);bus.write32('h211c,10000000);bus.write32('h2128,500000);
        bus.write32('h2004,5);bus.write32('h2104,5);
        bus.read32('h202c,data);if(data!=598802)$fatal(1,"SAFE_ACTUAL_UPDATE_RATE");
        wait(frames0>30 && frames1>30);#1;
        if(code0!==20'd262144 || code1!==20'd786431)$fatal(1,"DUAL_INDEPENDENT_CODES %h %h",code0,code1);
        if(!running[0] || !running[1] || cycles[31:0]==0 || cycles[63:32]==0)$fatal(1,"DUAL_RUNNING");
        bus.read32('h200c,data);if(data)$fatal(1,"CHANNEL0_ERROR %h",data);
        bus.read32('h210c,data);if(data)$fatal(1,"CHANNEL1_ERROR %h",data);
        bus.expect_error(1,'h3004,5);
        bus.write32('h2004,0);repeat(200)@(negedge clk);old_count=frames0;
        repeat(1000)@(negedge clk);if(frames0!=old_count || !running[1])$fatal(1,"STOP_ISOLATION");
        bus.write32('h2004,1);wait(frames0>old_count);
        enable[1]=0;repeat(300)@(negedge clk);if(running[1] || !running[0])$fatal(1,"ENABLE_ISOLATION");
        bus.write32('h2004,2);if(running[0])$fatal(1,"SOFT_RESET_STOP");
        $display("TEST_PASS tb_wms_dac_dual concurrent 598802/500000 samples/s, 609756 capacity, page isolation, stop/restart/enable independence");$finish;
    end
    initial begin #2000000;$fatal(1,"TIMEOUT");end
endmodule
