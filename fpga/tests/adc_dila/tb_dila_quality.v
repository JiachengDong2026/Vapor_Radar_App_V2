`timescale 1ns/1ps
module tb_dila_quality;
    reg clk=0,rst=0,sv=0,cv=0,cw=0;
    reg [7:0] flags=0;
    reg [193:0] tag=0;
    reg [31:0] ca=0,cd=0;
    wire [1:0] ready;
    always #5 clk=~clk;
    genvar i;
    generate for(i=0;i<2;i=i+1)begin:cores
        dila_core #(.USE_CAPTURE_TAGS(1),.BASE_ADDR(32'h5000+i*256)) dut(
            .sys_clk(clk),.rst_sys_n(rst),.sample_valid(sv),.sample_ready(ready[i]),
            .sample_data(32'd100),.sample_flags(flags),.capture_tag(tag),
            .wms_scan_start(1'b0),.wms_cycle_id(32'd99),.wms_sine_phase(32'd0),.wms_phase_valid(1'b1),
            .timestamp_now(64'd1),.time_sync_valid(1'b1),.input_sample_rate_hz(32'd1000000),
            .expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),
            .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),
            .cfg_ready(),.cfg_rdata(),.cfg_error(),.cfg_error_code(),
            .m_ready(1'b1),.m_valid(),.m_data(),.m_keep(),.m_sof(),.m_last(),.m_source_id(),.m_msg_id(),
            .m_timestamp(),.m_cycle_id(),.m_flags(),.output_queue_level(),.datapath_idle());
    end endgenerate
    task wr;
        input [31:0] a,d;
        begin @(negedge clk);cv=1;cw=1;ca=a;cd=d;@(negedge clk);cv=0;cw=0;end
    endtask
    task sample;
        input phase;input [7:0] f;
        begin
            @(negedge clk);tag={1'b1,phase,64'd0,64'd1,32'd0,32'd1};flags=f;sv=1;
            wait(ready==3);@(posedge clk);@(negedge clk);sv=0;
            repeat(8)@(negedge clk);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;wr('h5004,1);wr('h5104,1);
        sample(0,0);
        if(!cores[0].dut.error_status[7] || !cores[1].dut.error_status[7] ||
           !cores[0].dut.cycle_partial || cores[0].dut.out_count!=0 || cores[1].dut.out_count!=0)
            $fatal(1,"invalid captured phase must fail despite live valid phase");
        wr('h5004,2);wr('h5104,2);wr('h5004,1);wr('h5104,1);
        sample(1,0);
        if(cores[0].dut.error_status[7] || cores[1].dut.error_status[7])$fatal(1,"valid captured phase rejected");
        sample(1,1);
        if(!cores[0].dut.error_status[7] || !cores[1].dut.error_status[7] ||
           cores[0].dut.in_sat_count!=1 || cores[1].dut.in_sat_count!=1 || !cores[0].dut.cycle_partial)
            $fatal(1,"saturation must retain quality failure");
        $display("TEST_PASS tb_dila_quality both channels invalid capture phase startup, valid phase, saturation");$finish;
    end
    initial begin #100000;$fatal(1,"watchdog");end
endmodule
