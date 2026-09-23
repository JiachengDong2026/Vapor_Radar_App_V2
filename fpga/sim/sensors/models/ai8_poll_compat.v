`timescale 1ns/1ps
`default_nettype none
// AI-8 manual V9.6 section 7. Poll with FC03; only the selected SP may be
// written using FC10 and must then be read back. No run/control writes exist.
module ai8_poll_compat #(
    parameter integer SYS_CLK_HZ = 25000000,
    parameter integer BAUD_HZ = 19200,
    parameter integer SLAVE_ADDR = 1,
    parameter integer CHANNEL = 1,
    parameter integer PARITY_MODE = 0,
    parameter integer STOP_BITS = 1,
    parameter integer POLL_MS = 1000,
    parameter integer TIMEOUT_MS = 200,
    parameter integer RETRY_LIMIT = 1
)(
    input wire clk, input wire rst_n, input wire uart_rxd,
    output wire uart_txd, output wire rs485_de,
    input wire sample_ready, output wire sample_valid,
    output wire [15:0] pv_raw, output wire [15:0] sp_raw,
    output wire [15:0] sv_raw, output wire [15:0] op_raw,
    output wire [7:0] alarm, output wire [7:0] control,
    output wire [15:0] host_status, output wire online,
    output wire [3:0] last_error, output wire [7:0] exception_code,
    output wire [31:0] good_count, output wire [31:0] error_count,
    output wire [63:0] sample_ticks, input wire [63:0] now_ticks,
    input wire set_valid, output wire set_ready, input wire [15:0] set_raw,
    output wire set_rsp_valid, input wire set_rsp_ready,
    output wire [3:0] set_result, output wire [3:0] set_error,
    output wire [7:0] set_exception,
    output wire [15:0] set_requested, output wire [15:0] set_readback
);
 ai8_poll_core #(.SYS_CLK_HZ(SYS_CLK_HZ)) dut(
 .enable(1'b1),.baud_hz(BAUD_HZ),.slave_addr(SLAVE_ADDR[7:0]),.channel(CHANNEL[7:0]),
 .parity_mode(PARITY_MODE[1:0]),.stop_bits(STOP_BITS[1:0]),.retry_limit(RETRY_LIMIT[1:0]),
 .timeout_ms(TIMEOUT_MS[15:0]),.poll_interval_ms(POLL_MS),.bus_request(),.bus_busy(),.bus_grant(1'b1),
 .clk(clk),
 .rst_n(rst_n),
 .uart_rxd(uart_rxd),
 .uart_txd(uart_txd),
 .rs485_de(rs485_de),
 .sample_ready(sample_ready),
 .sample_valid(sample_valid),
 .pv_raw(pv_raw),
 .sp_raw(sp_raw),
 .sv_raw(sv_raw),
 .op_raw(op_raw),
 .alarm(alarm),
 .control(control),
 .host_status(host_status),
 .online(online),
 .last_error(last_error),
 .exception_code(exception_code),
 .good_count(good_count),
 .error_count(error_count),
 .sample_ticks(sample_ticks),
 .now_ticks(now_ticks),.time_sync_valid(1'b1),.sample_time_sync(),
 .set_valid(set_valid),
 .set_ready(set_ready),
 .set_raw(set_raw),
 .set_rsp_valid(set_rsp_valid),
 .set_rsp_ready(set_rsp_ready),
 .set_result(set_result),
 .set_error(set_error),
 .set_exception(set_exception),
 .set_requested(set_requested),
 .set_readback(set_readback)
 );
endmodule
`default_nettype wire
