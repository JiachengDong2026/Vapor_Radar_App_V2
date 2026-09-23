`include "sensor_cfg_codes.vh"
`timescale 1ns/1ps

`include "project_defs.vh"
`include "register_map.vh"
`include "error_codes.vh"

module ptb210_rs232 #(
    parameter integer SYS_CLK_HZ = 100_000_000,
    parameter integer FIFO_DEPTH = 256,
    parameter integer AUTO_INIT = 1,
    parameter integer BOOT_DELAY_MS = 2000,
    parameter integer RESET_DELAY_MS = 2000,
    parameter integer RECOVERY_SILENCE_MS = 5
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,

    input  wire        uart_rxd,
    output wire        uart_txd,

    input  wire [63:0] timestamp_now,
    input  wire        time_sync_valid,
    input  wire [31:0] time_sync_seq,

    input  wire        cfg_valid,
    input  wire        cfg_write,
    input  wire [31:0] cfg_addr,
    input  wire [31:0] cfg_wdata,
    input  wire [3:0]  cfg_wstrb,
    output wire        cfg_ready,
    output wire [31:0] cfg_rdata,
    output wire        cfg_error,

    output wire        m_valid,
    input  wire        m_ready,
    output wire [31:0] m_data,
    output wire [3:0]  m_keep,
    output wire        m_sof,
    output wire        m_last,
    output wire [15:0] m_source_id,
    output wire [15:0] m_msg_id,
    output wire [63:0] m_timestamp,
    output wire [31:0] m_cycle_id,
    output wire [31:0] m_flags,
    output wire monitor_online,
    output wire [31:0] monitor_errors, monitor_drop_count, monitor_fifo_level,
    output reg [3:0] cfg_error_code
);
    localparam integer MS_DIV = SYS_CLK_HZ / 1000;
    localparam integer FIFO_AFULL_THRESHOLD = (FIFO_DEPTH > 16) ?
                                               (FIFO_DEPTH-16) : (FIFO_DEPTH-1);
    localparam [4:0] ST_DISABLED   = 5'd0;
    localparam [4:0] ST_BOOT_WAIT  = 5'd1;
    localparam [4:0] ST_SEND_FORM  = 5'd2;
    localparam [4:0] ST_SEND_RESET = 5'd3;
    localparam [4:0] ST_RESET_WAIT = 5'd4;
    localparam [4:0] ST_POLL_WAIT  = 5'd5;
    localparam [4:0] ST_SEND_POLL  = 5'd6;
    localparam [4:0] ST_SEND_BP    = 5'd7;
    localparam [4:0] ST_WAIT_RESP  = 5'd8;
    localparam [4:0] ST_RECOVER    = 5'd9;
    localparam [4:0] ST_FINALIZE   = 5'd10;
    localparam [4:0] ST_SEND_STOP  = 5'd11;
    localparam [4:0] ST_STOP_DRAIN = 5'd12;

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strobe;
        integer i;
        begin
            apply_wstrb = old_value;
            for (i = 0; i < 4; i = i + 1)
                if (strobe[i])
                    apply_wstrb[i*8 +: 8] = new_value[i*8 +: 8];
        end
    endfunction

    function [31:0] masked_wdata;
        input [31:0] value;
        input [3:0]  strobe;
        integer i;
        begin
            masked_wdata = 32'd0;
            for (i = 0; i < 4; i = i + 1)
                if (strobe[i])
                    masked_wdata[i*8 +: 8] = value[i*8 +: 8];
        end
    endfunction

    function [7:0] command_byte;
        input [4:0] command_state;
        input [3:0] index;
        begin
            command_byte = 8'h0D;
            case (command_state)
                ST_SEND_FORM: begin
                    case (index)
                        4'd0: command_byte = ".";
                        4'd1: command_byte = "F";
                        4'd2: command_byte = "O";
                        4'd3: command_byte = "R";
                        4'd4: command_byte = "M";
                        4'd5: command_byte = ".";
                        4'd6: command_byte = "0";
                        default: command_byte = 8'h0D;
                    endcase
                end
                ST_SEND_RESET: begin
                    case (index)
                        4'd0: command_byte = ".";
                        4'd1: command_byte = "R";
                        4'd2: command_byte = "E";
                        4'd3: command_byte = "S";
                        4'd4: command_byte = "E";
                        4'd5: command_byte = "T";
                        default: command_byte = 8'h0D;
                    endcase
                end
                ST_SEND_BP: begin
                    case (index)
                        4'd0: command_byte = ".";
                        4'd1: command_byte = "B";
                        4'd2: command_byte = "P";
                        default: command_byte = 8'h0D;
                    endcase
                end
                default: begin
                    case (index)
                        4'd0: command_byte = ".";
                        4'd1: command_byte = "P";
                        default: command_byte = 8'h0D;
                    endcase
                end
            endcase
        end
    endfunction

    function [3:0] command_last_index;
        input [4:0] command_state;
        begin
            case (command_state)
                ST_SEND_FORM:  command_last_index = 4'd7;
                ST_SEND_RESET: command_last_index = 4'd6;
                ST_SEND_BP:    command_last_index = 4'd3;
                default:       command_last_index = 4'd2;
            endcase
        end
    endfunction

    function [31:0] pressure_mpa_magnitude;
        input [31:0] whole_hpa;
        input [31:0] fractional_mpa;
        reg [63:0] scaled;
        begin
            scaled = whole_hpa * 64'd100000 + fractional_mpa;
            pressure_mpa_magnitude = scaled[31:0];
        end
    endfunction

    reg        enable_reg;
    reg [31:0] baud_reg;
    reg [31:0] uart_format_reg;
    reg [31:0] poll_interval_ms_reg;
    reg [31:0] mode_reg;
    reg [31:0] timeout_ms_reg;
    reg [31:0] error_reg;
    reg [31:0] last_pressure_mpa_reg;
    reg [31:0] rx_frame_count_reg;
    reg [31:0] parse_error_count_reg;
    reg [31:0] drop_count_reg;
    reg [31:0] timeout_count_reg;
    reg        online_reg;
    reg        overflow_since_last;
    reg        continuous_active, response_sync, finalize_sync;

    reg [4:0]  state;
    reg [3:0]  command_index;
    reg [31:0] ms_div_count;
    reg [31:0] wait_elapsed_ms;
    reg [31:0] poll_elapsed_ms;
    reg [31:0] response_elapsed_ms;
    reg        response_started;
    reg [63:0] response_timestamp;

    reg [5:0]  frame_length;
    reg        parse_invalid;
    reg        parse_negative;
    reg        sign_seen;
    reg        have_digit;
    reg        decimal_seen;
    reg        number_done;
    reg [2:0]  fractional_digits;
    reg [31:0] whole_value;
    reg [31:0] fractional_value;
    reg [31:0] finalize_magnitude;
    reg        finalize_negative;
    reg [63:0] finalize_timestamp;

    reg        record_pending;
    reg [1:0]  record_index;
    reg [31:0] record_pressure;
    reg [63:0] record_timestamp;
    reg [31:0] record_flags;

    wire cfg_hit = (cfg_addr[31:8] == 24'h000060);
    wire cfg_access = cfg_valid && cfg_hit;
    wire [7:0] cfg_offset = cfg_addr[7:0];
    wire [31:0] merged_control = apply_wstrb({31'd0, enable_reg}, cfg_wdata, cfg_wstrb);
    wire [31:0] merged_baud = apply_wstrb(baud_reg, cfg_wdata, cfg_wstrb);
    wire [31:0] merged_format = apply_wstrb(uart_format_reg, cfg_wdata, cfg_wstrb);
    wire [31:0] merged_poll = apply_wstrb(poll_interval_ms_reg, cfg_wdata, cfg_wstrb);
    wire [31:0] merged_mode = apply_wstrb(mode_reg, cfg_wdata, cfg_wstrb);
    wire [31:0] merged_timeout = apply_wstrb(timeout_ms_reg, cfg_wdata, cfg_wstrb);
    wire [31:0] clear_error_mask = masked_wdata(cfg_wdata, cfg_wstrb);

    reg [31:0] cfg_rdata_reg;
    reg        cfg_error_reg;
    wire cfg_write_fire = cfg_access && cfg_write && !cfg_error_reg;
    wire soft_reset_req = cfg_write_fire && (cfg_offset == `REG_OFS_CONTROL) &&
                          cfg_wstrb[0] && cfg_wdata[`CTRL_BIT_SOFT_RESET];
    wire clear_fifo_req = cfg_write_fire && (cfg_offset == `REG_OFS_CONTROL) &&
                          cfg_wstrb[0] && cfg_wdata[`CTRL_BIT_CLEAR_FIFO];

    wire [3:0] uart_data_bits = uart_format_reg[3:0];
    wire [1:0] uart_parity_mode = uart_format_reg[5:4];
    wire [1:0] uart_stop_bits = uart_format_reg[7:6];

    wire tx_byte_ready;
    wire tx_busy;
    wire tx_frame_done;
    wire tx_byte_valid = (state == ST_SEND_FORM) || (state == ST_SEND_RESET) ||
                         (state == ST_SEND_POLL) || (state == ST_SEND_BP) || (state == ST_SEND_STOP);
    wire [7:0] tx_byte_data = state==ST_SEND_STOP ? 8'h0d : command_byte(state, command_index);

    wire rx_byte_valid;
    wire [7:0] rx_byte_data;
    wire rx_byte_start;
    wire rx_frame_error;
    wire rx_parity_error;
    wire rx_busy;
    wire rx_byte_ready = enable_reg;

    wire ms_tick = (ms_div_count >= MS_DIV-1);
    wire [31:0] parsed_magnitude = pressure_mpa_magnitude(
        whole_value, fractional_value);

    wire fifo_s_valid = record_pending;
    wire fifo_s_ready;
    reg [31:0] fifo_s_data;
    wire fifo_s_sof = (record_index == 2'd0);
    wire fifo_s_last = (record_index == 2'd2);
    wire fifo_full;
    wire fifo_almost_full;
    wire [31:0] fifo_level;
    wire fifo_full_stall;
    wire fifo_rst_n = rst_sys_n && !soft_reset_req && !clear_fifo_req;

    always @* begin
        case (record_index)
            2'd0: fifo_s_data = 32'h0001_0001;
            2'd1: fifo_s_data = 32'h0407_0012;
            default: fifo_s_data = record_pressure;
        endcase
    end

    always @* begin
        cfg_rdata_reg = 32'd0;
        cfg_error_reg = 1'b0;
        if (cfg_access) begin
            case (cfg_offset)
                `REG_OFS_ID_VERSION: begin
                    cfg_rdata_reg = 32'h0040_0100;
                    if (cfg_write)
                        cfg_error_reg = 1'b1;
                end
                `REG_OFS_CONTROL: begin
                    cfg_rdata_reg = {31'd0, enable_reg};
                    if(cfg_write && (merged_control & 32'hfffffff0)!=0)cfg_error_reg=1;
                end
                `REG_OFS_STATUS: begin
                    cfg_rdata_reg[`STATUS_BIT_ENABLED] = enable_reg;
                    cfg_rdata_reg[`STATUS_BIT_READY] = 1'b1;
                    cfg_rdata_reg[`STATUS_BIT_BUSY] = tx_busy || rx_busy ||
                                                      (state != ST_POLL_WAIT);
                    cfg_rdata_reg[`STATUS_BIT_ONLINE] = online_reg;
                    cfg_rdata_reg[`STATUS_BIT_FIFO_AFULL] = fifo_almost_full;
                    cfg_rdata_reg[`STATUS_BIT_OVERFLOW] = error_reg[`ERR_BIT_FIFO_OVERFLOW];
                    cfg_rdata_reg[`STATUS_BIT_ERROR] = |error_reg;
                    cfg_rdata_reg[`STATUS_BIT_TIME_SYNC] = time_sync_valid;
                    if (cfg_write)
                        cfg_error_reg = 1'b1;
                end
                `REG_OFS_ERROR:
                    cfg_rdata_reg = error_reg;
                `REG_PTB_BAUD: begin
                    cfg_rdata_reg = baud_reg;
                    if (cfg_write && (enable_reg || tx_busy || (merged_baud < 32'd1200) ||
                                      (merged_baud > 32'd19200)))
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_UART_FORMAT: begin
                    cfg_rdata_reg = uart_format_reg;
                    if (cfg_write && (enable_reg || tx_busy || !(((merged_format[3:0] == 4'd7) ||
                                        (merged_format[3:0] == 4'd8)) &&
                                       (merged_format[5:4] <= 2'd2) &&
                                       ((merged_format[7:6] == 2'd1) ||
                                        (merged_format[7:6] == 2'd2)) &&
                                       (merged_format[31:8] == 0))))
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_POLL_INTERVAL_MS: begin
                    cfg_rdata_reg = poll_interval_ms_reg;
                    if (cfg_write && ((merged_poll == 0) ||
                                      (merged_poll > 32'd3_600_000)))
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_MODE: begin
                    cfg_rdata_reg = mode_reg;
                    if (cfg_write && (merged_mode > 1))
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_LAST_PRESSURE_MPA: begin
                    cfg_rdata_reg = last_pressure_mpa_reg;
                    if (cfg_write)
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_RX_FRAME_COUNT: begin
                    cfg_rdata_reg = rx_frame_count_reg;
                    if (cfg_write)
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_PARSE_ERROR_COUNT: begin
                    cfg_rdata_reg = parse_error_count_reg;
                    if (cfg_write)
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_TIMEOUT_MS: begin
                    cfg_rdata_reg = timeout_ms_reg;
                    if (cfg_write && ((merged_timeout == 0) ||
                                      (merged_timeout > 32'd600_000)))
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_DEVICE_ID_HASH: begin
                    cfg_rdata_reg = 32'd0;
                    if (cfg_write)
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_FIFO_LEVEL: begin
                    cfg_rdata_reg = fifo_level;
                    if (cfg_write)
                        cfg_error_reg = 1'b1;
                end
                `REG_PTB_DROP_COUNT: begin
                    cfg_rdata_reg = drop_count_reg;
                    if (cfg_write)
                        cfg_error_reg = 1'b1;
                end
                default: cfg_error_reg = 1'b1;
            endcase
        end
    end

    assign cfg_ready = cfg_access;
    assign cfg_rdata = cfg_rdata_reg;
    assign cfg_error = cfg_access && cfg_error_reg;

    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_uart_tx (
        .sys_clk(sys_clk),
        .rst_sys_n(rst_sys_n),
        .enable(1'b1),
        .baud_hz(baud_reg),
        .data_bits(uart_data_bits),
        .parity_mode(uart_parity_mode),
        .stop_bits(uart_stop_bits),
        .byte_valid(tx_byte_valid),
        .byte_ready(tx_byte_ready),
        .byte_data(tx_byte_data),
        .txd(uart_txd),
        .busy(tx_busy),
        .frame_done_pulse(tx_frame_done)
    );

    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_uart_rx (
        .sys_clk(sys_clk),
        .rst_sys_n(rst_sys_n),
        .enable(enable_reg),
        .baud_hz(baud_reg),
        .data_bits(uart_data_bits),
        .parity_mode(uart_parity_mode),
        .stop_bits(uart_stop_bits),
        .rxd(uart_rxd),
        .byte_valid(rx_byte_valid),
        .byte_ready(rx_byte_ready),
        .byte_data(rx_byte_data),
        .byte_start_pulse(rx_byte_start),
        .framing_error_pulse(rx_frame_error),
        .parity_error_pulse(rx_parity_error),
        .busy(rx_busy)
    );

    msg_stream_fifo #(
        .DEPTH(FIFO_DEPTH),
        .ALMOST_FULL_THRESHOLD(FIFO_AFULL_THRESHOLD)
    ) u_output_fifo (
        .clk(sys_clk),
        .rst_n(fifo_rst_n),
        .s_valid(fifo_s_valid),
        .s_ready(fifo_s_ready),
        .s_data(fifo_s_data),
        .s_keep(4'hF),
        .s_sof(fifo_s_sof),
        .s_last(fifo_s_last),
        .s_source_id(`SRC_PTB210),
        .s_msg_id(`MSG_SENSOR_TLV_RECORD),
        .s_timestamp(record_timestamp),
        .s_cycle_id(`CYCLE_ID_NONE),
        .s_flags(record_flags),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data(m_data),
        .m_keep(m_keep),
        .m_sof(m_sof),
        .m_last(m_last),
        .m_source_id(m_source_id),
        .m_msg_id(m_msg_id),
        .m_timestamp(m_timestamp),
        .m_cycle_id(m_cycle_id),
        .m_flags(m_flags),
        .full(fifo_full),
        .almost_full(fifo_almost_full),
        .level(fifo_level),
        .full_stall_pulse(fifo_full_stall)
    );

    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            enable_reg            <= 1'b0;
            baud_reg              <= 32'd9600;
            uart_format_reg       <= 32'h0000_0057;
            poll_interval_ms_reg  <= 32'd1000;
            mode_reg              <= 32'd0;
            timeout_ms_reg        <= 32'd1500;
            error_reg             <= 32'd0;
            last_pressure_mpa_reg <= 32'd0;
            rx_frame_count_reg    <= 32'd0;
            parse_error_count_reg <= 32'd0;
            drop_count_reg        <= 32'd0;
            timeout_count_reg     <= 32'd0;
            online_reg            <= 1'b0;
            overflow_since_last   <= 1'b0;
            continuous_active     <= 1'b0;
            response_sync         <= 1'b0;
            finalize_sync         <= 1'b0;
            state                 <= ST_DISABLED;
            command_index         <= 4'd0;
            ms_div_count          <= 32'd0;
            wait_elapsed_ms       <= 32'd0;
            poll_elapsed_ms       <= 32'd0;
            response_elapsed_ms   <= 32'd0;
            response_started      <= 1'b0;
            response_timestamp    <= 64'd0;
            frame_length          <= 6'd0;
            parse_invalid         <= 1'b0;
            parse_negative        <= 1'b0;
            sign_seen             <= 1'b0;
            have_digit            <= 1'b0;
            decimal_seen          <= 1'b0;
            number_done           <= 1'b0;
            fractional_digits     <= 3'd0;
            whole_value           <= 32'd0;
            fractional_value      <= 32'd0;
            finalize_magnitude    <= 32'd0;
            finalize_negative     <= 1'b0;
            finalize_timestamp    <= 64'd0;
            record_pending        <= 1'b0;
            record_index          <= 2'd0;
            record_pressure       <= 32'd0;
            record_timestamp      <= 64'd0;
            record_flags          <= 32'd0;
        end else begin
            if (ms_tick)
                ms_div_count <= 32'd0;
            else
                ms_div_count <= ms_div_count + 1'b1;

            if (cfg_access && cfg_write && cfg_error_reg)
                error_reg[`ERR_BIT_CONFIG_RANGE] <= 1'b1;

            if (cfg_write_fire) begin
                case (cfg_offset)
                    `REG_OFS_CONTROL:
                        enable_reg <= merged_control[`CTRL_BIT_ENABLE];
                    `REG_OFS_ERROR:
                        error_reg <= error_reg & ~clear_error_mask;
                    `REG_PTB_BAUD:
                        baud_reg <= merged_baud;
                    `REG_PTB_UART_FORMAT:
                        uart_format_reg <= merged_format;
                    `REG_PTB_POLL_INTERVAL_MS:
                        poll_interval_ms_reg <= merged_poll;
                    `REG_PTB_MODE:
                        mode_reg <= merged_mode;
                    `REG_PTB_TIMEOUT_MS:
                        timeout_ms_reg <= merged_timeout;
                    default: begin end
                endcase
            end

            if (soft_reset_req) begin
                state                 <= ST_DISABLED;
                command_index         <= 4'd0;
                online_reg            <= 1'b0;
                error_reg             <= 32'd0;
                rx_frame_count_reg    <= 32'd0;
                parse_error_count_reg <= 32'd0;
                drop_count_reg        <= 32'd0;
                timeout_count_reg     <= 32'd0;
                record_pending        <= 1'b0;
                response_started      <= 1'b0;
            end else if (clear_fifo_req) begin
                record_pending <= 1'b0;
                record_index <= 2'd0;
            end

            if (record_pending && fifo_s_ready) begin
                if (record_index == 2'd2) begin
                    record_pending <= 1'b0;
                    record_index <= 2'd0;
                end else begin
                    record_index <= record_index + 1'b1;
                end
            end

            if (rx_frame_error || rx_parity_error) begin
                error_reg[`ERR_BIT_PROTOCOL_OR_CRC] <= 1'b1;
                if(state==ST_WAIT_RESP)parse_invalid<=1;
            end

            if (!soft_reset_req) begin
                case (state)
                    ST_DISABLED: begin
                        command_index <= 4'd0;
                        wait_elapsed_ms <= 32'd0;
                        poll_elapsed_ms <= 32'd0;
                        response_elapsed_ms <= 32'd0;
                        response_started <= 1'b0;
                        frame_length<=0;parse_invalid<=0;parse_negative<=0;sign_seen<=0;
                        have_digit<=0;decimal_seen<=0;number_done<=0;fractional_digits<=0;
                        whole_value<=0;fractional_value<=0;
                        if (enable_reg) begin
                            if (AUTO_INIT != 0)
                                state <= ST_BOOT_WAIT;
                            else
                                state <= ST_POLL_WAIT;
                        end
                    end

                    ST_BOOT_WAIT: begin
                        if (!enable_reg)
                            state <= ST_DISABLED;
                        else if (ms_tick) begin
                            if (wait_elapsed_ms + 1'b1 >= BOOT_DELAY_MS) begin
                                wait_elapsed_ms <= 32'd0;
                                command_index <= 4'd0;
                                state <= ST_SEND_FORM;
                            end else
                                wait_elapsed_ms <= wait_elapsed_ms + 1'b1;
                        end
                    end

                    ST_SEND_FORM: begin
                        if (!enable_reg)
                            state <= ST_DISABLED;
                        else if (tx_byte_valid && tx_byte_ready) begin
                            if (command_index >= command_last_index(state)) begin
                                command_index <= 4'd0;
                                state <= ST_SEND_RESET;
                            end else
                                command_index <= command_index + 1'b1;
                        end
                    end

                    ST_SEND_RESET: begin
                        if (!enable_reg)
                            state <= ST_DISABLED;
                        else if (tx_byte_valid && tx_byte_ready) begin
                            if (command_index >= command_last_index(state)) begin
                                command_index <= 4'd0;
                                wait_elapsed_ms <= 32'd0;
                                state <= ST_RESET_WAIT;
                            end else
                                command_index <= command_index + 1'b1;
                        end
                    end

                    ST_RESET_WAIT: begin
                        if (!enable_reg)
                            state <= ST_DISABLED;
                        else if (ms_tick) begin
                            if (wait_elapsed_ms + 1'b1 >= RESET_DELAY_MS) begin
                                wait_elapsed_ms <= 32'd0;
                                poll_elapsed_ms <= poll_interval_ms_reg;
                                state <= ST_POLL_WAIT;
                            end else
                                wait_elapsed_ms <= wait_elapsed_ms + 1'b1;
                        end
                    end

                    ST_POLL_WAIT: begin
                        if (!enable_reg)
                            state <= ST_DISABLED;
                        else if (mode_reg[0]) begin
                            command_index <= 4'd0;
                            state <= ST_SEND_BP;
                        end else if (ms_tick) begin
                            if (poll_elapsed_ms + 1'b1 >= poll_interval_ms_reg) begin
                                poll_elapsed_ms <= 32'd0;
                                command_index <= 4'd0;
                                state <= ST_SEND_POLL;
                            end else
                                poll_elapsed_ms <= poll_elapsed_ms + 1'b1;
                        end
                    end

                    ST_SEND_POLL, ST_SEND_BP: begin
                        if (!enable_reg)
                            state <= ST_DISABLED;
                        else if (tx_byte_valid && tx_byte_ready) begin
                            if (command_index >= command_last_index(state)) begin
                                if(state==ST_SEND_BP)continuous_active<=1;
                                command_index <= 4'd0;
                                response_elapsed_ms <= 32'd0;
                                response_started <= 1'b0;
                                state <= ST_WAIT_RESP;
                            end else
                                command_index <= command_index + 1'b1;
                        end
                    end

                    ST_WAIT_RESP: begin
                        if (!enable_reg)
                            state <= ST_DISABLED;
                        else if (ms_tick) begin
                            if (response_elapsed_ms + 1'b1 >= timeout_ms_reg) begin
                                response_elapsed_ms <= 32'd0;
                                response_started <= 1'b0;
                                frame_length <= 6'd0;
                                parse_invalid <= 1'b0;
                                parse_negative <= 1'b0;
                                sign_seen <= 1'b0;
                                have_digit <= 1'b0;
                                decimal_seen <= 1'b0;
                                number_done <= 1'b0;
                                fractional_digits <= 3'd0;
                                whole_value <= 32'd0;
                                fractional_value <= 32'd0;
                                timeout_count_reg <= timeout_count_reg + 1'b1;
                                error_reg[`ERR_BIT_TIMEOUT] <= 1'b1;
                                online_reg <= 1'b0;
                                wait_elapsed_ms <= 32'd0;
                                state <= ST_RECOVER;
                            end else
                                response_elapsed_ms <= response_elapsed_ms + 1'b1;
                        end
                    end

                    ST_SEND_STOP: if(tx_byte_ready)state<=ST_STOP_DRAIN;
                    ST_STOP_DRAIN: if(tx_frame_done)begin
                        continuous_active<=0;wait_elapsed_ms<=0;
                        state<=enable_reg?ST_RECOVER:ST_DISABLED;
                    end

                    ST_RECOVER: begin
                        if (!enable_reg)
                            state <= ST_DISABLED;
                        else if (rx_byte_valid) begin
                            wait_elapsed_ms <= 32'd0;
                        end else if (ms_tick) begin
                            if (wait_elapsed_ms + 1'b1 >= RECOVERY_SILENCE_MS) begin
                                wait_elapsed_ms <= 32'd0;
                                poll_elapsed_ms <= 32'd0;
                                state <= ST_POLL_WAIT;
                            end else
                                wait_elapsed_ms <= wait_elapsed_ms + 1'b1;
                        end
                    end

                    ST_FINALIZE: begin
                        if (!enable_reg) begin
                            state <= ST_DISABLED;
                        end else begin
                            if (!record_pending && (fifo_level <= FIFO_DEPTH-3)) begin
                                last_pressure_mpa_reg <= finalize_negative ?
                                                         (~finalize_magnitude + 1'b1) :
                                                         finalize_magnitude;
                                rx_frame_count_reg <= rx_frame_count_reg + 1'b1;
                                online_reg <= 1'b1;
                                record_pressure <= finalize_negative ?
                                                     (~finalize_magnitude + 1'b1) :
                                                     finalize_magnitude;
                                record_timestamp <= finalize_timestamp;
                                record_flags <= 32'h0000_0001 |
                                                (finalize_sync ? 32'h0000_0004 : 32'd0) |
                                                (overflow_since_last ? 32'h0000_0008 : 32'd0) |
                                                ((|error_reg) ? 32'h0000_0010 : 32'd0);
                                record_pending <= 1'b1;
                                record_index <= 2'd0;
                                overflow_since_last <= 1'b0;
                            end else begin
                                drop_count_reg <= drop_count_reg + 1'b1;
                                error_reg[`ERR_BIT_FIFO_OVERFLOW] <= 1'b1;
                                overflow_since_last <= 1'b1;
                            end
                            poll_elapsed_ms <= 32'd0;
                            state <= mode_reg[0] ? ST_WAIT_RESP : ST_POLL_WAIT;
                        end
                    end

                    default: state <= ST_DISABLED;
                endcase
            end

            if ((state == ST_WAIT_RESP) && rx_byte_start && !response_started) begin
                response_timestamp <= timestamp_now;
                response_sync <= time_sync_valid;
                response_started <= 1'b1;
            end

            if ((state == ST_WAIT_RESP) && rx_byte_valid && rx_byte_ready) begin
                if (rx_byte_data == 8'h0D) begin
                    if (have_digit && !parse_invalid && !rx_frame_error && !rx_parity_error && (whole_value <= 32'd15000)) begin
                        finalize_magnitude <= parsed_magnitude;
                        finalize_negative <= parse_negative;
                        finalize_timestamp <= response_started ? response_timestamp : timestamp_now;
                        finalize_sync <= response_started ? response_sync : time_sync_valid;
                        state <= ST_FINALIZE;
                    end else begin
                        parse_error_count_reg <= parse_error_count_reg + 1'b1;
                        error_reg[`ERR_BIT_DATA_FORMAT] <= 1'b1;
                        poll_elapsed_ms <= 32'd0;
                        if (!mode_reg[0])
                            state <= ST_POLL_WAIT;
                    end

                    frame_length <= 6'd0;
                    parse_invalid <= 1'b0;
                    parse_negative <= 1'b0;
                    sign_seen <= 1'b0;
                    have_digit <= 1'b0;
                    decimal_seen <= 1'b0;
                    number_done <= 1'b0;
                    fractional_digits <= 3'd0;
                    whole_value <= 32'd0;
                    fractional_value <= 32'd0;
                    response_started <= 1'b0;
                    response_elapsed_ms <= 32'd0;
                end else if (rx_byte_data != 8'h0A) begin
                    if (frame_length >= 6'd31)
                        parse_invalid <= 1'b1;
                    else
                        frame_length <= frame_length + 1'b1;

                    if ((rx_byte_data == " ") || (rx_byte_data == 8'h09)) begin
                        if (have_digit)
                            number_done <= 1'b1;
                    end else if ((rx_byte_data == "+") || (rx_byte_data == "-")) begin
                        if (have_digit || decimal_seen || sign_seen || number_done)
                            parse_invalid <= 1'b1;
                        else begin
                            sign_seen <= 1'b1;
                            parse_negative <= (rx_byte_data == "-");
                        end
                    end else if (rx_byte_data == ".") begin
                        if (decimal_seen || number_done)
                            parse_invalid <= 1'b1;
                        else
                            decimal_seen <= 1'b1;
                    end else if ((rx_byte_data >= "0") && (rx_byte_data <= "9")) begin
                        if (number_done)
                            parse_invalid <= 1'b1;
                        else begin
                            have_digit <= 1'b1;
                            if (decimal_seen) begin
                                if (fractional_digits >= 3'd5)
                                    parse_invalid <= 1'b1;
                                else begin
                                    case (fractional_digits)
                                        3'd0: fractional_value <= fractional_value +
                                                                  (rx_byte_data - "0") * 32'd10000;
                                        3'd1: fractional_value <= fractional_value +
                                                                  (rx_byte_data - "0") * 32'd1000;
                                        3'd2: fractional_value <= fractional_value +
                                                                  (rx_byte_data - "0") * 32'd100;
                                        3'd3: fractional_value <= fractional_value +
                                                                  (rx_byte_data - "0") * 32'd10;
                                        default: fractional_value <= fractional_value +
                                                                            (rx_byte_data - "0");
                                    endcase
                                    fractional_digits <= fractional_digits + 1'b1;
                                end
                            end else begin
                                if (whole_value > 32'd15000)
                                    parse_invalid <= 1'b1;
                                else
                                    whole_value <= whole_value * 10 +
                                                   (rx_byte_data - "0");
                            end
                        end
                    end else begin
                        parse_invalid <= 1'b1;
                    end
                end
            end
            // Stop continuous device output with CR before changing to polling or disable.
            if(!soft_reset_req && continuous_active && (!enable_reg || !mode_reg[0]) &&
                state!=ST_SEND_STOP && state!=ST_STOP_DRAIN)state<=ST_SEND_STOP;
        end
    end

    wire unused_time_sync_seq = ^time_sync_seq;
    wire unused_tx_done = tx_frame_done;
    wire unused_fifo_full = fifo_full;
    wire unused_fifo_stall = fifo_full_stall;
    assign monitor_online=online_reg;
    assign monitor_errors=error_reg;
    assign monitor_drop_count=drop_count_reg;
    assign monitor_fifo_level=fifo_level;
    // Error reason is only meaningful on the accepted configuration response.
    // Address / read-only / range errors take precedence over temporary busy.
    always @* begin
        cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_ready && cfg_error)begin
            cfg_error_code=`SENSOR_CFG_RANGE;
            if(cfg_addr[1:0]!=0 || cfg_offset>8'h38)cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;
            else if(cfg_write)case(cfg_offset)
                8'h04,8'h0c,8'h18,8'h1c,8'h2c:;
                8'h10:if((enable_reg || tx_busy) && merged_baud>=1200 && merged_baud<=19200)
                    cfg_error_code=`SENSOR_CFG_BUSY;
                8'h14:if((enable_reg || tx_busy) &&
                    (merged_format[3:0]==7 || merged_format[3:0]==8) && merged_format[5:4]<=2 &&
                    (merged_format[7:6]==1 || merged_format[7:6]==2) && merged_format[31:8]==0)
                    cfg_error_code=`SENSOR_CFG_BUSY;
                default:cfg_error_code=`SENSOR_CFG_READ_ONLY;
            endcase
        end
    end

endmodule
