`timescale 1ns/1ps

module uart_tx #(
    parameter integer SYS_CLK_HZ = 100_000_000
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,
    input  wire        enable,
    input  wire [31:0] baud_hz,
    input  wire [3:0]  data_bits,
    input  wire [1:0]  parity_mode,
    input  wire [1:0]  stop_bits,
    input  wire        byte_valid,
    output wire        byte_ready,
    input  wire [7:0]  byte_data,
    output wire        txd,
    output wire        busy,
    output wire        frame_done_pulse
);
    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_START  = 3'd1;
    localparam [2:0] ST_DATA   = 3'd2;
    localparam [2:0] ST_PARITY = 3'd3;
    localparam [2:0] ST_STOP   = 3'd4;

    reg [2:0]  state;
    reg [32:0] baud_acc;
    reg [7:0]  data_latched;
    reg [3:0]  data_index;
    reg [1:0]  stop_index;
    reg        parity_latched;
    reg        txd_reg;
    reg        done_reg;

    wire [32:0] baud_step = {1'b0, baud_acc[31:0]} + {1'b0, baud_hz};
    wire baud_tick = (state != ST_IDLE) && (baud_hz != 0) &&
                     (baud_step >= SYS_CLK_HZ);
    wire parity_enabled = (parity_mode == 2'd1) || (parity_mode == 2'd2);
    wire [3:0] effective_data_bits = (data_bits == 4'd7) ? 4'd7 : 4'd8;
    wire [1:0] effective_stop_bits = (stop_bits == 2'd2) ? 2'd2 : 2'd1;

    assign byte_ready = enable && (state == ST_IDLE) && (baud_hz != 0);
    assign txd = txd_reg;
    assign busy = (state != ST_IDLE);
    assign frame_done_pulse = done_reg;

    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            state           <= ST_IDLE;
            baud_acc        <= 33'd0;
            data_latched    <= 8'd0;
            data_index      <= 4'd0;
            stop_index      <= 2'd0;
            parity_latched  <= 1'b0;
            txd_reg         <= 1'b1;
            done_reg        <= 1'b0;
        end else begin
            done_reg <= 1'b0;

            if (!enable) begin
                state      <= ST_IDLE;
                baud_acc   <= 33'd0;
                txd_reg    <= 1'b1;
                data_index <= 4'd0;
                stop_index <= 2'd0;
            end else if (state == ST_IDLE) begin
                baud_acc <= 33'd0;
                txd_reg  <= 1'b1;
                if (byte_valid && byte_ready) begin
                    data_latched   <= byte_data;
                    parity_latched <= (effective_data_bits == 4'd7) ?
                                      ^byte_data[6:0] : ^byte_data;
                    data_index     <= 4'd0;
                    stop_index     <= 2'd0;
                    txd_reg        <= 1'b0;
                    state          <= ST_START;
                end
            end else begin
                if (baud_tick)
                    baud_acc <= baud_step - SYS_CLK_HZ;
                else
                    baud_acc <= baud_step;

                if (baud_tick) begin
                    case (state)
                        ST_START: begin
                            txd_reg <= data_latched[0];
                            state <= ST_DATA;
                        end

                        ST_DATA: begin
                            if (data_index == effective_data_bits - 1'b1) begin
                                data_index <= 4'd0;
                                if (parity_enabled) begin
                                    txd_reg <= (parity_mode == 2'd1) ?
                                               parity_latched : ~parity_latched;
                                    state <= ST_PARITY;
                                end else begin
                                    txd_reg <= 1'b1;
                                    stop_index <= 2'd1;
                                    state <= ST_STOP;
                                end
                            end else begin
                                data_index <= data_index + 1'b1;
                                txd_reg <= data_latched[data_index + 1'b1];
                            end
                        end

                        ST_PARITY: begin
                            txd_reg <= 1'b1;
                            stop_index <= 2'd1;
                            state <= ST_STOP;
                        end

                        ST_STOP: begin
                            if (stop_index >= effective_stop_bits) begin
                                state <= ST_IDLE;
                                baud_acc <= 33'd0;
                                txd_reg <= 1'b1;
                                done_reg <= 1'b1;
                            end else begin
                                stop_index <= stop_index + 1'b1;
                                txd_reg <= 1'b1;
                            end
                        end

                        default: begin
                            state <= ST_IDLE;
                            txd_reg <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end
endmodule
