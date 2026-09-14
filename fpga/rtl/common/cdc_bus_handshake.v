module cdc_bus_handshake #(
    parameter integer WIDTH = 32
)(
    input  wire                 src_clk,
    input  wire                 src_rst_n,
    input  wire                 src_valid,
    output wire                 src_ready,
    input  wire [WIDTH-1:0]     src_data,

    input  wire                 dst_clk,
    input  wire                 dst_rst_n,
    output reg                  dst_valid,
    output reg  [WIDTH-1:0]     dst_data
);
    // Bundled-data CDC: src_data is held in src_hold until the destination has
    // observed the request and returned the matching acknowledge toggle.
    reg [WIDTH-1:0] src_hold;
    reg req_toggle;
    reg ack_toggle;

    reg ack_sync1, ack_sync2;
    reg req_sync1, req_sync2, req_seen;

    assign src_ready = (ack_sync2 == req_toggle);

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_hold   <= {WIDTH{1'b0}};
            req_toggle <= 1'b0;
            ack_sync1  <= 1'b0;
            ack_sync2  <= 1'b0;
        end else begin
            ack_sync1 <= ack_toggle;
            ack_sync2 <= ack_sync1;
            if (src_valid && src_ready) begin
                src_hold   <= src_data;
                req_toggle <= ~req_toggle;
            end
        end
    end

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            req_sync1 <= 1'b0;
            req_sync2 <= 1'b0;
            req_seen  <= 1'b0;
            ack_toggle <= 1'b0;
            dst_valid <= 1'b0;
            dst_data  <= {WIDTH{1'b0}};
        end else begin
            req_sync1 <= req_toggle;
            req_sync2 <= req_sync1;
            dst_valid <= 1'b0;

            if (req_sync2 != req_seen) begin
                // By the time req_sync2 changes, src_hold has been stable for
                // multiple destination-clock cycles.
                dst_data   <= src_hold;
                dst_valid  <= 1'b1;
                req_seen   <= req_sync2;
                ack_toggle <= req_sync2;
            end
        end
    end
endmodule
