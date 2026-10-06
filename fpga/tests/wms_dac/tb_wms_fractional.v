`timescale 1ns/1ps
module tb_wms_fractional;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire [31:0] sample_data,phase,cycle;wire valid,scan,pv,running;
    reg [31:0] expected,ep,ec,data;
    integer f,r,n=0;time previous=0;
    cfg_test_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    wms_wavegen dut(.sys_clk(clk),.rst_sys_n(rst),.enable(1'b1),.timestamp_now(64'd0),.time_sync_valid(1'b1),
        .transport_ready(1'b1),.max_update_hz(32'd800000),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.dac_sample(sample_data),.dac_sample_valid(valid),.dac_sample_ready(1'b1),
        .scan_start(scan),.cycle_id(cycle),.sine_phase(phase),.wms_running(running),.phase_valid(pv),.config_changed());
    initial begin
        f=$fopen("wms_fractional.txt","r");if(!f)$fatal(1,"VECTOR_OPEN");
        repeat(5)@(negedge clk);rst=1;
        bus.write32('h2010,1234567);bus.write32('h201c,43211234);bus.write32('h2014,'h37098765);
        bus.write32('h2020,-32'h5a876543);bus.write32('h2018,'h18765432);bus.write32('h2024,'h12345678);
        bus.write32('h2028,730000);bus.write32('h2004,4);repeat(3)@(negedge clk);
        bus.read32('h202c,data);if(data!=729927)$fatal(1,"QUANTIZED_ACT");
        bus.read32('h2048,data);if(data!=137)$fatal(1,"PERIOD");bus.write32('h2004,1);
        while(n<700)begin
            @(posedge clk);if(valid)begin
                r=$fscanf(f,"%h %h %h\n",expected,ep,ec);
                if(sample_data!==expected || phase!==ep || cycle!==ec)$fatal(1,"FRACTIONAL_GOLDEN n=%d got=%h exp=%h phase=%h ep=%h cycle=%d ec=%d",n,sample_data,expected,phase,ep,cycle,ec);
                if(n>0 && $time-previous!=1370)$fatal(1,"UPDATE_CADENCE");previous=$time;n=n+1;
            end
        end
        $display("TEST_PASS tb_wms_fractional 700 noncardinal samples, fractional DDS, wraps and exact cadence");$finish;
    end
    initial begin #2000000;$fatal(1,"TIMEOUT");end
endmodule
