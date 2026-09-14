module sync_fifo #(
    parameter integer WIDTH = 32,
    parameter integer DEPTH = 16,
    parameter integer ALMOST_FULL_THRESHOLD = DEPTH-2
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 s_valid,
    output wire                 s_ready,
    input  wire [WIDTH-1:0]     s_data,

    output wire                 m_valid,
    input  wire                 m_ready,
    output wire [WIDTH-1:0]     m_data,

    output wire                 full,
    output wire                 empty,
    output wire                 almost_full,
    output reg  [31:0]          level,
    output reg                  full_stall_pulse
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

    (* ram_style = "auto" *) reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;

    wire do_write = s_valid && s_ready;
    wire do_read  = m_valid && m_ready;

    assign full        = (level >= DEPTH);
    assign empty       = (level == 0);
    assign almost_full = (level >= ALMOST_FULL_THRESHOLD);
    assign s_ready     = !full;
    assign m_valid     = !empty;
    assign m_data      = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr          <= {ADDR_W{1'b0}};
            rd_ptr          <= {ADDR_W{1'b0}};
            level           <= 32'd0;
            full_stall_pulse <= 1'b0;
        end else begin
            full_stall_pulse <= s_valid && !s_ready;

            if (do_write) begin
                mem[wr_ptr] <= s_data;
                if (wr_ptr == DEPTH-1)
                    wr_ptr <= {ADDR_W{1'b0}};
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_read) begin
                if (rd_ptr == DEPTH-1)
                    rd_ptr <= {ADDR_W{1'b0}};
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            case ({do_write, do_read})
                2'b10: level <= level + 1'b1;
                2'b01: level <= level - 1'b1;
                default: level <= level;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (DEPTH < 2) begin
            $display("sync_fifo: DEPTH must be >= 2");
            $finish;
        end
    end
`endif
endmodule
