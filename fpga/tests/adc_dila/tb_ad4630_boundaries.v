`timescale 1ns/1ps
module tb_ad4630_boundaries;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0,cw=0;reg [31:0] ca=0,cd=0;wire cr,ce;wire [31:0] rd;
    wire cnv,csn,sck,sdi,arst,busy,configured;wire [7:0] sdo;wire [31:0] count;
    wire mv;wire [31:0] md;integer received=0;
    adc_ad4630_if #(.SIMULATION(1)) dut(.sys_clk(clk),.rst_sys_n(rst),
        .wms_scan_start(1'b0),.wms_cycle_id(32'd0),.wms_sine_phase(32'd0),.wms_phase_valid(1'b0),
        .timestamp_now(64'd0),.time_sync_valid(1'b0),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),
        .cfg_ready(cr),.cfg_error(ce),.cfg_rdata(rd),.m_valid(mv),.m_ready(1'b1),.m_data(md),.external_drop_increment(2'd0),
        .adc_sdo(sdo),.adc_busy(busy),.adc_sdi(sdi),.adc_rst_n(arst),.adc_cnv(cnv),.adc_cs_n(csn),.adc_sck(sck));
    // A deliberately late BUSY exceeds the official 300ns conversion maximum.
    ad4630_model #(.CONVERSION_MAX_NS(850.0)) model(.rst_n(arst),.cnv(cnv),.cs_n(csn),.sck(sck),.sdi(sdi),.stall_busy(1'b0),
        .busy(busy),.sdo(sdo),.conversions(count),.configured(configured));
    task write_reg;input [31:0] a,d;begin
        @(negedge clk);cv=1;cw=1;ca=a;cd=d;@(posedge clk);if(!cr||ce)$fatal(1,"BOUNDARY_CFG %h",a);
        @(negedge clk);cv=0;cw=0;
    end endtask
    realtime last_cnv=0,last_edge=0;integer starts=0;
    always @(csn or sck)if(configured)last_edge=$realtime;
    always @(posedge cnv)begin
        if(last_cnv!=0 && $realtime-last_cnv<1000)$fatal(1,"CNV_PERIOD_UNDERRUN");
        if(configured && $realtime-last_edge<50)$fatal(1,"CNV_QUIET_UNDERRUN %f",$realtime-last_edge);
        last_cnv=$realtime;starts=starts+1;
    end
    always @(posedge clk)if(mv)received=received+1;
    initial begin
        repeat(5)@(negedge clk);rst=1;write_reg('h4004,1);wait(configured);
        repeat(4)begin
            @(posedge cnv);repeat(10)@(negedge clk);write_reg('h4004,0);
            repeat(2)@(negedge clk);write_reg('h4004,1);
        end
        wait(received>=4);write_reg('h4004,0);repeat(150)@(negedge clk);
        write_reg('h4034,40);write_reg('h4004,4);repeat(100)@(negedge clk);write_reg('h4004,1);
        repeat(4)begin @(posedge cnv);repeat(8)@(negedge clk);write_reg('h4004,0);repeat(2)@(negedge clk);write_reg('h4004,1);end
        repeat(150)@(negedge clk);@(negedge clk);cv=1;cw=0;ca='h400c;#1;
        if(!rd[0])$fatal(1,"EXPECTED_BUSY_TIMEOUT");
        $display("AD4630_BOUNDARIES_PASS starts=%0d received=%0d late_BUSY enable_toggle timeout quiet_and_period",starts,received);$finish;
    end
    initial begin #200000;$fatal(1,"BOUNDARY_TIMEOUT");end
endmodule
