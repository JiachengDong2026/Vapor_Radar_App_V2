`timescale 1ns/1ps
module tb_system_reset_controller;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,soft=0,clock_req=0,wd=0,sr=0,sc=0,uc=0,fr=0,quiet=0;
    reg [31:0] mask=1,ms=2;
    wire pending,rc,ra,rw,rs,rm,rstream,rt,fx;wire [31:0] forced;
    integer tick=0,start_tick,cases=0;
    always @(posedge clk)tick=tick+1;
    system_reset_controller #(.SYS_CLK_HZ(1000000),.DRAIN_TIMEOUT_TICKS(100),.STARTUP_FX3_RESET_MS(0)) dut(
        .sys_clk(clk),.rst_power_n(rst),.soft_request(soft),.clock_request(clock_req),.watchdog_request(wd),
        .stream_reset_request(sr),.stream_clear_request(sc),.usb_clear_request(uc),.fx3_request(fr),
        .reset_mask(mask),.fx3_reset_ms(ms),.path_quiet(quiet),.reset_pending(pending),
        .rst_control_n(rc),.rst_adc_n(ra),.rst_wms_n(rw),.rst_sensors_n(rs),.rst_motor_n(rm),
        .rst_stream_n(rstream),.rst_transport_n(rt),.fx3_reset_n(fx),.forced_clear_count(forced));
    initial begin
        repeat(4)@(negedge clk);rst=1;repeat(3)@(negedge clk);
        soft=1;@(negedge clk);soft=0;
        repeat(40)begin @(negedge clk);if(!rc || !fx || !ra)$fatal(1,"reset before response drained");end
        quiet=1;wait(!rc);@(negedge clk);
        if(ra || rstream || rt || !rw || !rs || !rm || !fx)$fatal(1,"producer reset dependency mask");
        start_tick=tick;wait(rc);if(tick-start_tick<15)$fatal(1,"reset hold too short");cases=cases+1;
        @(negedge clk);uc=1;@(negedge clk);uc=0;wait(!rc);@(negedge clk);
        if(!ra || !rw || !rs || !rm || rstream || rt || !fx)$fatal(1,"USB clear reset external device");
        wait(rc);cases=cases+1;
        @(negedge clk);quiet=0;mask=1;wd=1;@(negedge clk);wd=0;
        wait(!rc);@(negedge clk);
        if(ra || rw || rs || rm || rstream || rt || !fx || forced!=1)$fatal(1,"watchdog forced internal reset");
        wait(rc);
        cases=cases+1;
        @(negedge clk);quiet=1;mask=0;clock_req=1;@(negedge clk);clock_req=0;
        wait(!rc);@(negedge clk);
        if(ra || rw || rs || rm || rstream || rt || !fx)$fatal(1,"zero mask must select all internal groups");
        wait(rc);wait(fx);cases=cases+1;
        @(negedge clk);fr=1;@(negedge clk);fr=0;
        wait(!fx);@(negedge clk);
        if(!ra || !rw || !rs || !rm || rstream || rt)$fatal(1,"explicit FX3 reset dependencies");
        start_tick=tick;wait(fx);if(tick-start_tick<1998)$fatal(1,"FX3 reset shorter than programmed ms");
        wait(rc);cases=cases+1;
        if(forced!=1)$fatal(1,"quiet resets counted forced");
        $display("tb_system_reset_controller_PASS cases=%0d forced=%0d",cases,forced);$finish;
    end
    initial begin #100000;$fatal(1,"reset test timeout");end
endmodule
