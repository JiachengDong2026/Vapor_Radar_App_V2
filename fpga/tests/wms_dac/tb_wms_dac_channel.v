`timescale 1ns/1ps
module tb_wms_dac_channel;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire sclk,sync_n,sdin,reset_n,clr_n,ldac_n;
    wire [19:0] code;wire [31:0] frames;
    reg [31:0] data;
    cfg_test_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    wms_dac_channel #(.WMS_BASE(32'h2200),.DAC_BASE(32'h3200),.WMS_ID(16'habcd),.DAC_ID(16'hdcba)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.enable(1'b1),.timestamp_now(64'd12345678),.time_sync_valid(1'b1),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),
        .scan_start(),.cycle_id(),.sine_phase(),.wms_running(),.phase_valid(),.config_changed(),
        .dac_sclk(sclk),.dac_sync_n(sync_n),.dac_sdin(sdin),.dac_sdo(1'b0),.dac_rst_n(reset_n),.dac_clr_n(clr_n),.dac_ldac_n(ldac_n));
    ad5791_model model(.sclk(sclk),.sync_n(sync_n),.sdin(sdin),.rst_n(reset_n),.clr_n(clr_n),.ldac_n(ldac_n),
        .code(code),.control(),.clear_code(),.last_frame(),.frame_count(frames));
    initial begin
        repeat(5)@(negedge clk);rst=1;repeat(1000)@(negedge clk);
        bus.read32('h2200,data);if(data!=='habcd0103)$fatal(1,"RELOCATED_WMS_ID");
        bus.read32('h3200,data);if(data!=='hdcba0103)$fatal(1,"RELOCATED_DAC_ID");
        bus.outside('h2000);bus.outside('h3000);bus.outside('h10002200);
        bus.write32('h3204,1);bus.write32('h2214,0);bus.write32('h2220,0);bus.write32('h2218,'h20000000);
        bus.write32('h2228,200000);bus.write32('h2204,5);wait(frames>=8);#1;
        if(code!==20'd655359)$fatal(1,"CHANNEL_MAPPING");
        bus.read32('h2234,data);if(data!=12345678)$fatal(1,"SCAN_TIMESTAMP");
        bus.read32('h220c,data);if(data)$fatal(1,"CHANNEL_ERROR");
        $display("TEST_PASS tb_wms_dac_channel relocated pages/IDs, timestamp capture and full chain");$finish;
    end
    initial begin #1000000;$fatal(1,"TIMEOUT");end
endmodule
