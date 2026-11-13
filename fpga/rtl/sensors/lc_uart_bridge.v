`timescale 1ns/1ps
`default_nettype none
`include "register_map.vh"
`include "error_codes.vh"

// Raw LC TTL UART. Device commands remain host supplied; no automatic polling.
module lc_uart_bridge #(
    parameter integer SYS_CLK_HZ = 100000000,
    parameter integer FIFO_DEPTH = 256,
    parameter [31:0] BASE_ADDR = 32'h00006800,
    parameter [31:0] ID_VERSION = 32'h00480100
)(
    input wire sys_clk, rst_sys_n, system_enable,
    input wire rxd,
    output wire txd,
    input wire cfg_valid, cfg_write,
    input wire [31:0] cfg_addr, cfg_wdata,
    input wire [3:0] cfg_wstrb,
    output wire cfg_ready,
    output reg cfg_error,
    output reg [3:0] cfg_error_code,
    output reg [31:0] cfg_rdata,
    output wire [31:0] drop_count
);
    reg enabled, reset_pulse;
    reg [31:0] baud_hz, format, errors;
    reg [31:0] tx_count, rx_count, parity_count, framing_count, drops;
    reg [1:0] rx_error_pending;
    wire selected = cfg_valid && cfg_addr[31:8] == BASE_ADDR[31:8];
    wire [7:0] offset = cfg_addr[7:0];
    wire fire = selected && !cfg_error;
    wire write_fire = fire && cfg_write;
    wire reset_request = write_fire && offset == `REG_OFS_CONTROL &&
                         (cfg_wdata[1] || cfg_wdata[3]);
    wire engine_rst_n = rst_sys_n && !reset_pulse;
    wire active = enabled && system_enable && !reset_pulse;
    wire tx_valid, tx_ready, tx_space, tx_busy, tx_done;
    wire [7:0] tx_data;
    wire rx_valid, rx_space, rx_available, rx_busy, rx_start, parity_error, framing_error;
    wire [7:0] rx_data;
    wire [9:0] rx_head;
    wire [31:0] tx_level, rx_level;
    wire [1:0] byte_errors = rx_error_pending | {framing_error, parity_error};
    wire tx_push = write_fire && offset == `REG_LC_TX_DATA;
    wire rx_pop = fire && !cfg_write && offset == `REG_LC_RX_DATA;
    wire [31:0] event_errors = ((parity_error || framing_error) ? `ERR_DATA_FORMAT : 0) |
                               ((rx_valid && active && !rx_space) ? `ERR_FIFO_OVERFLOW : 0);
    wire [31:0] error_clear = write_fire && offset == `REG_OFS_ERROR ? cfg_wdata : 0;
    wire idle = !tx_busy && !rx_busy && tx_level == 0;
    wire control_flush = write_fire && offset == `REG_OFS_CONTROL &&
                         enabled && !cfg_wdata[0];
    assign cfg_ready = selected;
    assign drop_count = drops;

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_tx_fifo (
        .clk(sys_clk), .rst_n(engine_rst_n), .s_valid(tx_push), .s_ready(tx_space),
        .s_data(cfg_wdata[7:0]), .m_valid(tx_valid), .m_ready(tx_ready),
        .m_data(tx_data), .level(tx_level));
    sync_fifo #(.WIDTH(10), .DEPTH(FIFO_DEPTH)) u_rx_fifo (
        .clk(sys_clk), .rst_n(engine_rst_n), .s_valid(rx_valid && active), .s_ready(rx_space),
        .s_data({byte_errors, rx_data}), .m_valid(rx_available), .m_ready(rx_pop),
        .m_data(rx_head), .level(rx_level));
    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_tx (
        .sys_clk(sys_clk), .rst_sys_n(engine_rst_n), .enable(active), .baud_hz(baud_hz),
        .data_bits(format[3:0]), .parity_mode(format[5:4]), .stop_bits(format[9:8]),
        .byte_valid(tx_valid), .byte_ready(tx_ready), .byte_data(tx_data),
        .txd(txd), .busy(tx_busy), .frame_done_pulse(tx_done));
    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_rx (
        .sys_clk(sys_clk), .rst_sys_n(engine_rst_n), .enable(active), .baud_hz(baud_hz),
        .data_bits(format[3:0]), .parity_mode(format[5:4]), .stop_bits(format[9:8]),
        .rxd(rxd), .byte_valid(rx_valid), .byte_ready(1'b1), .byte_data(rx_data),
        .byte_start_pulse(rx_start), .framing_error_pulse(framing_error),
        .parity_error_pulse(parity_error), .busy(rx_busy));

    always @* begin
        cfg_rdata = 0;
        cfg_error = 0;
        cfg_error_code = 0;
        case (offset)
            `REG_OFS_ID_VERSION: cfg_rdata = ID_VERSION;
            `REG_OFS_CONTROL: cfg_rdata = {31'd0, enabled};
            `REG_OFS_STATUS: begin
                cfg_rdata[0] = active;
                cfg_rdata[1] = active && tx_space;
                cfg_rdata[3] = !idle;
                // Raw UART cannot infer whether a physical LC is online.
                cfg_rdata[5] = rx_level >= FIFO_DEPTH-2;
                cfg_rdata[6] = errors[2];
                cfg_rdata[7] = |errors;
                cfg_rdata[9] = rx_available;
                cfg_rdata[10] = !tx_space;
            end
            `REG_OFS_ERROR: cfg_rdata = errors;
            `REG_LC_BAUD: cfg_rdata = baud_hz;
            `REG_LC_FORMAT: cfg_rdata = format;
            `REG_LC_TX_DATA: cfg_rdata = 0;
            `REG_LC_RX_DATA: begin
                if (rx_available) cfg_rdata = {22'd0, rx_head};
                else begin cfg_error = 1; cfg_error_code = 11; end
            end
            `REG_LC_TX_LEVEL: cfg_rdata = tx_level;
            `REG_LC_RX_LEVEL: cfg_rdata = rx_level;
            `REG_LC_TX_COUNT: cfg_rdata = tx_count;
            `REG_LC_RX_COUNT: cfg_rdata = rx_count;
            `REG_LC_DROP_COUNT: cfg_rdata = drops;
            `REG_LC_PARITY_COUNT: cfg_rdata = parity_count;
            `REG_LC_FRAMING_COUNT: cfg_rdata = framing_count;
            `REG_LC_FIFO_DEPTH: cfg_rdata = FIFO_DEPTH;
            default: begin cfg_error = 1; cfg_error_code = 5; end
        endcase
        if (selected && cfg_addr[1:0] != 0) begin cfg_error = 1; cfg_error_code = 5; end
        else if (selected && cfg_write) begin
            // Write validation is independent of read side effects/empty state.
            cfg_error = 0; cfg_error_code = 0;
            case (offset)
                `REG_OFS_CONTROL: begin
                    if (cfg_wstrb != 15 || (cfg_wdata & ~32'hb) != 0)
                        begin cfg_error = 1; cfg_error_code = 7; end
                end
                `REG_OFS_ERROR: if (cfg_wstrb != 15)
                    begin cfg_error = 1; cfg_error_code = 7; end
                `REG_LC_BAUD, `REG_LC_FORMAT: begin
                    if (enabled || !idle || reset_pulse) begin cfg_error = 1; cfg_error_code = 8; end
                    else if (cfg_wstrb != 15) begin cfg_error = 1; cfg_error_code = 7; end
                    else if (offset == `REG_LC_BAUD && (cfg_wdata < 300 || cfg_wdata > SYS_CLK_HZ/16))
                        begin cfg_error = 1; cfg_error_code = 7; end
                    else if (offset == `REG_LC_FORMAT &&
                        ((cfg_wdata & ~32'h33f) != 0 ||
                         (cfg_wdata[3:0] != 7 && cfg_wdata[3:0] != 8) ||
                         cfg_wdata[5:4] > 2 ||
                         (cfg_wdata[9:8] != 1 && cfg_wdata[9:8] != 2)))
                        begin cfg_error = 1; cfg_error_code = 7; end
                end
                `REG_LC_TX_DATA: begin
                    if (cfg_wstrb != 15 || cfg_wdata > 255)
                        begin cfg_error = 1; cfg_error_code = 7; end
                    else if (!active) begin cfg_error = 1; cfg_error_code = 11; end
                    else if (!tx_space) begin cfg_error = 1; cfg_error_code = 8; end
                end
                `REG_OFS_ID_VERSION, `REG_OFS_STATUS, `REG_LC_RX_DATA,
                `REG_LC_TX_LEVEL, `REG_LC_RX_LEVEL, `REG_LC_TX_COUNT,
                `REG_LC_RX_COUNT, `REG_LC_DROP_COUNT, `REG_LC_PARITY_COUNT,
                `REG_LC_FRAMING_COUNT, `REG_LC_FIFO_DEPTH:
                    begin cfg_error = 1; cfg_error_code = 6; end
                default: begin cfg_error = 1; cfg_error_code = 5; end
            endcase
        end
    end

    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            enabled <= 0; reset_pulse <= 0;
            baud_hz <= 115200; format <= 32'h108;
            errors <= 0; tx_count <= 0; rx_count <= 0;
            parity_count <= 0; framing_count <= 0; drops <= 0; rx_error_pending <= 0;
        end else begin
            reset_pulse <= reset_request || control_flush || (enabled && !system_enable);
            errors <= (errors & ~error_clear) | event_errors;
            if (write_fire) case (offset)
                `REG_OFS_CONTROL: enabled <= cfg_wdata[0] && !cfg_wdata[1];
                `REG_LC_BAUD: baud_hz <= cfg_wdata;
                `REG_LC_FORMAT: format <= cfg_wdata;
                default: begin end
            endcase
            if (tx_done) tx_count <= tx_count + 1'b1;
            if (rx_valid && active) begin
                rx_count <= rx_count + 1'b1;
                if (!rx_space) drops <= drops + 1'b1;
            end
            if (parity_error) parity_count <= parity_count + 1'b1;
            if (framing_error) framing_count <= framing_count + 1'b1;
            if (rx_start || reset_pulse || (rx_valid && active)) rx_error_pending <= 0;
            else rx_error_pending <= byte_errors;
            if (reset_request && cfg_wdata[1]) begin
                errors <= 0; tx_count <= 0; rx_count <= 0;
                drops <= 0; parity_count <= 0; framing_count <= 0;
            end
        end
    end
endmodule
`default_nettype wire
