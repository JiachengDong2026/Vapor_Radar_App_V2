`timescale 1ns/1ps
module tb_dila_reference_alignment;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,valid=0,cv=0;
    reg [31:0] addr=0,wdata=0;
    reg signed [31:0] sample_data=0;
    reg [193:0] tag=0;
    wire ready,cfg_ready,cfg_error;
    wire [31:0] rdata;
    integer head=0,tail=0,checks=0,n;
    reg [127:0] expected[0:127];
    reg [193:0] tags[0:127];
    reg [1:0] quadrant;
    reg [127:0] iq;
    dila_core #(.USE_CAPTURE_TAGS(1),.OUTPUT_FORMAT(1)) dut(
        .sys_clk(clk),.rst_sys_n(rst_n),.sample_valid(valid),.sample_ready(ready),
        .sample_data(sample_data),.sample_flags(8'd0),.capture_tag(tag),
        .wms_scan_start(1'b0),.wms_cycle_id(32'd1),.wms_sine_phase(32'd0),
        .wms_phase_valid(1'b1),.timestamp_now(64'd0),.time_sync_valid(1'b1),
        .pps_mode(1'b0),.scan_aborted(1'b0),.capture_stopped(1'b1),
        .input_sample_rate_hz(32'd1000000),.expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),
        .cfg_valid(cv),.cfg_write(1'b1),.cfg_addr(addr),.cfg_wdata(wdata),.cfg_wstrb(4'hf),
        .cfg_ready(cfg_ready),.cfg_rdata(rdata),.cfg_error(cfg_error),.m_ready(1'b1));
    function signed [17:0] sine_quadrant;
        input [1:0] phase;
        begin
            case(phase)
                1:sine_quadrant=18'sd131071;
                3:sine_quadrant=-18'sd131071;
                default:sine_quadrant=0;
            endcase
        end
    endfunction
    function [31:0] scaled;
        input signed [31:0] value;
        input signed [17:0] coefficient;
        reg signed [63:0] product,result;
        begin
            product=value*coefficient;
            if(product<0)result=-((-product+65536)/131072);
            else result=(product+65536)/131072;
            scaled=result[31:0];
        end
    endfunction
    always @(posedge clk)begin
        if(!rst_n)begin head=0;tail=0;end
        else begin
            if(valid && ready)begin
                quadrant=tag[63:62];
                iq={scaled(sample_data,sine_quadrant(quadrant*2)),
                    scaled(sample_data,sine_quadrant(quadrant*2+1)),
                    scaled(sample_data,sine_quadrant(quadrant)),
                    scaled(sample_data,sine_quadrant(quadrant+1))};
                expected[tail]=iq;tags[tail]=tag;tail=tail+1;
            end
            if(dut.mix_valid)begin
                if(head>=tail)$fatal(1,"Unexpected/duplicate mixer output");
                if(dut.mix_tag!==tags[head] || dut.mix_iq!==expected[head])
                    $fatal(1,"Reference/sample/tag mismatch index=%0d got=%h expected=%h",head,dut.mix_iq,expected[head]);
                head=head+1;checks=checks+1;
            end
            if(head<tail && !(valid && ready) && dut.config_pipeline_idle)
                $fatal(1,"Pipeline reported idle with a pending sample");
        end
    end
    task write_reg;
        input [31:0] a,d;
        begin
            @(negedge clk);addr=a;wdata=d;cv=1;
            @(posedge clk);if(!cfg_ready || cfg_error)$fatal(1,"Configuration rejected");
            @(negedge clk);cv=0;
        end
    endtask
    task configure;
        begin
            write_reg(32'h5020,5);write_reg(32'h501c,100000);
            write_reg(32'h5004,4);repeat(120)@(negedge clk);
            write_reg(32'h5004,1);
        end
    endtask
    task send_sample;
        input integer index;
        begin
            @(negedge clk);
            sample_data=(index[0]?-1:1)*(1234567+index*7919);
            tag={2'b11,64'd1000,64'd1000+index,{index[1:0],30'd0},32'd1};valid=1;
            @(posedge clk);while(!ready)@(posedge clk);
            @(negedge clk);valid=0;
        end
    endtask
    initial begin #2000000;$fatal(1,"Timeout");end
    initial begin
        repeat(5)@(negedge clk);rst_n=1;configure;
        for(n=0;n<64;n=n+1)send_sample(n);
        // Disable with the last reference/sample still in flight; it must drain.
        write_reg(32'h5004,0);wait(head==tail);repeat(20)@(negedge clk);
        if(checks!=64)$fatal(1,"Lost sample during STOP");
        configure;send_sample(3);
        // Assert reset before this sample reaches the mixer output.
        rst_n=0;repeat(5)@(negedge clk);rst_n=1;
        repeat(20)@(negedge clk);if(checks!=64)$fatal(1,"Reset leaked an old sample");
        configure;for(n=0;n<16;n=n+1)send_sample(n+64);
        wait(head==tail);repeat(20)@(negedge clk);
        if(checks!=80)$fatal(1,"Reset recovery count");
        $display("DILA_REFERENCE_ALIGNMENT_PASS samples=80 stop_drain reset quadrant_rounding tags");$finish;
    end
endmodule
