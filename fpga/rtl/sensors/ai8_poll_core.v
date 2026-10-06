`timescale 1ns/1ps
`default_nettype none
// AI-8 manual V9.6 section 7. Poll with FC03; only the selected SP may be
// written using FC10 and must then be read back. No run/control writes exist.
module ai8_poll_core #(
    parameter integer SYS_CLK_HZ = 25000000, SHARED_BUS = 0
)(
    input wire clk, input wire rst_n, input wire uart_rxd,
    input wire enable, input wire [31:0] baud_hz, input wire [7:0] slave_addr, channel,
    input wire [1:0] parity_mode, stop_bits, retry_limit,
    input wire [31:0] poll_interval_ms, input wire [15:0] timeout_ms,
    output wire bus_request, bus_busy, input wire bus_grant,
    output wire uart_txd, output wire rs485_de,
    input wire sample_ready, output reg sample_valid,
    output reg [15:0] pv_raw, output reg [15:0] sp_raw,
    output reg [15:0] sv_raw, output reg [15:0] op_raw,
    output reg [7:0] alarm, output reg [7:0] control,
    output reg [15:0] host_status, output reg online,
    output reg [3:0] last_error, output reg [7:0] exception_code,
    output reg [31:0] good_count, output reg [31:0] error_count,
    output reg [63:0] sample_ticks, input wire [63:0] now_ticks,
    input wire time_sync_valid, output reg sample_time_sync,
    input wire set_valid, output wire set_ready, input wire [15:0] set_raw,
    output reg set_rsp_valid, input wire set_rsp_ready,
    output reg [3:0] set_result, output reg [3:0] set_error,
    output reg [7:0] set_exception,
    output reg [15:0] set_requested, output reg [15:0] set_readback
);
    wire CONFIG_OK = SYS_CLK_HZ >= 1000 && baud_hz >= 4800 &&
        baud_hz <= 115200 && baud_hz <= SYS_CLK_HZ/16 &&
        slave_addr >= 1 && slave_addr <= 80 && channel >= 1 && channel <= 96 &&
        parity_mode >= 0 && parity_mode <= 1 && stop_bits >= 1 && stop_bits <= 2 &&
        poll_interval_ms >= 0 && timeout_ms >= 1 && timeout_ms <= 65535 &&
        retry_limit >= 0 && retry_limit <= 3;
    localparam START = 0, REQUEST = 1, RESPONSE = 2, HOLD = 3, GAP = 4,
        WRITE_REQ = 5, WRITE_RSP = 6, VERIFY_REQ = 7, VERIFY_RSP = 8;
    reg [3:0] state;
    reg [2:0] item;
    reg [31:0] ms_div, gap_ms;
    reg [15:0] pending_sp, pending_pv, pending_sv, pending_op;
    reg [7:0] pending_alarm, pending_control;
    reg [15:0] address;
    wire req_ready, done;
    wire [3:0] master_error;
    wire [7:0] master_exception;
    wire [255:0] read_data;
    wire [15:0] value = {read_data[7:0], read_data[15:8]};
    wire command_active = state == WRITE_REQ || state == WRITE_RSP ||
                          state == VERIFY_REQ || state == VERIFY_RSP;
    wire [15:0] selected_sp_address = channel - 1;
    // Invalid builds still consume commands and report CONFIG_ERROR; the
    // master remains disabled, so the command frontend cannot deadlock.
    assign set_ready = rst_n && enable && !set_rsp_valid && (state == START || state == GAP);
    always @* begin
        case (item)
            0: address = 16'h0000 + channel - 1;
            1: address = 16'h0600 + channel - 1;
            2: address = 16'h0480 + channel - 1;
            3: address = 16'h0360 + channel - 1;
            4: address = 16'h0680 + (channel - 1)/2;
            5: address = 16'h06c0 + (channel - 1)/2;
            default: address = 16'h0851;
        endcase
    end
    modbus_rtu_master #(.SYS_CLK_HZ(SYS_CLK_HZ),.SHARED_BUS(SHARED_BUS)) master (
        .sys_clk(clk), .rst_sys_n(rst_n), .enable(enable && CONFIG_OK),
        .baud_hz(baud_hz), .parity_mode(parity_mode[1:0]), .stop_bits(stop_bits[1:0]),
        .req_valid(state == REQUEST || state == WRITE_REQ || state == VERIFY_REQ), .req_ready(req_ready),
        .req_slave(slave_addr[7:0]), .req_function(state == WRITE_REQ ? 8'h10 : 8'h03),
        .req_address(command_active ? selected_sp_address : address),
        .req_quantity(5'd1), .req_write_data({240'd0, set_requested[7:0], set_requested[15:8]}),
        .timeout_ms(timeout_ms[15:0]), .retry_limit(retry_limit[1:0]),
        .timestamp_now(now_ticks), .time_sync_valid(1'b0), .done(done),
        .error(master_error), .exception_code(master_exception), .read_data(read_data),
        .response_timestamp(), .response_time_sync(), .attempt_error_pulse(), .attempt_error(),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd), .rs485_de(rs485_de), .busy(bus_busy), .bus_request(bus_request), .bus_grant(bus_grant)
    );
    always @(posedge clk) begin
        if (!rst_n || !enable) begin
            state <= START; item <= 0; ms_div <= 0; gap_ms <= 0;
            sample_valid <= 0; pv_raw <= 0; sp_raw <= 0; sv_raw <= 0; op_raw <= 0;
            alarm <= 0; control <= 0; host_status <= 0; online <= 0;
            last_error <= 0; exception_code <= 0; good_count <= 0; error_count <= 0;
            sample_ticks <= 0; sample_time_sync <= 0; pending_sp <= 0; pending_pv <= 0; pending_sv <= 0;
            pending_op <= 0; pending_alarm <= 0; pending_control <= 0;
            set_rsp_valid <= 0; set_result <= 0; set_error <= 0; set_exception <= 0;
            set_requested <= 0; set_readback <= 0;
        end else begin
            if (set_rsp_valid && set_rsp_ready) set_rsp_valid <= 0;
            // The gap clock starts at completion and runs through backpressure.
            if (state == HOLD || state == GAP) begin
                if (ms_div >= SYS_CLK_HZ/1000 - 1) begin
                    ms_div <= 0;
                    if (gap_ms < poll_interval_ms) gap_ms <= gap_ms + 1'b1;
                end else ms_div <= ms_div + 1'b1;
            end
            if (set_valid && set_ready) begin
                set_requested <= set_raw; set_readback <= 0;
                set_error <= 0; set_exception <= 0;
                if (!CONFIG_OK) begin
                    set_result <= 5; set_error <= 6; set_rsp_valid <= 1; state <= START;
                end else if ($signed(set_raw) < -9990 || $signed(set_raw) > 32000) begin
                    set_result <= 4; set_rsp_valid <= 1; state <= START;
                end else state <= WRITE_REQ;
            end else case (state)
                START: begin
                    item <= 0;
                    if (CONFIG_OK) state <= REQUEST;
                    else begin
                        sample_valid <= 1; online <= 0; last_error <= 6;
                        exception_code <= 0; error_count <= error_count + 1'b1;
                        sample_ticks <= now_ticks; sample_time_sync <= time_sync_valid;
                        ms_div <= 0; gap_ms <= 0; state <= HOLD;
                    end
                end
                REQUEST: if (req_ready) state <= RESPONSE;
                RESPONSE: if (done) begin
                    if (master_error != 0) begin
                        // Failed partial polls must never overwrite the previous snapshot.
                        online <= 0; last_error <= master_error; exception_code <= master_exception;
                        error_count <= error_count + 1'b1; sample_ticks <= now_ticks;
                        sample_time_sync <= time_sync_valid;
                        sample_valid <= 1; ms_div <= 0; gap_ms <= 0; state <= HOLD;
                    end else if (item == 6) begin
                        sp_raw <= pending_sp; pv_raw <= pending_pv; sv_raw <= pending_sv;
                        op_raw <= pending_op; alarm <= pending_alarm; control <= pending_control;
                        host_status <= value; online <= 1; last_error <= 0; exception_code <= 0;
                        good_count <= good_count + 1'b1; sample_ticks <= now_ticks;
                        sample_time_sync <= time_sync_valid;
                        sample_valid <= 1; ms_div <= 0; gap_ms <= 0; state <= HOLD;
                    end else begin
                        case (item)
                            0: pending_sp <= value;
                            1: pending_pv <= value;
                            2: pending_sv <= value;
                            3: pending_op <= value;
                            4: pending_alarm <= channel % 2 ? value[15:8] : value[7:0];
                            5: pending_control <= channel % 2 ? value[15:8] : value[7:0];
                        endcase
                        item <= item + 1'b1; state <= REQUEST;
                    end
                end
                HOLD: if (sample_ready) begin sample_valid <= 0; state <= GAP; end
                GAP: if (gap_ms >= poll_interval_ms) state <= START;
                WRITE_REQ: if (req_ready) state <= WRITE_RSP;
                WRITE_RSP: if (done) begin
                    if (master_error != 0) begin
                        set_result <= 1; set_error <= master_error; set_exception <= master_exception;
                        set_rsp_valid <= 1; state <= START;
                    end else state <= VERIFY_REQ;
                end
                VERIFY_REQ: if (req_ready) state <= VERIFY_RSP;
                VERIFY_RSP: if (done) begin
                    set_readback <= master_error == 0 ? value : 16'd0;
                    set_error <= master_error; set_exception <= master_exception;
                    if (master_error != 0) set_result <= 2;
                    else if (value != set_requested) set_result <= 3;
                    else set_result <= 0;
                    set_rsp_valid <= 1; state <= START;
                end
                default: state <= START;
            endcase
        end
    end
endmodule
`default_nettype wire
