module async_fifo_wrap #(
    parameter integer WIDTH = 32,
    parameter integer DEPTH = 16
)(
    input  wire                 wr_clk,
    input  wire                 wr_rst_n,
    input  wire                 wr_valid,
    output wire                 wr_ready,
    input  wire [WIDTH-1:0]     wr_data,
    output wire                 wr_full,
    output reg                  wr_full_stall_pulse,

    input  wire                 rd_clk,
    input  wire                 rd_rst_n,
    output wire                 rd_valid,
    input  wire                 rd_ready,
    output wire [WIDTH-1:0]     rd_data,
    output wire                 rd_empty
);
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1)
                v = v >> 1;
        end
    endfunction

    localparam integer ADDR_W = clog2(DEPTH);
    localparam integer PTR_W  = ADDR_W + 1;

    (* ram_style = "auto" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

    reg [PTR_W-1:0] wr_bin, wr_gray;
    reg [PTR_W-1:0] rd_bin, rd_gray;
    reg [PTR_W-1:0] rd_gray_w1, rd_gray_w2;
    reg [PTR_W-1:0] wr_gray_r1, wr_gray_r2;
    reg wr_full_r, rd_empty_r;

    wire wr_fire = wr_valid && wr_ready;
    wire rd_fire = rd_valid && rd_ready;

    wire [PTR_W-1:0] wr_bin_next  = wr_bin + wr_fire;
    wire [PTR_W-1:0] rd_bin_next  = rd_bin + rd_fire;
    wire [PTR_W-1:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire [PTR_W-1:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    // Standard Gray-pointer full test: next write pointer equals synchronized
    // read pointer with the two MSBs inverted.
    wire wr_full_next =
        (wr_gray_next == {~rd_gray_w2[PTR_W-1:PTR_W-2],
                          rd_gray_w2[PTR_W-3:0]});
    wire rd_empty_next = (rd_gray_next == wr_gray_r2);

    assign wr_full  = wr_full_r;
    assign rd_empty = rd_empty_r;
    assign wr_ready = !wr_full_r;
    assign rd_valid = !rd_empty_r;
    assign rd_data  = mem[rd_bin[ADDR_W-1:0]];

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin             <= {PTR_W{1'b0}};
            wr_gray            <= {PTR_W{1'b0}};
            rd_gray_w1         <= {PTR_W{1'b0}};
            rd_gray_w2         <= {PTR_W{1'b0}};
            wr_full_r          <= 1'b0;
            wr_full_stall_pulse <= 1'b0;
        end else begin
            rd_gray_w1 <= rd_gray;
            rd_gray_w2 <= rd_gray_w1;
            wr_full_stall_pulse <= wr_valid && !wr_ready;

            if (wr_fire)
                mem[wr_bin[ADDR_W-1:0]] <= wr_data;

            wr_bin    <= wr_bin_next;
            wr_gray   <= wr_gray_next;
            wr_full_r <= wr_full_next;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin              <= {PTR_W{1'b0}};
            rd_gray             <= {PTR_W{1'b0}};
            wr_gray_r1          <= {PTR_W{1'b0}};
            wr_gray_r2          <= {PTR_W{1'b0}};
            rd_empty_r          <= 1'b1;
        end else begin
            wr_gray_r1 <= wr_gray;
            wr_gray_r2 <= wr_gray_r1;
            rd_bin     <= rd_bin_next;
            rd_gray    <= rd_gray_next;
            rd_empty_r <= rd_empty_next;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (DEPTH < 4 || (DEPTH & (DEPTH-1)) != 0) begin
            $display("async_fifo_wrap: DEPTH must be a power of two and >= 4");
            $finish;
        end
    end
`endif
endmodule
