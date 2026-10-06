`timescale 1ns/1ps
// Pin-level slave: no DUT UART, CRC, or Modbus implementation is reused.
module ai8_case #(parameter CH = 1, PARITY = 0, STOPS = 1, ADDR = 1, BAUD = 100000)(output reg finished);
    localparam BIT_NS = 1000000000 / BAUD;
    reg clk = 0, rst_n = 0, rxd = 1, ready = 0;
    always #250 clk = ~clk;
    reg [63:0] ticks = 0;
    always @(posedge clk) ticks <= ticks + 1;
    wire txd, de, valid, online;
    wire [15:0] pv, sp, sv, op, host;
    wire [7:0] alarm, control, exception;
    wire [3:0] error;
    wire [31:0] good, bad;
    wire [63:0] sample_ticks;
    ai8_poll_compat #(.SYS_CLK_HZ(2000000), .BAUD_HZ(BAUD), .CHANNEL(CH), .SLAVE_ADDR(ADDR),
        .PARITY_MODE(PARITY), .STOP_BITS(STOPS), .POLL_MS(1),
        .TIMEOUT_MS(5), .RETRY_LIMIT(1)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rxd(rxd), .uart_txd(txd), .rs485_de(de),
        .sample_ready(ready), .sample_valid(valid), .pv_raw(pv), .sp_raw(sp),
        .sv_raw(sv), .op_raw(op), .alarm(alarm), .control(control), .host_status(host),
        .online(online), .last_error(error), .exception_code(exception),
        .good_count(good), .error_count(bad), .sample_ticks(sample_ticks), .now_ticks(ticks),
        .set_valid(1'b0), .set_raw(16'd0), .set_rsp_ready(1'b1),
        .set_ready(), .set_rsp_valid(), .set_result(), .set_error(), .set_exception(),
        .set_requested(), .set_readback()
    );
    integer mode = 0, version = 0, step = 0, failures = 0, requests = 0;
    integer j, n, count_before;
    reg [7:0] request [0:7];
    reg [7:0] reply [0:6];
    reg [15:0] crc, addr, word_value;
    reg [236:0] held;
    time last_bus_activity = 0;
    wire [236:0] snapshot = {pv,sp,sv,op,host,alarm,control,online,error,exception,good,bad,sample_ticks};
    always @(negedge de) if(rst_n) last_bus_activity=$time;
    always @(posedge de) if(rst_n && last_bus_activity!=0 && $time-last_bus_activity<1750000)
        $fatal(1,"CH%0d high-baud request silence shorter than 1.75ms",CH);
    function [15:0] expected_address;
        input integer i;
        begin
            case(i)
                0: expected_address = CH-1;
                1: expected_address = 16'h600+CH-1;
                2: expected_address = 16'h480+CH-1;
                3: expected_address = 16'h360+CH-1;
                4: expected_address = 16'h680+(CH-1)/2;
                5: expected_address = 16'h6c0+(CH-1)/2;
                default: expected_address = 16'h851;
            endcase
        end
    endfunction
    function [15:0] reference_crc;
        input [15:0] previous;
        input [7:0] data;
        reg [15:0] shift;
        integer bit_index;
        begin
            shift = previous ^ data;
            for (bit_index=0; bit_index<8; bit_index=bit_index+1) begin
                if (shift & 1) shift = (shift >> 1) ^ 16'hA001;
                else shift = shift >> 1;
            end
            reference_crc = shift;
        end
    endfunction
    task receive_byte;
        output [7:0] data;
        integer b;
        begin
            @(negedge txd);
            if (!de) $fatal(1,"CH%0d transmitted without DE",CH);
            #(BIT_NS/2);
            if (txd !== 0) $fatal(1,"bad start");
            #BIT_NS;
            for (b=0;b<8;b=b+1) begin data[b]=txd; #BIT_NS; end
            if (PARITY) begin
                if (txd !== ^data) $fatal(1,"bad even parity");
                #BIT_NS;
            end
            for (b=0;b<STOPS;b=b+1) begin
                if (txd !== 1) $fatal(1,"bad stop");
                if (b<STOPS-1) #BIT_NS;
            end
            #(BIT_NS/4);
        end
    endtask
    task send_byte;
        input [7:0] data;
        integer b;
        begin
            if (de) $fatal(1,"slave/master collision");
            rxd=0; #BIT_NS;
            for(b=0;b<8;b=b+1) begin rxd=data[b]; #BIT_NS; end
            if(PARITY) begin rxd=^data; #BIT_NS; end
            rxd=1; #(BIT_NS*STOPS);
        end
    endtask
    initial begin
        wait(rst_n);
        forever begin
            for(j=0;j<8;j=j+1) receive_byte(request[j]);
            requests=requests+1;
            crc=16'hffff;
            for(j=0;j<8;j=j+1) crc=reference_crc(crc,request[j]);
            addr={request[2],request[3]};
            if(crc!==0 || request[0]!==ADDR || request[1]!==3 ||
                request[4]!==0 || request[5]!==1 || addr!==expected_address(step))
                $fatal(1,"CH%0d invalid/read-write/address/CRC request step=%0d addr=%h crc=%h",CH,step,addr,crc);
            @(negedge de);
            #(BIT_NS*2);
            case(step)
                0: word_value=version ? 16'd700 : 16'd500;
                1: word_value=version ? 16'd321 : -16'd123;
                2: word_value=version ? 16'd600 : 16'd450;
                3: word_value=16'd12800;
                4: word_value=16'h15a2;
                5: word_value=16'h0103;
                default: word_value=16'h0301;
            endcase
            reply[0]=ADDR; reply[1]=3; reply[2]=2;
            reply[3]=word_value[15:8]; reply[4]=word_value[7:0]; n=5;
            if(mode==3 && step==5) begin reply[1]=8'h83; reply[2]=2; n=3; end
            crc=16'hffff;
            for(j=0;j<n;j=j+1) crc=reference_crc(crc,reply[j]);
            if((mode==1 && step==2) || (mode==4 && step==1 && failures==0)) crc=crc^16'h0001;
            reply[n]=crc[7:0]; reply[n+1]=crc[15:8];
            if (!(mode==2 && step==1)) begin
                for(j=0;j<n+2;j=j+1) begin
                    send_byte(reply[j]);
                    if(j==0 && step==2 && mode==5) #500000;
                    if(j==0 && step==2 && mode==6) #800000;
                end
                last_bus_activity=$time;
            end
            if((mode==1 && step==2) || (mode==2 && step==1) || (mode==6 && step==2)) begin
                if(failures==0) failures=1;
                else begin failures=0; step=0; end
            end else if(mode==3 && step==5) step=0;
            else if(mode==4 && step==1 && failures==0) failures=1;
            else begin failures=0; if(step==6) step=0; else step=step+1; end
        end
    end
    task await_sample;
        begin wait(valid); @(negedge clk); end
    endtask
    task consume;
        begin ready=1; @(negedge clk); ready=0; end
    endtask
    task check_success;
        input integer expected_good, expected_bad;
        begin
            if(!online || error!==0 || exception!==0 || good!==expected_good || bad!==expected_bad)
                $fatal(1,"CH%0d success status good=%d bad=%d error=%d",CH,good,bad,error);
            if(sp!==(version ? 16'd700:16'd500) || pv!==(version ? 16'd321:-16'd123) ||
                sv!==(version ? 16'd600:16'd450) || op!==12800 || host!==16'h0301 ||
                alarm!==(CH%2 ? 8'h15:8'ha2) || control!==(CH%2 ? 8'h01:8'h03))
                $fatal(1,"CH%0d data/mapping mismatch pv=%h sp=%h sv=%h alarm=%h control=%h",CH,pv,sp,sv,alarm,control);
            if(sample_ticks==0 || sample_ticks>ticks) $fatal(1,"timestamp invalid");
        end
    endtask
    task check_failure;
        input [3:0] expected_error;
        input integer expected_bad;
        begin
            if(online || error!==expected_error || good!==1 || bad!==expected_bad ||
                exception!==(expected_error==4 ? 8'd2:8'd0)) $fatal(1,"failure diagnostic mismatch");
            if(sp!==500 || pv!==-16'd123 || sv!==450 || op!==12800 || host!==16'h0301 ||
                alarm!==(CH%2 ? 8'h15:8'ha2) || control!==(CH%2 ? 8'h01:8'h03))
                $fatal(1,"partial failed poll contaminated previous sample");
        end
    endtask
    initial begin
        finished=0;
        repeat(10) @(negedge clk); rst_n=1;
        await_sample; check_success(1,0);
        held=snapshot; count_before=requests;
        repeat(10000) begin
            @(negedge clk);
            if(!valid || snapshot!==held || de || requests!=count_before) $fatal(1,"backpressure instability");
        end
        version=1; mode=1; count_before=requests; consume;
        await_sample; check_failure(2,1);
        if(requests-count_before!=4) $fatal(1,"CRC retry count incorrect");
        mode=2; count_before=requests; consume;
        await_sample; check_failure(1,2);
        if(requests-count_before!=3) $fatal(1,"timeout retry count incorrect");
        mode=3; count_before=requests; consume;
        await_sample; check_failure(4,3);
        if(requests-count_before!=6) $fatal(1,"exception should not retry");
        mode=6; count_before=requests; consume;
        await_sample; check_failure(5,4);
        if(requests-count_before!=4) $fatal(1,"invalid frame gap retry count incorrect");
        mode=5; consume; await_sample; check_success(2,4);
        mode=4; count_before=requests; consume;
        await_sample; check_success(3,4);
        if(requests-count_before!=8) $fatal(1,"transient CRC recovery retry missing");
        mode=0; consume; await_sample; check_success(4,4);
        // Reset a held snapshot. No request may survive reset; the next poll recovers.
        rst_n=0; repeat(10) @(negedge clk);
        if(valid || online || good || bad || pv || sp || sample_ticks || de || txd!==1) $fatal(1,"reset outputs");
        rst_n=1; await_sample; check_success(1,0);
        $display("AI8_CASE_PASS CH=%0d address=%0d parity=%0d stops=%0d requests=%0d",CH,ADDR,PARITY,STOPS,requests);
        finished=1;
    end
endmodule

module invalid_case #(parameter ADDR=0, CH=1, PARITY=0, STOPS=1)(output reg finished);
    reg clk=0, rst_n=0;
    always #250 clk=~clk;
    wire valid, txd, de;
    wire [3:0] error;
    wire [31:0] errors;
    ai8_poll_compat #(.SYS_CLK_HZ(2000000), .BAUD_HZ(100000), .SLAVE_ADDR(ADDR),
        .CHANNEL(CH), .PARITY_MODE(PARITY), .STOP_BITS(STOPS)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rxd(1'b1), .uart_txd(txd), .rs485_de(de),
        .sample_ready(1'b0), .sample_valid(valid), .last_error(error), .error_count(errors), .now_ticks(64'd42),
        .pv_raw(), .sp_raw(), .sv_raw(), .op_raw(), .alarm(), .control(), .host_status(),
        .online(), .exception_code(), .good_count(), .sample_ticks(),
        .set_valid(1'b0), .set_raw(16'd0), .set_rsp_ready(1'b1),
        .set_ready(), .set_rsp_valid(), .set_result(), .set_error(), .set_exception(),
        .set_requested(), .set_readback()
    );
    initial begin
        finished=0;
        repeat(10) @(negedge clk); rst_n=1;
        repeat(1000) begin
            @(negedge clk);
            if(de || txd!==1) $fatal(1,"invalid config emitted traffic");
        end
        if(!valid || error!==6 || errors!==1) $fatal(1,"invalid config missing diagnostic");
        finished=1;
    end
endmodule

module tb_ai8_poll;
    wire odd_done, even_done, boundary_done;
    wire [6:0] invalid_done;
    ai8_case #(.CH(1)) odd_channel(odd_done);
    ai8_case #(.CH(2), .PARITY(1), .STOPS(2)) even_channel(even_done);
    ai8_case #(.CH(96), .ADDR(80), .STOPS(2), .BAUD(115200)) boundary_channel(boundary_done);
    invalid_case bad_address_zero(invalid_done[0]);
    invalid_case #(.ADDR(81)) bad_address_high(invalid_done[1]);
    invalid_case #(.ADDR(1),.CH(0)) bad_channel_zero(invalid_done[2]);
    invalid_case #(.ADDR(1),.CH(97)) bad_channel_high(invalid_done[3]);
    invalid_case #(.ADDR(1),.PARITY(2)) bad_parity(invalid_done[4]);
    invalid_case #(.ADDR(1),.STOPS(0)) bad_stop_zero(invalid_done[5]);
    invalid_case #(.ADDR(1),.STOPS(3)) bad_stop_high(invalid_done[6]);
    initial begin
        wait(odd_done && even_done && boundary_done && (&invalid_done));
        $display("AI8_POLL_ALL_TESTS_PASS");
        $display("TEST_PASS tb_ai8_poll"); $finish;
    end
    initial begin #500000000; $fatal(1,"test watchdog expired"); end
endmodule
