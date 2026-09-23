`timescale 1ns/1ps
module tb_modbus_rtu_master;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,valid=0;wire ready,done,busy;
    reg [7:0] func=3;reg [15:0] address=0;reg [4:0] quantity=4;
    reg [255:0] write_data=0;reg [3:0] inject=0;reg [1:0] retries=0;
    wire [3:0] error,attempt_error;wire [7:0] exception;
    wire [255:0] read_data;wire [63:0] stamp;reg [63:0] now=0;
    wire sync,de,txd,rxd,attempt_pulse;
    wire [31:0] requests,writes,last_written;reg [31:0] before_requests;
    integer mode;
    always @(posedge clk)now<=now+1;
    modbus_rtu_master #(.SYS_CLK_HZ(1000000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.enable(1'b1),.baud_hz(32'd19200),.parity_mode(2'd0),.stop_bits(2'd2),
        .req_valid(valid),.req_ready(ready),.req_slave(8'd240),.req_function(func),.req_address(address),.req_quantity(quantity),
        .req_write_data(write_data),.timeout_ms(16'd30),.retry_limit(retries),.timestamp_now(now),.time_sync_valid(1'b1),
        .done(done),.error(error),.exception_code(exception),.read_data(read_data),.response_timestamp(stamp),.response_time_sync(sync),
        .attempt_error_pulse(attempt_pulse),.attempt_error(attempt_error),.uart_rxd(rxd),.uart_txd(txd),.rs485_de(de),.busy(busy));
    modbus_sensor_model #(.SYS_CLK_HZ(1000000),.DEVICE_KIND(0)) device(
        .clk(clk),.rst_n(rst),.request_txd(txd),.rs485_de(de),.response_rxd(rxd),.inject_mode(inject),
        .native_temperature(32'd2500000),.device_error(16'd0),.request_count(requests),.write_count(writes),.last_written(last_written),.response_start_pulse());
    task request;
        input [3:0] expected_error;
        begin
            @(negedge clk);valid=1;
            begin:wait_ready forever begin @(posedge clk);if(ready)disable wait_ready;end end
            @(negedge clk);valid=0;wait(done);#1;
            if(error!==expected_error)$fatal(1,"RTU_ERROR inject=%d got=%d expected=%d",inject,error,expected_error);
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;request(0);
        if(read_data[63:0]!==64'hcc41000048420000 || !sync || stamp==0 || stamp>=now)$fatal(1,"RTU_READ_TIMESTAMP");
        func=16;address='h300;quantity=2;write_data[31:0]='h7d440050;request(0);
        if(last_written!=='h447d5000 || writes!=1)$fatal(1,"RTU_WRITE");
        inject=8;request(3);
        func=3;address=0;quantity=4;
        for(mode=1;mode<=7;mode=mode+1)begin
            inject=mode;
            case(mode)
                1:request(2);2,3,4:request(3);5:begin request(4);if(exception!=2)$fatal(1,"EXCEPTION_CODE");end
                6:request(1);7:request(5);
            endcase
        end
        inject=9;request(5);
        inject=1;retries=1;before_requests=requests;request(2);if(requests-before_requests!=2)$fatal(1,"RETRY_BOUND");
        inject=0;retries=0;request(0);quantity=0;request(6);
        $display("TEST_PASS tb_modbus_rtu_master 03/10, quiet timing, echo suppression, CRC/slave/function/length/exception/UART/gap/timeout/retry");$finish;
    end
    initial begin #20000000;$fatal(1,"TIMEOUT");end
endmodule
