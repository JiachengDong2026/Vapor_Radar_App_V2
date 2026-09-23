`timescale 1ns/1ps
module tb_adc_channel_regs;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,scan=0,v=0,wr=0;
    reg [31:0] addr=0,data=0;
    wire ready,err,en,raw,sreset,clear;
    wire [31:0] rd,period,rate,cnv,timeout,expected,errors;
    adc_channel_regs dut(.clk(clk),.rst_n(rst_n),.scan_start(scan),.cfg_valid(v),.cfg_write(wr),.cfg_addr(addr),.cfg_wdata(data),.cfg_wstrb(4'hf),
        .cfg_ready(ready),.cfg_rdata(rd),.cfg_error(err),.initialized(1'b1),.phy_busy(1'b0),.capture_pulse(1'b0),
        .overflow_pulse(1'b0),.timeout_pulse(1'b0),.align_pulse(1'b0),.external_drop_increment(2'd0),.fifo_level(32'd0),.sync_count(32'd0),
        .enable(en),.raw_enable(raw),.soft_reset(sreset),.clear_fifo(clear),.period_ticks(period),.rate_actual(rate),.cnv_ticks(cnv),.busy_timeout(timeout),.expected_per_cycle(expected),.error_status(errors));
    task write;
        input [7:0] ofs;input [31:0] value;
        begin @(negedge clk);v=1;wr=1;addr=32'h4000+ofs;data=value;#1;if(!ready||err)$fatal(1,"cfg write rejected");@(negedge clk);v=0;wr=0;end
    endtask
    initial begin
        #32;rst_n=1;write(4,1);write(16,500000);write(28,123);write(48,4);write(4,5);
        // The commit snapshot must survive later shadow writes.
        write(16,250000);write(28,456);write(48,6);
        repeat(150)@(posedge clk);
        if(rate!=1000000 || cnv!=2 || expected!=0)$fatal(1,"changed outside boundary");
        @(negedge clk);scan=1;@(negedge clk);scan=0;
        if(rate!=500000 || period!=200 || cnv!=4 || expected!=123)$fatal(1,"boundary atomic snapshot failed");
        write(4,4);repeat(150)@(posedge clk);
        if(rate!=250000 || cnv!=6 || expected!=456)$fatal(1,"disabled commit failed");
        $display("ADC_CHANNEL_REGS_PASS atomic_boundary snapshot disabled_commit");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
