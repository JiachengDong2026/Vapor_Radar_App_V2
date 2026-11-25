`timescale 1ns/1ps
module tb_adc_measurement_start;
    reg clk=0,rst_n=0,valid=0,write=0;
    reg [31:0] addr=0,data=0,cycle0=0,cycle1=0;
    reg scan0=0,scan1=0,window0=0,window1=0;
    reg [1:0] mode=0;
    reg [63:0] tick=0;
    wire ready,error,cnv,busy,sdi,adc_rst_n,cs_n,sck,configured,start_event;
    wire [7:0] sdo;
    wire [31:0] conversions;
    integer starts=0,expected=0;
    reg pending_event=0;
    always #5 clk=~clk;
    always @(posedge clk)begin
        tick<=tick+1'b1;
        pending_event=start_event;
        #1;
        if(pending_event)begin
            if(!cnv || !window0 || !window1 || mode!=3)$fatal(1,"ADC marker not on common first CNV");
            starts=starts+1;
        end
    end
    adc_ad4630_dual_if #(.SIMULATION(1),.FIFO_DEPTH(16)) dut(
        .sys_clk(clk),.rst_sys_n(rst_n),.pps_mode(mode),.capture_start_event(start_event),
        .wms0_scan_start(scan0),.wms0_cycle_id(cycle0),.wms0_sine_phase(32'd0),.wms0_phase_valid(window0),
        .wms1_scan_start(scan1),.wms1_cycle_id(cycle1),.wms1_sine_phase(32'd0),.wms1_phase_valid(window1),
        .timestamp_now(tick),.time_sync_valid(1'b1),
        .cfg_valid(valid),.cfg_write(write),.cfg_addr(addr),.cfg_wdata(data),.cfg_wstrb(4'hf),
        .cfg_ready(ready),.cfg_error(error),.m0_ready(1'b1),.m1_ready(1'b1),
        .external_drop_increment0(2'd0),.external_drop_increment1(2'd0),
        .adc_sdo(sdo),.adc_busy(busy),.adc_sdi(sdi),.adc_rst_n(adc_rst_n),
        .adc_cnv(cnv),.adc_cs_n(cs_n),.adc_sck(sck));
    ad4630_model model(.rst_n(adc_rst_n),.cnv(cnv),.cs_n(cs_n),.sck(sck),.sdi(sdi),
        .stall_busy(1'b0),.busy(busy),.sdo(sdo),.conversions(conversions),.configured(configured));
    task write_reg;
        input [31:0] a,d;
        begin
            @(negedge clk);valid=1;write=1;addr=a;data=d;#1;
            if(!ready || error)$fatal(1,"ADC marker config %h",a);
            @(negedge clk);valid=0;write=0;
        end
    endtask
    task check_count;
        input integer count;
        begin
            repeat(500)@(negedge clk);
            if(starts!=count)$fatal(1,"ADC marker count %0d expected %0d",starts,count);
        end
    endtask
    task window_both;
        input [31:0] c0,c1;
        begin
            @(negedge clk);cycle0=c0;cycle1=c1;scan0=1;scan1=1;window0=1;window1=1;
            @(negedge clk);scan0=0;scan1=0;
        end
    endtask
    initial begin
        repeat(8)@(negedge clk);rst_n=1;
        wait(configured);repeat(20)@(negedge clk);
        write_reg('h4004,1);write_reg('h4104,1);
        window_both(1,7);check_count(0); // Continuous mode never marks PPS starts.
        @(negedge clk);window0=0;window1=0;mode=3;
        check_count(0); // Background conversions are not a measurement window.
        window_both(2,8);check_count(1);
        check_count(1); // Many further samples in the same window: no duplicate.
        @(negedge clk);window0=0;window1=0;
        window_both(32'hffffffff,32'hffffffff);check_count(2);
        @(negedge clk);window0=0;window1=0;
        window_both(0,0);check_count(3); // U32 cycle wrap remains observable.
        // Channel 0 starts first. Opening channel 1 later must NOT fabricate a
        // common first conversion, even though both are then simultaneously valid.
        @(negedge clk);cycle0=1;cycle1=1;scan0=1;scan1=1;window1=0;
        @(negedge clk);scan0=0;scan1=0;
        check_count(3);
        @(negedge clk);window1=1;check_count(3);
        @(negedge clk);window0=0;window1=0;
        window_both(2,2);check_count(4);
        // A stopped logical peer cannot be represented by the shared marker.
        write_reg('h4104,0);
        window_both(3,3);check_count(4);
        @(negedge clk);mode=0;window0=0;window1=0;
        write_reg('h4104,1);window_both(4,4);check_count(4);
        @(negedge clk);rst_n=0;
        #1;if(start_event)$fatal(1,"ADC event survived reset");
        $display("ADC_MEASUREMENT_START_PASS common_CNV_no_background_no_continuous_no_misaligned_no_disabled_peer_cycle_wrap_reset");$finish;
    end
    initial begin #300000;$fatal(1,"ADC start test timeout");end
endmodule
