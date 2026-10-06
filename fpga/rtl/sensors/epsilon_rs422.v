`include "sensor_cfg_codes.vh"
`include "project_defs.vh"
`include "error_codes.vh"
module epsilon_rs422 #(
    parameter integer SYS_CLK_HZ=100000000,FIFO_DEPTH=256
)(
    input wire sys_clk,rst_sys_n,uart_rxd,output wire uart_txd,
    input wire [63:0] timestamp_now,input wire time_sync_valid,input wire [31:0] time_sync_seq,
    input wire sync_event_pulse,
    output wire [63:0] gnss_time_tag,output wire gnss_time_tag_valid,
    input wire cfg_valid,cfg_write,input wire [31:0] cfg_addr,cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output wire [31:0] cfg_rdata,output wire cfg_error,
    output wire m_valid,input wire m_ready,output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,m_last,output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,m_flags,
    output wire online,output wire [31:0] errors,output wire [31:0] drop_count,fifo_level,
    output wire [3:0] cfg_error_code
);
    // Compatibility name only; the bank instantiates epsilon_rs232 directly.
    epsilon_rs232 #(.SYS_CLK_HZ(SYS_CLK_HZ),.FIFO_DEPTH(FIFO_DEPTH)) core(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_sys_n),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .timestamp_now(timestamp_now),
        .time_sync_valid(time_sync_valid),
        .time_sync_seq(time_sync_seq),
        .sync_event_pulse(sync_event_pulse),
        .gnss_time_tag(gnss_time_tag),
        .gnss_time_tag_valid(gnss_time_tag_valid),
        .cfg_valid(cfg_valid),
        .cfg_write(cfg_write),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready),
        .cfg_rdata(cfg_rdata),
        .cfg_error(cfg_error),
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
        .online(online),
        .errors(errors),
        .drop_count(drop_count),
        .fifo_level(fifo_level),
        .cfg_error_code(cfg_error_code));
endmodule
