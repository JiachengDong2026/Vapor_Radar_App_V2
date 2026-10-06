`default_nettype none
// One outstanding event. Both domains must reset together. Events while busy
// are rejected and counted; the acknowledgement waits for output acceptance.
module timestamp_capture (
    input wire event_clk, event_rst_n, event_pulse,
    output wire event_busy,
    output reg [31:0] rejected_count,
    input wire sys_clk, rst_sys_n,
    input wire [63:0] timestamp_now,
    output reg ts_valid,
    input wire ts_ready,
    output reg [63:0] ts_value
);
    reg request_toggle, acknowledge_toggle;
    (* ASYNC_REG = "TRUE" *) reg ack_meta, ack_sync;
    (* ASYNC_REG = "TRUE" *) reg req_meta, req_sync;
    assign event_busy = request_toggle != ack_sync;
    always @(posedge event_clk or negedge event_rst_n) begin
        if (!event_rst_n) begin
            request_toggle <= 0; ack_meta <= 0; ack_sync <= 0;
            rejected_count <= 0;
        end else begin
            ack_meta <= acknowledge_toggle; ack_sync <= ack_meta;
            if (event_pulse) begin
                if (!event_busy) request_toggle <= ~request_toggle;
                else rejected_count <= rejected_count + 1'b1;
            end
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            req_meta <= 0; req_sync <= 0; acknowledge_toggle <= 0;
            ts_valid <= 0; ts_value <= 0;
        end else begin
            req_meta <= request_toggle; req_sync <= req_meta;
            if (ts_valid) begin
                if (ts_ready) begin
                    ts_valid <= 0;
                    acknowledge_toggle <= req_sync;
                end
            end else if (req_sync != acknowledge_toggle) begin
                ts_value <= timestamp_now;
                ts_valid <= 1;
            end
        end
    end
endmodule
`default_nettype wire
