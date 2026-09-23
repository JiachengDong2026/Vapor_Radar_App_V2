`timescale 1ns/1ps

module uart_rx #(
    parameter integer SYS_CLK_HZ = 100_000_000
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,
    input  wire        enable,
    input  wire [31:0] baud_hz,
    input  wire [3:0]  data_bits,
    input  wire [1:0]  parity_mode,
    input  wire [1:0]  stop_bits,
    input  wire        rxd,
    output wire        byte_valid,
    input  wire        byte_ready,
    output wire [7:0]  byte_data,
    output wire        byte_start_pulse,
    output wire        framing_error_pulse,
    output wire        parity_error_pulse,
    output wire        busy
);
    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_START  = 3'd1;
    localparam [2:0] ST_DATA   = 3'd2;
    localparam [2:0] ST_PARITY = 3'd3;
    localparam [2:0] ST_STOP   = 3'd4;

    (* ASYNC_REG = "TRUE" *) reg rxd_meta;
    (* ASYNC_REG = "TRUE" *) reg rxd_sync;
    reg rxd_prev;
    reg [2:0] state;
    reg [32:0] sample_acc;
    reg [4:0] sample_count;
    reg [3:0] data_index;
    reg [1:0] stop_index;
    reg [7:0] data_shift;
    reg byte_valid_reg;
    reg [7:0] byte_data_reg;
    reg start_pulse_reg;
    reg framing_error_reg;
    reg parity_error_reg;

    wire [36:0] sample_rate_ext = {5'd0, baud_hz} << 4;
    wire [36:0] sample_step_ext = {4'd0, sample_acc} + sample_rate_ext;
    wire sample_tick = (state != ST_IDLE) && (baud_hz != 0) &&
                       (sample_step_ext >= SYS_CLK_HZ);
    wire falling_edge = rxd_prev && !rxd_sync;
    wire parity_enabled = (parity_mode == 2'd1) || (parity_mode == 2'd2);
    wire [3:0] effective_data_bits = (data_bits == 4'd7) ? 4'd7 : 4'd8;
    wire [1:0] effective_stop_bits = (stop_bits == 2'd2) ? 2'd2 : 2'd1;
    wire expected_even_parity = (effective_data_bits == 4'd7) ?
                                ^data_shift[6:0] : ^data_shift;
    wire expected_parity = (parity_mode == 2'd1) ?
                           expected_even_parity : ~expected_even_parity;

    assign byte_valid = byte_valid_reg;
    assign byte_data = byte_data_reg;
    assign byte_start_pulse = start_pulse_reg;
    assign framing_error_pulse = framing_error_reg;
    assign parity_error_pulse = parity_error_reg;
    assign busy = (state != ST_IDLE);

    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            rxd_meta <= 1'b1;
            rxd_sync <= 1'b1;
            rxd_prev <= 1'b1;
        end else begin
            rxd_meta <= rxd;
            rxd_sync <= rxd_meta;
            rxd_prev <= rxd_sync;
        end
    end

    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            state              <= ST_IDLE;
            sample_acc         <= 33'd0;
            sample_count       <= 5'd0;
            data_index         <= 4'd0;
            stop_index         <= 2'd0;
            data_shift         <= 8'd0;
            byte_valid_reg     <= 1'b0;
            byte_data_reg      <= 8'd0;
            start_pulse_reg    <= 1'b0;
            framing_error_reg  <= 1'b0;
            parity_error_reg   <= 1'b0;
        end else begin
            start_pulse_reg   <= 1'b0;
            framing_error_reg <= 1'b0;
            parity_error_reg  <= 1'b0;

            if (byte_valid_reg && byte_ready)
                byte_valid_reg <= 1'b0;

            if (!enable) begin
                state        <= ST_IDLE;
                sample_acc   <= 33'd0;
                sample_count <= 5'd0;
                data_index   <= 4'd0;
                stop_index   <= 2'd0;
            end else if (state == ST_IDLE) begin
                sample_acc <= 33'd0;
                if (falling_edge) begin
                    state           <= ST_START;
                    sample_count    <= 5'd0;
                    data_index      <= 4'd0;
                    stop_index      <= 2'd0;
                    data_shift      <= 8'd0;
                    start_pulse_reg <= 1'b1;
                end
            end else begin
                if (sample_tick)
                    sample_acc <= sample_step_ext - SYS_CLK_HZ;
                else
                    sample_acc <= sample_step_ext[32:0];

                if (sample_tick) begin
                    case (state)
                        ST_START: begin
                            if (sample_count == 5'd7) begin
                                sample_count <= 5'd0;
                                if (rxd_sync) begin
                                    state <= ST_IDLE;
                                end else begin
                                    state <= ST_DATA;
                                end
                            end else begin
                                sample_count <= sample_count + 1'b1;
                            end
                        end

                        ST_DATA: begin
                            if (sample_count == 5'd15) begin
                                sample_count <= 5'd0;
                                data_shift[data_index] <= rxd_sync;
                                if (data_index == effective_data_bits - 1'b1) begin
                                    data_index <= 4'd0;
                                    if (parity_enabled)
                                        state <= ST_PARITY;
                                    else begin
                                        stop_index <= 2'd0;
                                        state <= ST_STOP;
                                    end
                                end else begin
                                    data_index <= data_index + 1'b1;
                                end
                            end else begin
                                sample_count <= sample_count + 1'b1;
                            end
                        end

                        ST_PARITY: begin
                            if (sample_count == 5'd15) begin
                                sample_count <= 5'd0;
                                if (rxd_sync != expected_parity)
                                    parity_error_reg <= 1'b1;
                                stop_index <= 2'd0;
                                state <= ST_STOP;
                            end else begin
                                sample_count <= sample_count + 1'b1;
                            end
                        end

                        ST_STOP: begin
                            if (sample_count == 5'd15) begin
                                sample_count <= 5'd0;
                                if (!rxd_sync)
                                    framing_error_reg <= 1'b1;
                                if (stop_index + 1'b1 >= effective_stop_bits) begin
                                    if (!byte_valid_reg || byte_ready) begin
                                        byte_data_reg <= (effective_data_bits == 4'd7) ?
                                                         {1'b0, data_shift[6:0]} : data_shift;
                                        byte_valid_reg <= 1'b1;
                                    end
                                    state <= ST_IDLE;
                                end else begin
                                    stop_index <= stop_index + 1'b1;
                                end
                            end else begin
                                sample_count <= sample_count + 1'b1;
                            end
                        end

                        default: state <= ST_IDLE;
                    endcase
                end
            end
        end
    end
endmodule
