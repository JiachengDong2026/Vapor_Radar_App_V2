`timescale 1ns/1ps
module tb_wms_wavegen;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,enable=1,ready=1,transport=1;
    wire [63:0] ts;wire sync;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire [31:0] sample_data,cycle,phase;wire valid,scan,running,pv,changed;
    reg [31:0] data,a,b,o,expect_sample[0:191],expect_phase[0:191],expect_cycle[0:191];
    reg [31:0] amps[0:3],samps[0:3],offs[0:3],held;
    integer f,n,j,r,seen=0,base=0;reg compare=0;
    time_sync_stub timebase(.clk(clk),.rst_n(rst),.timestamp_now(ts),.time_sync_valid(sync),.time_sync_seq(),.sync_event_pulse());
    cfg_test_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    wms_wavegen dut(.sys_clk(clk),.rst_sys_n(rst),.enable(enable),.timestamp_now(ts),.time_sync_valid(sync),
        .transport_ready(transport),.max_update_hz(32'd800000),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.dac_sample(sample_data),.dac_sample_valid(valid),.dac_sample_ready(ready),
        .scan_start(scan),.cycle_id(cycle),.sine_phase(phase),.wms_running(running),.phase_valid(pv),.config_changed(changed));
    always @(posedge clk)if(rst && valid && ready && compare)begin
        if(sample_data!==expect_sample[base+seen] || phase!==expect_phase[base+seen] || cycle!==expect_cycle[base+seen])
            $fatal(1,"WMS_GOLDEN idx=%d got=%h expected=%h phase=%h cycle=%d",base+seen,sample_data,expect_sample[base+seen],phase,cycle);
        seen=seen+1;
    end
    always @(negedge clk)if(scan && (!pv || phase!==expect_phase[base+seen]) && compare)$fatal(1,"SCAN_PHASE_ALIGNMENT");
    task configure;
        input [31:0] aa,bb,oo;
        begin
            bus.write32('h2004,2);bus.write32('h2010,6250000);bus.write32('h201c,25000000);
            bus.write32('h2014,aa);bus.write32('h2020,bb);bus.write32('h2018,oo);bus.write32('h2040,0);
            bus.write32('h2028,100000);bus.write32('h2004,4);repeat(3)@(negedge clk);
        end
    endtask
    initial begin
        f=$fopen("wms_vectors.txt","r");if(!f)$fatal(1,"VECTOR_OPEN");
        for(n=0;n<192;n=n+1)begin
            r=$fscanf(f,"%h %h %h %h %h %h\n",a,b,o,expect_sample[n],expect_phase[n],expect_cycle[n]);
            if(r!=6)$fatal(1,"VECTOR_FORMAT");amps[n/48]=a;samps[n/48]=b;offs[n/48]=o;
        end
        repeat(5)@(negedge clk);rst=1;repeat(3)@(negedge clk);
        bus.read32('h2000,data);if(data!=='h00100103)$fatal(1,"ID");
        for(n=0;n<=18;n=n+1)bus.read32('h2000+4*n,data);
        bus.outside('h10002000);bus.outside('h2100);
        bus.expect_error(0,'h2001,0);bus.expect_error(0,'h20fc,0);bus.expect_error(1,'h202c,1);bus.expect_error(1,'h2004,'h10);
        bus.masked('h2018,'h12345678,5);bus.read32('h2018,data);if(data!=='h00340078)$fatal(1,"WSTRB");
        bus.write32('h2028,0);bus.expect_error(1,'h2004,4);
        bus.write32('h2028,800001);bus.expect_error(1,'h2004,4);
        bus.write32('h2028,100000);bus.write32('h2010,50000001);bus.expect_error(1,'h2004,4);
        bus.write32('h200c,'hffffffff);bus.read32('h200c,data);if(data)$fatal(1,"ERROR_W1C");
        for(j=0;j<4;j=j+1)begin
            configure(amps[j],samps[j],offs[j]);
            bus.read32('h202c,data);if(data!=100000)$fatal(1,"ACT_RATE");
            base=j*48;seen=0;compare=1;bus.write32('h2004,1);
            wait(seen==48);@(negedge clk);compare=0;bus.write32('h2004,0);
            if(j>=2)begin bus.read32('h203c,data);if(data==0)$fatal(1,"SAT_COUNTER");end
            bus.write32('h203c,'hffffffff);bus.read32('h203c,data);if(data)$fatal(1,"SAT_W1C");
        end
        // Snapshot must remain immutable while subsequent shadow writes occur.
        configure(0,0,0);bus.write32('h2004,1);wait(valid);@(negedge clk);
        bus.write32('h2018,'h10000000);bus.write32('h2004,5);
        bus.expect_error(1,'h2004,5);bus.write32('h2018,'h20000000);
        wait(changed);wait(scan);wait(valid);#1;if(sample_data!=='h10000000)$fatal(1,"PENDING_SNAPSHOT");
        bus.write32('h2004,0);repeat(10)@(negedge clk);
        // Ready stalls hold data. A stall extending to the next update stops with a visible error.
        ready=0;bus.write32('h2004,1);wait(valid);#1;held=sample_data;
        repeat(1200)begin @(negedge clk);if(valid && sample_data!==held)$fatal(1,"BACKPRESSURE_STABILITY");end
        if(running || !valid)$fatal(1,"OVERRUN_STOP");
        bus.read32('h2044,data);if(data!=1)$fatal(1,"OVERRUN_COUNT");
        bus.read32('h200c,data);if(!data[8])$fatal(1,"OVERRUN_ERROR");
        ready=1;bus.write32('h2004,0);bus.write32('h2004,2);bus.read32('h2030,data);if(data)$fatal(1,"RESET_CYCLE");
        $display("TEST_PASS tb_wms_wavegen 192 golden samples, cfg, snapshot, saturation, backpressure, overrun, reset");$finish;
    end
    initial begin #10000000;$fatal(1,"TIMEOUT");end
endmodule
