`include "project_defs.vh"

module common_synth_smoke (
    input wire clk_a,
    input wire clk_b,
    input wire rst_n,
    input wire async_in,
    input wire [31:0] data_in, cfg_address,
    input wire valid_in, ready_in, ready_b_in, cfg_valid_in, cfg_write_in,
    input wire [3:0] cfg_strobes,
    output wire [511:0] observed_a,
    output wire [127:0] observed_b,
    output wire sync_out
);
    wire rst_a_n,rst_b_n;
    cdc_bit_sync u_reset_a(.clk(clk_a),.rst_n(rst_n),.async_in(1'b1),.sync_out(rst_a_n));
    cdc_bit_sync u_reset_b(.clk(clk_b),.rst_n(rst_n),.async_in(1'b1),.sync_out(rst_b_n));
    wire pulse_out;
    reg pulse_src;
    always @(posedge clk_a or negedge rst_a_n)
        if (!rst_a_n) pulse_src <= 1'b0;
        else pulse_src <= valid_in;

    cdc_bit_sync u_bit_sync (
        .clk(clk_a), .rst_n(rst_a_n), .async_in(async_in), .sync_out(sync_out)
    );

    cdc_pulse_sync u_pulse_sync (
        .src_clk(clk_a), .src_rst_n(rst_a_n), .src_pulse(pulse_src),
        .dst_clk(clk_b), .dst_rst_n(rst_b_n), .dst_pulse(pulse_out)
    );

    wire bus_src_ready, bus_dst_valid;
    wire [31:0] bus_dst_data;
    cdc_bus_handshake #(.WIDTH(32)) u_bus_cdc (
        .src_clk(clk_a), .src_rst_n(rst_a_n), .src_valid(pulse_src),
        .src_ready(bus_src_ready), .src_data(data_in),
        .dst_clk(clk_b), .dst_rst_n(rst_b_n),
        .dst_valid(bus_dst_valid), .dst_data(bus_dst_data)
    );

    wire sf_s_ready, sf_m_valid, sf_full, sf_empty, sf_afull;
    wire [31:0] sf_m_data, sf_level;
    wire sf_full_stall;
    sync_fifo #(.WIDTH(32), .DEPTH(16), .ALMOST_FULL_THRESHOLD(12)) u_sync_fifo (
        .clk(clk_a), .rst_n(rst_a_n),
        .s_valid(pulse_src), .s_ready(sf_s_ready), .s_data(data_in),
        .m_valid(sf_m_valid), .m_ready(ready_in), .m_data(sf_m_data),
        .full(sf_full), .empty(sf_empty), .almost_full(sf_afull),
        .level(sf_level), .full_stall_pulse(sf_full_stall)
    );

    wire af_wr_ready, af_wr_full, af_full_stall;
    wire af_rd_valid, af_rd_empty;
    wire [31:0] af_rd_data;
    async_fifo_wrap #(.WIDTH(32), .DEPTH(16)) u_async_fifo (
        .wr_clk(clk_a), .wr_rst_n(rst_a_n), .wr_valid(pulse_src),
        .wr_ready(af_wr_ready), .wr_data(data_in), .wr_full(af_wr_full),
        .wr_full_stall_pulse(af_full_stall),
        .rd_clk(clk_b), .rd_rst_n(rst_b_n), .rd_valid(af_rd_valid),
        .rd_ready(ready_b_in), .rd_data(af_rd_data), .rd_empty(af_rd_empty)
    );


    wire sample_s_ready, sample_m_valid;
    wire [31:0] sample_m_data, sample_level;
    wire [7:0] sample_m_flags;
    wire sample_full, sample_afull, sample_full_stall;
    sample_stream_fifo #(.DEPTH(16), .ALMOST_FULL_THRESHOLD(12)) u_sample_fifo (
        .clk(clk_a), .rst_n(rst_a_n),
        .s_valid(pulse_src), .s_ready(sample_s_ready), .s_data(data_in), .s_flags(8'h00),
        .m_valid(sample_m_valid), .m_ready(ready_in), .m_data(sample_m_data), .m_flags(sample_m_flags),
        .full(sample_full), .almost_full(sample_afull), .level(sample_level),
        .full_stall_pulse(sample_full_stall)
    );

    wire msg_s_ready, msg_m_valid;
    wire [31:0] msg_m_data, msg_m_cycle, msg_m_flags, msg_level;
    wire [3:0] msg_m_keep;
    wire msg_m_sof, msg_m_last;
    wire [15:0] msg_m_source, msg_m_id;
    wire [63:0] msg_m_ts;
    wire msg_full, msg_afull, msg_full_stall;
    msg_stream_fifo #(.DEPTH(16), .ALMOST_FULL_THRESHOLD(12)) u_msg_fifo (
        .clk(clk_a), .rst_n(rst_a_n),
        .s_valid(pulse_src), .s_ready(msg_s_ready), .s_data(data_in), .s_keep(4'hF),
        .s_sof(1'b1), .s_last(1'b1), .s_source_id(`SRC_HMP),
        .s_msg_id(`MSG_SENSOR_TLV_RECORD), .s_timestamp(64'd0),
        .s_cycle_id(`CYCLE_ID_NONE), .s_flags(32'd0),
        .m_valid(msg_m_valid), .m_ready(ready_in), .m_data(msg_m_data), .m_keep(msg_m_keep),
        .m_sof(msg_m_sof), .m_last(msg_m_last), .m_source_id(msg_m_source),
        .m_msg_id(msg_m_id), .m_timestamp(msg_m_ts), .m_cycle_id(msg_m_cycle),
        .m_flags(msg_m_flags), .full(msg_full), .almost_full(msg_afull),
        .level(msg_level), .full_stall_pulse(msg_full_stall)
    );

    wire bulk_s_ready, bulk_m_valid;
    wire [31:0] bulk_m_data, bulk_m_cycle, bulk_m_flags, bulk_level;
    wire [3:0] bulk_m_keep;
    wire bulk_m_sof, bulk_m_last;
    wire [15:0] bulk_m_source, bulk_m_id;
    wire [63:0] bulk_m_ts;
    wire bulk_full, bulk_afull, bulk_full_stall;
    bulk_stream_fifo #(.DEPTH(16), .ALMOST_FULL_THRESHOLD(12)) u_bulk_fifo (
        .clk(clk_a), .rst_n(rst_a_n),
        .s_valid(pulse_src), .s_ready(bulk_s_ready), .s_data(data_in), .s_keep(4'hF),
        .s_sof(1'b1), .s_last(1'b1), .s_source_id(`SRC_DILA0),
        .s_msg_id(`MSG_DILA_BLOCK), .s_timestamp(64'd0),
        .s_cycle_id(32'd0), .s_flags(32'd0),
        .m_valid(bulk_m_valid), .m_ready(ready_in), .m_data(bulk_m_data), .m_keep(bulk_m_keep),
        .m_sof(bulk_m_sof), .m_last(bulk_m_last), .m_source_id(bulk_m_source),
        .m_msg_id(bulk_m_id), .m_timestamp(bulk_m_ts), .m_cycle_id(bulk_m_cycle),
        .m_flags(bulk_m_flags), .full(bulk_full), .almost_full(bulk_afull),
        .level(bulk_level), .full_stall_pulse(bulk_full_stall)
    );

    wire cfg_ready, cfg_error;
    wire [31:0] cfg_rdata, ctrl, err, r0, r1;
    cfg_bus_if u_cfg (
        .sys_clk(clk_a), .rst_sys_n(rst_a_n),
        .cfg_valid(cfg_valid_in), .cfg_write(cfg_write_in), .cfg_addr(cfg_address),
        .cfg_wdata(data_in), .cfg_wstrb(cfg_strobes),
        .cfg_ready(cfg_ready), .cfg_rdata(cfg_rdata), .cfg_error(cfg_error),
        .control_reg(ctrl), .error_reg(err), .user_reg0(r0), .user_reg1(r1)
    );
    assign observed_a={cfg_ready,cfg_error,cfg_rdata,ctrl,err,r0,r1,
        sf_s_ready,sf_m_valid,sf_m_data,sf_full,sf_empty,sf_afull,sf_level,sf_full_stall,
        af_wr_ready,af_wr_full,af_full_stall,bus_src_ready,
        sample_s_ready,sample_m_valid,sample_m_data,sample_m_flags,sample_full,sample_afull,sample_level,sample_full_stall,
        msg_s_ready,msg_m_valid,msg_m_data,msg_m_keep,msg_m_sof,msg_m_last,msg_full,msg_afull,msg_level,msg_full_stall,
        bulk_s_ready,bulk_m_valid,bulk_m_data,bulk_m_keep,bulk_m_sof,bulk_m_last,bulk_full,bulk_afull,bulk_level,bulk_full_stall};
    assign observed_b={pulse_out,bus_dst_valid,bus_dst_data,af_rd_valid,af_rd_data,af_rd_empty};
endmodule
