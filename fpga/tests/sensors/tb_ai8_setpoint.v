`timescale 1ns/1ps
module tb_ai8_setpoint;
    wire invalid_done;
    invalid_setpoint_case invalid_config(invalid_done);
    reg clk=0, rst_n=0;
    always #250 clk=~clk;
    reg [63:0] ticks=0;
    always @(posedge clk) ticks<=ticks+1;
    reg cmd_valid=0, rsp_ready=0, sample_ready=0;
    reg [15:0] cmd_raw=0;
    reg [3:0] fault=0;
    wire cmd_ready, rsp_valid, sample_valid, txd, rxd, de, online;
    wire [3:0] result, error, poll_error;
    wire [7:0] exception, alarm, control, poll_exception;
    wire [15:0] requested, readback, current_sp, pv, sp, sv, op, host;
    wire [31:0] good, bad;
    wire [63:0] sample_ticks;
    wire [31:0] request_count, write_count, verify_count;
    integer before_writes, before_verify, completed_commands=0, old_good;
    reg [47:0] held_rsp;
    reg [236:0] held_sample;
    wire [236:0] sample_payload={pv,sp,sv,op,host,alarm,control,online,poll_error,poll_exception,good,bad,sample_ticks};
    ai8_poll_compat #(.SYS_CLK_HZ(2000000),.BAUD_HZ(100000),.SLAVE_ADDR(80),.CHANNEL(96),
        .POLL_MS(2),.TIMEOUT_MS(5),.RETRY_LIMIT(1)) dut (
        .clk(clk),.rst_n(rst_n),.uart_rxd(rxd),.uart_txd(txd),.rs485_de(de),
        .sample_ready(sample_ready),.sample_valid(sample_valid),.pv_raw(pv),.sp_raw(sp),.sv_raw(sv),.op_raw(op),
        .alarm(alarm),.control(control),.host_status(host),.online(online),.last_error(poll_error),
        .exception_code(poll_exception),.good_count(good),.error_count(bad),.sample_ticks(sample_ticks),.now_ticks(ticks),
        .set_valid(cmd_valid),.set_ready(cmd_ready),.set_raw(cmd_raw),.set_rsp_valid(rsp_valid),.set_rsp_ready(rsp_ready),
        .set_result(result),.set_error(error),.set_exception(exception),.set_requested(requested),.set_readback(readback)
    );
    ai8_setpoint_slave_bfm #(.BAUD_HZ(100000),.SLAVE_ADDR(80),.CHANNEL(96)) slave (
        .rst_n(rst_n),.master_txd(txd),.master_de(de),.slave_txd(rxd),.fault_mode(fault),
        .request_count(request_count),.write_count(write_count),.verify_count(verify_count),.current_sp(current_sp)
    );
    task send_command;
        input [15:0] value;
        begin
            @(negedge clk); cmd_raw=value; cmd_valid=1;
            wait(cmd_ready); @(posedge clk); @(negedge clk); cmd_valid=0;
        end
    endtask
    task consume_response;
        begin rsp_ready=1; @(negedge clk); rsp_ready=0; end
    endtask
    task check_poll;
        begin
            wait(sample_valid); @(negedge clk);
            if(!online || poll_error || bad || sp!==current_sp || pv!==244 || sv!==450 || op!==12800 ||
                alarm!==8'ha2 || control!==8'h03 || host!==16'h0301) $fatal(1,"post-command poll atomic/data/status");
        end
    endtask
    task exercise;
        input [15:0] value;
        input [3:0] mode, expected_result, expected_error;
        input [7:0] expected_exception;
        input integer expected_writes, expected_verifies;
        begin
            fault=mode; before_writes=write_count; before_verify=verify_count; old_good=good;
            send_command(value); wait(rsp_valid); @(negedge clk);
            if(result!==expected_result || error!==expected_error || exception!==expected_exception || requested!==value)
                $fatal(1,"set response raw=%h result=%d error=%d exception=%d",value,result,error,exception);
            if(write_count-before_writes!=expected_writes || verify_count-before_verify!=expected_verifies)
                $fatal(1,"write/verify attempts incorrect w=%d v=%d",write_count-before_writes,verify_count-before_verify);
            if(result==0 && (readback!==value || current_sp!==value)) $fatal(1,"false confirmed result");
            if(result==3 && (readback===value || readback!==current_sp)) $fatal(1,"locked mismatch not exposed");
            consume_response;
            wait(good>old_good); check_poll;
            completed_commands=completed_commands+1;
        end
    endtask
    initial begin
        repeat(10) @(negedge clk); rst_n=1;
        wait(sample_valid); @(negedge clk);
        if(write_count!=0) $fatal(1,"startup wrote instrument");
        held_sample=sample_payload;
        // A pending command must wait for consumption of the complete snapshot.
        cmd_raw=16'd550; cmd_valid=1;
        repeat(5000) begin
            @(negedge clk);
            if(cmd_ready || write_count!=0 || sample_payload!==held_sample) $fatal(1,"command preempted held poll");
        end
        sample_ready=1;
        wait(cmd_ready); @(posedge clk); @(negedge clk); cmd_valid=0;
        wait(rsp_valid); @(negedge clk);
        if(result!==0 || requested!==550 || readback!==550) $fatal(1,"first command failed");
        held_rsp={result,error,exception,requested,readback}; before_writes=write_count;
        // A response may be held while polling continues, but a second write waits.
        cmd_raw=16'd660; cmd_valid=1;
        repeat(80000) begin
            @(negedge clk);
            if(!rsp_valid || cmd_ready || {result,error,exception,requested,readback}!==held_rsp || write_count!=before_writes)
                $fatal(1,"response backpressure instability");
        end
        cmd_valid=0; consume_response; check_poll;
        exercise(16'd244,0,0,0,0,1,1);
        exercise(-16'sd123,0,0,0,0,1,1);
        exercise(-16'sd9990,0,0,0,0,1,1);
        exercise(16'd32000,0,0,0,0,1,1);
        exercise(-16'sd9991,0,4,0,0,0,0);
        exercise(16'd32001,0,4,0,0,0,0);
        exercise(16'h8000,0,4,0,0,0,0);
        exercise(16'h7fff,0,4,0,0,0,0);
        exercise(16'd777,1,3,0,0,1,1);
        exercise(16'd888,2,1,1,0,2,0);
        exercise(16'd999,3,1,2,0,2,0);
        exercise(16'd1111,4,1,4,3,1,0);
        exercise(16'd1222,5,2,1,0,1,2);
        exercise(16'd1333,6,2,2,0,1,2);
        exercise(16'd1444,7,2,4,2,1,1);
        exercise(16'd1555,0,0,0,0,1,1);
        // Reset while a write frame is in flight, then ensure startup is read-only.
        fault=0; send_command(16'd1666); wait(de); repeat(20) @(negedge clk);
        rst_n=0; repeat(10) @(negedge clk);
        if(de || txd!==1 || rsp_valid || sample_valid || cmd_ready || good || bad) $fatal(1,"reset state not cleared");
        rst_n=1; check_poll;
        if(write_count!=0 || rsp_valid || sp!==500) $fatal(1,"reset caused unrequested write");
        wait(invalid_done);
        $display("SETPOINT_CASES_PASS commands=%0d",completed_commands);
        $display("TEST_PASS tb_ai8_setpoint"); $finish;
    end
    initial begin #2000000000; $fatal(1,"setpoint watchdog"); end
endmodule

module invalid_setpoint_case(output reg finished=0);
    reg clk=0, rst_n=0, valid=0, rsp_ready=0;
    reg [15:0] raw=244;
    always #250 clk=~clk;
    wire ready, rsp_valid, txd, de;
    wire [3:0] result, error;
    wire [7:0] exception;
    wire [15:0] requested, readback;
    integer i, j;
    ai8_poll_compat #(.SYS_CLK_HZ(2000000),.CHANNEL(0),.POLL_MS(0)) dut (
        .clk(clk),.rst_n(rst_n),.uart_rxd(1'b1),.uart_txd(txd),.rs485_de(de),
        .sample_ready(1'b1),.sample_valid(),.pv_raw(),.sp_raw(),.sv_raw(),.op_raw(),
        .alarm(),.control(),.host_status(),.online(),.last_error(),.exception_code(),
        .good_count(),.error_count(),.sample_ticks(),.now_ticks(64'd42),
        .set_valid(valid),.set_ready(ready),.set_raw(raw),.set_rsp_valid(rsp_valid),.set_rsp_ready(rsp_ready),
        .set_result(result),.set_error(error),.set_exception(exception),.set_requested(requested),.set_readback(readback)
    );
    always @(negedge clk) if(rst_n && (de || txd!==1)) $fatal(1,"invalid config transmitted Modbus");
    initial begin
        repeat(10) @(negedge clk); rst_n=1;
        for(i=0;i<2;i=i+1) begin
            raw=244+i; valid=1;
            wait(ready); @(posedge clk); @(negedge clk); valid=0;
            wait(rsp_valid);
            for(j=0;j<20;j=j+1) begin
                @(negedge clk);
                if(!rsp_valid || ready || result!==5 || error!==6 || exception!==0 || requested!==raw || readback!==0)
                    $fatal(1,"invalid config SET response/deadlock");
            end
            rsp_ready=1; @(negedge clk); rsp_ready=0;
        end
        finished=1;
    end
endmodule
