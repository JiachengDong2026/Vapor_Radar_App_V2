module ptb210_model #(
    parameter integer SYS_CLK_HZ = 10_000_000,
    parameter integer RESPONSE_DELAY_CLKS = 2000,
    parameter integer REPEAT_VALID = 0
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,
    input  wire        host_txd,
    output wire        host_rxd,
    output reg  [31:0] poll_count,
    output reg  [31:0] bp_count,
    output reg         form_seen,
    output reg         reset_seen
);
    wire cmd_valid;
    wire [7:0] cmd_data;
    wire cmd_start;
    wire cmd_frame_error;
    wire cmd_parity_error;
    wire cmd_busy;
    reg [7:0] cmd_mem [0:31];
    reg [5:0] cmd_length;

    reg response_pending;
    reg [2:0] response_kind;
    reg [5:0] response_index;
    reg [31:0] response_delay;
    wire response_tx_ready;
    wire response_tx_busy;
    wire response_tx_done;

    function [5:0] response_last_index;
        input [2:0] kind;
        begin
            case (kind)
                3'd1: response_last_index = 6'd8;
                3'd2: response_last_index = 6'd6;
                3'd3: response_last_index = 6'd6;
                3'd5: response_last_index = 6'd35;
                3'd6: response_last_index = 6'd6;
                default: response_last_index = 6'd7;
            endcase
        end
    endfunction

    function [7:0] response_byte;
        input [2:0] kind;
        input [5:0] index;
        begin
            response_byte = 8'h0D;
            case (kind)
                3'd1: begin
                    case (index)
                        0: response_byte = " ";
                        1: response_byte = "1";
                        2: response_byte = "0";
                        3: response_byte = "1";
                        4: response_byte = "2";
                        5: response_byte = ".";
                        6: response_byte = "9";
                        7: response_byte = "9";
                        default: response_byte = 8'h0D;
                    endcase
                end
                3'd2: begin
                    case (index)
                        0: response_byte = "-";
                        1: response_byte = "1";
                        2: response_byte = "2";
                        3: response_byte = ".";
                        4: response_byte = "3";
                        5: response_byte = "4";
                        default: response_byte = 8'h0D;
                    endcase
                end
                3'd3: begin
                    case (index)
                        0: response_byte = "1";
                        1: response_byte = "2";
                        2: response_byte = "A";
                        3: response_byte = ".";
                        4: response_byte = "3";
                        5: response_byte = "4";
                        default: response_byte = 8'h0D;
                    endcase
                end
                3'd5: begin
                    if (index < 35)
                        response_byte = "1";
                    else
                        response_byte = 8'h0D;
                end
                3'd6: begin
                    case (index)
                        0: response_byte = "9";
                        1: response_byte = "9";
                        2: response_byte = "9";
                        3: response_byte = ".";
                        4: response_byte = "0";
                        5: response_byte = "1";
                        default: response_byte = 8'h0D;
                    endcase
                end
                default: begin
                    case (index)
                        0: response_byte = "1";
                        1: response_byte = "0";
                        2: response_byte = "0";
                        3: response_byte = "0";
                        4: response_byte = ".";
                        5: response_byte = "0";
                        6: response_byte = "0";
                        default: response_byte = 8'h0D;
                    endcase
                end
            endcase
        end
    endfunction

    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_command_rx (
        .sys_clk(sys_clk), .rst_sys_n(rst_sys_n), .enable(1'b1),
        .baud_hz(32'd9600), .data_bits(4'd7), .parity_mode(2'd1),
        .stop_bits(2'd1), .rxd(host_txd), .byte_valid(cmd_valid),
        .byte_ready(1'b1), .byte_data(cmd_data),
        .byte_start_pulse(cmd_start),
        .framing_error_pulse(cmd_frame_error),
        .parity_error_pulse(cmd_parity_error), .busy(cmd_busy)
    );

    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_response_tx (
        .sys_clk(sys_clk), .rst_sys_n(rst_sys_n), .enable(1'b1),
        .baud_hz(32'd9600), .data_bits(4'd7), .parity_mode(2'd1),
        .stop_bits(2'd1), .byte_valid(response_pending && (response_delay == 0)),
        .byte_ready(response_tx_ready),
        .byte_data(response_byte(response_kind, response_index)),
        .txd(host_rxd), .busy(response_tx_busy),
        .frame_done_pulse(response_tx_done)
    );

    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            cmd_length <= 6'd0;
            poll_count <= 32'd0;
            bp_count <= 32'd0;
            form_seen <= 1'b0;
            reset_seen <= 1'b0;
            response_pending <= 1'b0;
            response_kind <= 3'd0;
            response_index <= 6'd0;
            response_delay <= 32'd0;
        end else begin
            if (response_pending && (response_delay != 0))
                response_delay <= response_delay - 1'b1;

            if (response_pending && (response_delay == 0) && response_tx_ready) begin
                if (response_index >= response_last_index(response_kind)) begin
                    response_pending <= 1'b0;
                    response_index <= 6'd0;
                end else begin
                    response_index <= response_index + 1'b1;
                end
            end

            if (cmd_valid) begin
                if (cmd_data == 8'h0D) begin
                    if ((cmd_length == 2) && (cmd_mem[0] == ".") &&
                        (cmd_mem[1] == "P")) begin
                        poll_count <= poll_count + 1'b1;
                        if (REPEAT_VALID != 0) begin
                            response_kind <= 3'd7;
                            response_index <= 6'd0;
                            response_delay <= RESPONSE_DELAY_CLKS;
                            response_pending <= 1'b1;
                        end else if ((poll_count + 1'b1) != 4) begin
                            response_kind <= poll_count + 1'b1;
                            response_index <= 6'd0;
                            response_delay <= RESPONSE_DELAY_CLKS;
                            response_pending <= 1'b1;
                        end
                    end else if ((cmd_length == 3) && (cmd_mem[0] == ".") &&
                                 (cmd_mem[1] == "B") && (cmd_mem[2] == "P")) begin
                        bp_count <= bp_count + 1'b1;
                        response_kind <= 3'd7;
                        response_index <= 6'd0;
                        response_delay <= RESPONSE_DELAY_CLKS;
                        response_pending <= 1'b1;
                    end else if ((cmd_length == 7) && (cmd_mem[0] == ".") &&
                                 (cmd_mem[1] == "F") && (cmd_mem[2] == "O") &&
                                 (cmd_mem[3] == "R") && (cmd_mem[4] == "M") &&
                                 (cmd_mem[5] == ".") && (cmd_mem[6] == "0")) begin
                        form_seen <= 1'b1;
                    end else if ((cmd_length == 6) && (cmd_mem[0] == ".") &&
                                 (cmd_mem[1] == "R") && (cmd_mem[2] == "E") &&
                                 (cmd_mem[3] == "S") && (cmd_mem[4] == "E") &&
                                 (cmd_mem[5] == "T")) begin
                        reset_seen <= 1'b1;
                    end
                    cmd_length <= 6'd0;
                end else if (cmd_length < 32) begin
                    cmd_mem[cmd_length] <= cmd_data;
                    cmd_length <= cmd_length + 1'b1;
                end else begin
                    cmd_length <= 6'd0;
                end
            end
        end
    end

    wire unused_rx_status = cmd_start ^ cmd_frame_error ^ cmd_parity_error ^
                            cmd_busy ^ response_tx_busy ^ response_tx_done;
endmodule
