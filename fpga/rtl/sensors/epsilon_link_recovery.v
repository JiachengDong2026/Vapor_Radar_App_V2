`timescale 1ns/1ps
// One read-only MAIN recovery attempt per enable epoch. The UART and command
// sequencer finish the current CRLF line and #fdeconfig after disable/reset.
// This cooperative cleanup requires the clock, supply and RS232 PHY to remain on.
module epsilon_link_recovery #(
    parameter integer SYS_CLK_HZ = 100000000,
    parameter integer PASSIVE_MS = 2500,
    parameter integer RESPONSE_MS = 500,
    parameter integer QUIET_MS = 50
)(
    input wire sys_clk, rst_sys_n, enable,
    input wire [31:0] baud_hz,
    input wire rx_valid,
    input wire [7:0] rx_data,
    input wire good_frame,
    output wire txd,
    output wire busy,
    output wire [3:0] debug_state,
    output reg [15:0] attempts
);
    localparam [3:0] IDLE=0, PASSIVE=1, CONFIG_TX=2, CONFIG_WAIT=3,
                     QUERY_TX=4, QUERY_WAIT=5, EXIT_TX=6, EXIT_WAIT=7,
                     RECHECK=8, RUN=9, FAILED=10;
    localparam integer PASSIVE_TICKS = (SYS_CLK_HZ/1000)*PASSIVE_MS;
    localparam integer RESPONSE_TICKS = (SYS_CLK_HZ/1000)*RESPONSE_MS;
    localparam integer QUIET_TICKS = (SYS_CLK_HZ/1000)*QUIET_MS;
    reg [3:0] state;
    reg [31:0] timer, quiet_timer, tx_baud;
    reg [3:0] tx_index;
    reg tx_pending, config_open, cancel_pending, reset_pending;
    reg stream_seen, reply_seen, ack_seen;
    reg [1:0] ack_match;
    wire tx_ready, tx_done, tx_busy;
    wire sending = state==CONFIG_TX || state==QUERY_TX || state==EXIT_TX;
    wire tx_valid = sending && !tx_pending;
    wire [3:0] final_index = state==CONFIG_TX ? 4'd9 : state==QUERY_TX ? 4'd6 : 4'd11;
    wire cancelling = cancel_pending || !enable || !rst_sys_n;
    // Keep uart_tx out of reset until the cleanup line has physically completed.
    wire tx_reset_n = rst_sys_n || config_open;
    assign busy = config_open;
    assign debug_state = state;
    function [7:0] command_byte;
        input [3:0] command, index;
        begin
            command_byte=8'h0a;
            if (command==CONFIG_TX) begin
                case(index)
                    0:command_byte="#"; 1:command_byte="f"; 2:command_byte="c";
                    3:command_byte="o"; 4:command_byte="n"; 5:command_byte="f";
                    6:command_byte="i"; 7:command_byte="g"; 8:command_byte=8'h0d;
                    default:command_byte=8'h0a;
                endcase
            end else if (command==QUERY_TX) begin
                case(index)
                    0:command_byte="#"; 1:command_byte="f"; 2:command_byte="m";
                    3:command_byte="s"; 4:command_byte="g"; 5:command_byte=8'h0d;
                    default:command_byte=8'h0a;
                endcase
            end else begin
                case(index)
                    0:command_byte="#"; 1:command_byte="f"; 2:command_byte="d";
                    3:command_byte="e"; 4:command_byte="c"; 5:command_byte="o";
                    6:command_byte="n"; 7:command_byte="f"; 8:command_byte="i";
                    9:command_byte="g"; 10:command_byte=8'h0d;
                    default:command_byte=8'h0a;
                endcase
            end
        end
    endfunction
    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_tx(
        .sys_clk(sys_clk), .rst_sys_n(tx_reset_n), .enable(1'b1), .baud_hz(tx_baud),
        .data_bits(4'd8), .parity_mode(2'd0), .stop_bits(2'd1),
        .byte_valid(tx_valid), .byte_ready(tx_ready), .byte_data(command_byte(state,tx_index)),
        .txd(txd), .busy(tx_busy), .frame_done_pulse(tx_done));

    // FPGA power-up initialization is required because an operational reset is
    // a cleanup request, not an asynchronous erase of an in-flight command.
    initial begin
        state=IDLE; timer=0; quiet_timer=0; tx_baud=921600; tx_index=0;
        tx_pending=0; config_open=0; cancel_pending=0; reset_pending=0;
        stream_seen=0; reply_seen=0; ack_seen=0; ack_match=0; attempts=0;
    end
    task begin_exit;
        begin
            state<=EXIT_TX; tx_index<=0; tx_pending<=0;
            timer<=0; quiet_timer<=0; reply_seen<=0; ack_seen<=0; ack_match<=0;
        end
    endtask
    always @(posedge sys_clk) begin
        if (!rst_sys_n && !config_open) begin
            state<=IDLE; timer<=0; quiet_timer<=0; tx_baud<=921600; tx_index<=0;
            tx_pending<=0; config_open<=0; cancel_pending<=0; reset_pending<=0;
            stream_seen<=0; reply_seen<=0; ack_seen<=0; ack_match<=0; attempts<=0;
        end else begin
            if (config_open && (!enable || !rst_sys_n)) cancel_pending<=1;
            if (config_open && !rst_sys_n) reset_pending<=1;
            if (good_frame) stream_seen<=1;
            if (config_open && rx_valid) begin
                reply_seen<=1; quiet_timer<=0;
                // Accept #OK and *#OK, including replies split across UART bytes.
                case(ack_match)
                    0:ack_match<=rx_data=="#" ? 1 : 0;
                    1:ack_match<=rx_data=="O" ? 2 : rx_data=="#" ? 1 : 0;
                    default:begin
                        if(rx_data=="K") ack_seen<=1;
                        ack_match<=rx_data=="#" ? 1 : 0;
                    end
                endcase
            end else if (quiet_timer<QUIET_TICKS) quiet_timer<=quiet_timer+1'b1;
            case(state)
                IDLE:begin
                    cancel_pending<=0; reset_pending<=0; stream_seen<=0;
                    reply_seen<=0; ack_seen<=0; ack_match<=0; timer<=0;
                    if(enable && rst_sys_n) state<=PASSIVE;
                end
                PASSIVE:begin
                    if(!enable) state<=IDLE;
                    else if(good_frame || stream_seen) state<=RUN;
                    else if(timer>=PASSIVE_TICKS-1) begin
                        state<=CONFIG_TX; config_open<=1; tx_baud<=baud_hz;
                        tx_index<=0; tx_pending<=0; timer<=0; quiet_timer<=0;
                        reply_seen<=0; ack_seen<=0; ack_match<=0;
                        if(attempts!=16'hffff) attempts<=attempts+1'b1;
                    end else timer<=timer+1'b1;
                end
                CONFIG_TX,QUERY_TX,EXIT_TX:begin
                    if(tx_valid && tx_ready) tx_pending<=1;
                    // Do not advance on byte_ready: it precedes physical TX.
                    if(tx_done && tx_pending) begin
                        tx_pending<=0;
                        if(tx_index==final_index) begin
                            tx_index<=0; timer<=0; quiet_timer<=0;
                            if(state==EXIT_TX) begin
                                if(cancelling) begin
                                    config_open<=0; state<=IDLE;
                                    if(reset_pending || !rst_sys_n) attempts<=0;
                                end else state<=EXIT_WAIT;
                            end else if(cancelling || stream_seen || good_frame) begin_exit;
                            else if(state==CONFIG_TX) state<=CONFIG_WAIT;
                            else begin state<=QUERY_WAIT; reply_seen<=0; end
                        end else tx_index<=tx_index+1'b1;
                    end
                end
                CONFIG_WAIT:begin
                    if(cancelling || stream_seen || good_frame) begin_exit;
                    else if(ack_seen || timer>=RESPONSE_TICKS-1) begin
                        // A lost/absent ACK must not omit the requested read-only
                        // query. Both success and timeout still end in #fdeconfig.
                        state<=QUERY_TX; tx_index<=0; tx_pending<=0;
                        timer<=0; quiet_timer<=0; reply_seen<=0; ack_seen<=0; ack_match<=0;
                    end else timer<=timer+1'b1;
                end
                QUERY_WAIT:begin
                    // Multiline fmsg has no assumed terminator: use a quiet gap
                    // after any reply, with a hard bound even for endless bytes.
                    if(cancelling || stream_seen || good_frame ||
                       (reply_seen && !rx_valid && quiet_timer>=QUIET_TICKS-1) ||
                       timer>=RESPONSE_TICKS-1) begin_exit;
                    else timer<=timer+1'b1;
                end
                EXIT_WAIT:begin
                    // The post-exit passive interval starts at the final LF's
                    // completed stop bit, not after the optional exit reply.
                    if(cancelling) begin
                        config_open<=0; state<=IDLE;
                        if(reset_pending || !rst_sys_n) attempts<=0;
                    end else if(stream_seen || good_frame) begin config_open<=0; state<=RUN; end
                    else if(timer>=PASSIVE_TICKS-1) begin config_open<=0; state<=FAILED; end
                    else if(ack_seen || timer>=RESPONSE_TICKS-1) begin
                        config_open<=0; timer<=timer+1'b1; state<=RECHECK;
                    end else timer<=timer+1'b1;
                end
                RECHECK:begin
                    if(!enable) state<=IDLE;
                    else if(stream_seen || good_frame) state<=RUN;
                    else if(timer>=PASSIVE_TICKS-1) state<=FAILED;
                    else timer<=timer+1'b1;
                end
                RUN,FAILED:begin
                    // Loss after RUN/FAILED never starts another command train.
                    if(!enable) state<=IDLE;
                    else if(good_frame) state<=RUN;
                end
                default:begin state<=IDLE; config_open<=0; end
            endcase
        end
    end
endmodule
