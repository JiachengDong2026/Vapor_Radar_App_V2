`timescale 1ns/1ps
module tb_ai8_sample_epoch;
    reg clk=0,rst_n=0,ready=0,live_sync=1;
    reg [7:0] slave_address=1;
    always #250 clk=~clk;
    reg [63:0] ticks=0;
    always @(posedge clk)ticks<=ticks+1;
    wire txd,rxd,de,valid,sample_sync,online;
    wire [63:0] sample_ticks;
    wire [3:0] error;
    reg [63:0] held_ticks;
    reg held_sync;
    integer i;
    ai8_poll_core #(.SYS_CLK_HZ(2000000)) core(
        .clk(clk),.rst_n(rst_n),.enable(1'b1),.baud_hz(32'd100000),.slave_addr(slave_address),.channel(8'd1),
        .parity_mode(2'd0),.stop_bits(2'd1),.retry_limit(2'd1),.poll_interval_ms(32'd1),.timeout_ms(16'd5),
        .uart_rxd(rxd),.uart_txd(txd),.rs485_de(de),.bus_request(),.bus_busy(),.bus_grant(1'b1),
        .sample_ready(ready),.sample_valid(valid),.pv_raw(),.sp_raw(),.sv_raw(),.op_raw(),
        .alarm(),.control(),.host_status(),.online(online),.last_error(error),.exception_code(),
        .good_count(),.error_count(),.sample_ticks(sample_ticks),.now_ticks(ticks),
        .time_sync_valid(live_sync),.sample_time_sync(sample_sync),
        .set_valid(1'b0),.set_ready(),.set_raw(16'd0),.set_rsp_valid(),.set_rsp_ready(1'b1),
        .set_result(),.set_error(),.set_exception(),.set_requested(),.set_readback());
    ai8_setpoint_slave_bfm #(.BAUD_HZ(100000)) device(
        .rst_n(rst_n),.master_txd(txd),.master_de(de),.fault_mode(4'd0),.slave_txd(rxd),
        .request_count(),.write_count(),.verify_count(),.current_sp());
    task capture_and_hold;
        input expected_sync;input [3:0] expected_error;
        begin
            wait(valid);@(negedge clk);
            if(sample_sync!==expected_sync || sample_ticks!==ticks-1 || error!==expected_error)
                $fatal(1,"publication timestamp/epoch not same input edge");
            held_ticks=sample_ticks;held_sync=sample_sync;
            for(i=0;i<5000;i=i+1)begin
                live_sync=~live_sync;@(negedge clk);
                if(!valid || sample_ticks!==held_ticks || sample_sync!==held_sync)
                    $fatal(1,"held sample epoch changed under backpressure");
            end
        end
    endtask
    task consume;
        begin ready=1;@(negedge clk);ready=0;end
    endtask
    initial begin
        repeat(10)@(negedge clk);rst_n=1;
        capture_and_hold(1,0);
        live_sync=0;consume;
        capture_and_hold(0,0);
        slave_address=0;live_sync=1;consume;
        capture_and_hold(1,6);
        rst_n=0;repeat(3)@(negedge clk);
        if(valid || sample_ticks || sample_sync)$fatal(1,"reset epoch not cleared");
        $display("TEST_PASS tb_ai8_sample_epoch publication edge, both sync states, config-error epoch, backpressure and reset");
        $finish;
    end
    initial begin #300000000;$fatal(1,"sample epoch watchdog");end
endmodule
