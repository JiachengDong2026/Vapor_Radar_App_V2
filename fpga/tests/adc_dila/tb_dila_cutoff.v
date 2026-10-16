`timescale 1ns/1ps
module tb_dila_cutoff;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0,cw=0,sv=0;reg [31:0] ca=0,cd=0;reg [193:0] tag=0;
    wire cr,ce,sr;wire [31:0] rd;
    reg [31:0] cutoffs[0:6];integer i;
    dila_core #(.USE_CAPTURE_TAGS(1),.OUTPUT_FORMAT(1)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.sample_valid(sv),.sample_ready(sr),.sample_data(32'd1000000),.sample_flags(8'd0),
        .wms_scan_start(1'b0),.wms_cycle_id(32'd0),.wms_sine_phase(32'd0),.wms_phase_valid(1'b1),
        .timestamp_now(64'd1),.time_sync_valid(1'b1),.capture_tag(tag),.input_sample_rate_hz(32'd1000000),
        .expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_ready(1'b1));
    task write;
        input [7:0] offset;input [31:0] value;input expect_error;
        begin
            @(negedge clk);cv=1;cw=1;ca='h5000+offset;cd=value;
            @(posedge clk);if(!cr || ce!==expect_error)$fatal(1,"cutoff cfg %h error=%b",offset,ce);
            @(negedge clk);cv=0;cw=0;
        end
    endtask
    task sample;
        input [31:0] cycle;
        begin
            @(negedge clk);tag={2'b11,64'd1,64'd1,32'd0,cycle};sv=1;
            while(!sr)@(negedge clk);
            @(negedge clk);sv=0;repeat(12)@(negedge clk);
        end
    endtask
    initial begin
        cutoffs[0]=100;cutoffs[1]=250;cutoffs[2]=500;cutoffs[3]=1000;cutoffs[4]=2000;cutoffs[5]=5000;cutoffs[6]=10000;
        repeat(5)@(negedge clk);rst=1;
        if(dut.cutoff_active!=1000)$fatal(1,"legacy default cutoff");
        write('h58,999,1);write('h5c,100,1);
        for(i=0;i<7;i=i+1)begin
            write('h58,cutoffs[i],0);write('h04,4,0);repeat(100)@(negedge clk);
            if(dut.pending || dut.cutoff_active!=cutoffs[i])$fatal(1,"disabled commit cutoff %0d",cutoffs[i]);
        end
        write('h04,1,0);sample(1);
        write('h58,250,0);write('h04,5,0);repeat(100)@(negedge clk);
        if(dut.cutoff_active!=10000 || !dut.pending)$fatal(1,"cutoff applied inside a capture cycle");
        sample(2);
        if(dut.cutoff_active!=250 || dut.pending)$fatal(1,"cutoff did not apply at boundary");
        if(dut.lpf_profiles[0].coefficients.b0!==48'sd43344068)$fatal(1,"active coefficient profile");
        $display("TEST_PASS tb_dila_cutoff seven profiles, default compatibility, invalid/readonly rejection, atomic capture-boundary commit");$finish;
    end
    initial begin #1000000;$fatal(1,"cutoff timeout");end
endmodule
