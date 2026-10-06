`default_nettype none
module gpif_transport_buffers #(parameter integer DEPTH=2048)(
    input wire reset_n,sys_clk,gpif_clk,
    input wire tx_valid,
    output wire tx_ready,
    input wire [31:0] tx_data,
    input wire tx_last,
    output wire rx_valid,
    input wire rx_ready,
    output wire [31:0] rx_data,
    output wire gpif_tx_valid,
    input wire gpif_tx_ready,
    output wire [31:0] gpif_tx_data,
    output wire gpif_tx_last,
    input wire gpif_rx_valid,
    output wire gpif_rx_ready,
    input wire [31:0] gpif_rx_data,
    output wire [31:0] sys_tx_level,sys_rx_level,gpif_tx_level,gpif_rx_free
);
    wire [31:0] gpif_rx_level;
    assign gpif_rx_free=DEPTH-gpif_rx_level;
    transport_async_fifo #(.WIDTH(33),.DEPTH(DEPTH)) u_tx(
        .reset_n(reset_n),.wr_clk(sys_clk),.rd_clk(gpif_clk),.s_valid(tx_valid),.s_ready(tx_ready),.s_data({tx_last,tx_data}),
        .m_valid(gpif_tx_valid),.m_ready(gpif_tx_ready),.m_data({gpif_tx_last,gpif_tx_data}),.wr_level(sys_tx_level),.rd_level(gpif_tx_level));
    transport_async_fifo #(.WIDTH(32),.DEPTH(DEPTH)) u_rx(
        .reset_n(reset_n),.wr_clk(gpif_clk),.rd_clk(sys_clk),.s_valid(gpif_rx_valid),.s_ready(gpif_rx_ready),.s_data(gpif_rx_data),
        .m_valid(rx_valid),.m_ready(rx_ready),.m_data(rx_data),.wr_level(gpif_rx_level),.rd_level(sys_rx_level));
endmodule
`default_nettype wire
