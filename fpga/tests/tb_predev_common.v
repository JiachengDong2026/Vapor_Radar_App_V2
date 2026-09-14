`timescale 1ns/1ps
`include "project_defs.vh"
`include "stream_defs.vh"

module tb_predev_common;
    reg clk2;
    wire clk;
    wire rst_n;

    // ------------------------------------------------------------------
    // Clock / reset and time reference stubs.
    // ------------------------------------------------------------------
    clock_reset_gen #(.CLK_PERIOD_NS(10), .RESET_CYCLES(8)) u_clkgen (
        .clk(clk), .rst_n(rst_n)
    );

    initial begin
        clk2 = 1'b0;
        forever #7 clk2 = ~clk2;
    end

    wire [63:0] timestamp_now;
    wire time_sync_valid;
    wire [31:0] time_sync_seq;
    wire sync_event_pulse;
    time_sync_stub #(.SYNC_PERIOD_CYCLES(32)) u_time (
        .clk(clk), .rst_n(rst_n),
        .timestamp_now(timestamp_now),
        .time_sync_valid(time_sync_valid),
        .time_sync_seq(time_sync_seq),
        .sync_event_pulse(sync_event_pulse)
    );

    wire scan_start, phase_valid, wms_running;
    wire [31:0] cycle_id, sine_phase;
    wms_reference_stub #(.SCAN_PERIOD_CYCLES(8), .PHASE_INC(32'h1000_0000)) u_wms (
        .clk(clk), .rst_n(rst_n),
        .scan_start(scan_start), .phase_valid(phase_valid),
        .cycle_id(cycle_id), .sine_phase(sine_phase),
        .wms_running(wms_running)
    );

    // ------------------------------------------------------------------
    // Frozen cfg_bus BFM + reference slave.
    // ------------------------------------------------------------------
    wire cfg_valid, cfg_write;
    wire [31:0] cfg_addr, cfg_wdata;
    wire [3:0] cfg_wstrb;
    wire cfg_ready, cfg_error;
    wire [31:0] cfg_rdata;
    wire [31:0] cfg_control, cfg_error_reg, cfg_user0, cfg_user1;
    reg [31:0] cfg_readback;

    cfg_bus_master_bfm #(.TIMEOUT_CYCLES(50)) u_cfg_bfm (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_write(cfg_write), .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata), .cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready), .cfg_rdata(cfg_rdata), .cfg_error(cfg_error)
    );

    cfg_bus_if #(.BASE_ADDR(32'h0000_9000), .MODULE_ID(16'h00FE)) u_cfg_slave (
        .sys_clk(clk), .rst_sys_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_write(cfg_write), .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata), .cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready), .cfg_rdata(cfg_rdata), .cfg_error(cfg_error),
        .control_reg(cfg_control), .error_reg(cfg_error_reg),
        .user_reg0(cfg_user0), .user_reg1(cfg_user1)
    );

    // ------------------------------------------------------------------
    // sample_stream checker with deterministic backpressure.
    // ------------------------------------------------------------------
    reg sample_valid;
    wire sample_ready;
    reg [31:0] sample_data;
    reg [7:0] sample_flags;
    wire sample_m_valid, sample_m_ready;
    wire [31:0] sample_m_data;
    wire [7:0] sample_m_flags;
    wire sample_fifo_full, sample_fifo_afull, sample_fifo_full_stall;
    wire [31:0] sample_fifo_level;
    wire [31:0] sample_count;

    sample_stream_fifo #(.DEPTH(16), .ALMOST_FULL_THRESHOLD(12)) u_sample_fifo (
        .clk(clk), .rst_n(rst_n),
        .s_valid(sample_valid), .s_ready(sample_ready), .s_data(sample_data), .s_flags(sample_flags),
        .m_valid(sample_m_valid), .m_ready(sample_m_ready), .m_data(sample_m_data), .m_flags(sample_m_flags),
        .full(sample_fifo_full), .almost_full(sample_fifo_afull), .level(sample_fifo_level),
        .full_stall_pulse(sample_fifo_full_stall)
    );

    sample_stream_sink #(.STALL_EVERY(3), .STALL_CYCLES(1)) u_sample_sink (
        .clk(clk), .rst_n(rst_n), .valid(sample_m_valid), .ready(sample_m_ready),
        .data(sample_m_data), .flags(sample_m_flags), .sample_count(sample_count)
    );

    // ------------------------------------------------------------------
    // msg_stream source -> common FIFO -> checker.
    // ------------------------------------------------------------------
    reg msg_s_valid;
    wire msg_s_ready;
    reg [31:0] msg_s_data;
    reg [3:0] msg_s_keep;
    reg msg_s_sof, msg_s_last;
    reg [15:0] msg_s_source_id, msg_s_msg_id;
    reg [63:0] msg_s_timestamp;
    reg [31:0] msg_s_cycle_id, msg_s_flags;

    wire msg_m_valid, msg_m_ready;
    wire [31:0] msg_m_data;
    wire [3:0] msg_m_keep;
    wire msg_m_sof, msg_m_last;
    wire [15:0] msg_m_source_id, msg_m_msg_id;
    wire [63:0] msg_m_timestamp;
    wire [31:0] msg_m_cycle_id, msg_m_flags;
    wire msg_fifo_full, msg_fifo_afull, msg_fifo_full_stall;
    wire [31:0] msg_fifo_level;
    wire [31:0] msg_beat_count, msg_count;

    msg_stream_fifo #(.DEPTH(16), .ALMOST_FULL_THRESHOLD(12)) u_msg_fifo (
        .clk(clk), .rst_n(rst_n),
        .s_valid(msg_s_valid), .s_ready(msg_s_ready),
        .s_data(msg_s_data), .s_keep(msg_s_keep), .s_sof(msg_s_sof), .s_last(msg_s_last),
        .s_source_id(msg_s_source_id), .s_msg_id(msg_s_msg_id),
        .s_timestamp(msg_s_timestamp), .s_cycle_id(msg_s_cycle_id), .s_flags(msg_s_flags),
        .m_valid(msg_m_valid), .m_ready(msg_m_ready),
        .m_data(msg_m_data), .m_keep(msg_m_keep), .m_sof(msg_m_sof), .m_last(msg_m_last),
        .m_source_id(msg_m_source_id), .m_msg_id(msg_m_msg_id),
        .m_timestamp(msg_m_timestamp), .m_cycle_id(msg_m_cycle_id), .m_flags(msg_m_flags),
        .full(msg_fifo_full), .almost_full(msg_fifo_afull), .level(msg_fifo_level),
        .full_stall_pulse(msg_fifo_full_stall)
    );

    msg_stream_sink #(
        .STALL_EVERY(2), .STALL_CYCLES(2), .CHECK_IDS(1),
        .EXPECTED_SOURCE_ID(`SRC_HMP), .EXPECTED_MSG_ID(`MSG_SENSOR_TLV_RECORD)
    ) u_msg_sink (
        .clk(clk), .rst_n(rst_n), .valid(msg_m_valid), .ready(msg_m_ready),
        .data(msg_m_data), .keep(msg_m_keep), .sof(msg_m_sof), .last(msg_m_last),
        .source_id(msg_m_source_id), .msg_id(msg_m_msg_id),
        .timestamp(msg_m_timestamp), .cycle_id(msg_m_cycle_id), .flags(msg_m_flags),
        .beat_count(msg_beat_count), .msg_count(msg_count)
    );

    // ------------------------------------------------------------------
    // bulk_stream source -> common FIFO -> checker.
    // Fragment index/count belong to DILA/ADC payload headers, not generic
    // stream sideband in this frozen interface.
    // ------------------------------------------------------------------
    reg bulk_s_valid;
    wire bulk_s_ready;
    reg [31:0] bulk_s_data;
    reg [3:0] bulk_s_keep;
    reg bulk_s_sof, bulk_s_last;
    reg [15:0] bulk_s_source_id, bulk_s_msg_id;
    reg [63:0] bulk_s_timestamp;
    reg [31:0] bulk_s_cycle_id, bulk_s_flags;

    wire bulk_m_valid, bulk_m_ready;
    wire [31:0] bulk_m_data;
    wire [3:0] bulk_m_keep;
    wire bulk_m_sof, bulk_m_last;
    wire [15:0] bulk_m_source_id, bulk_m_msg_id;
    wire [63:0] bulk_m_timestamp;
    wire [31:0] bulk_m_cycle_id, bulk_m_flags;
    wire bulk_fifo_full, bulk_fifo_afull, bulk_fifo_full_stall;
    wire [31:0] bulk_fifo_level;
    wire [31:0] bulk_beat_count, bulk_frame_count;

    bulk_stream_fifo #(.DEPTH(16), .ALMOST_FULL_THRESHOLD(12)) u_bulk_fifo (
        .clk(clk), .rst_n(rst_n),
        .s_valid(bulk_s_valid), .s_ready(bulk_s_ready),
        .s_data(bulk_s_data), .s_keep(bulk_s_keep), .s_sof(bulk_s_sof), .s_last(bulk_s_last),
        .s_source_id(bulk_s_source_id), .s_msg_id(bulk_s_msg_id),
        .s_timestamp(bulk_s_timestamp), .s_cycle_id(bulk_s_cycle_id), .s_flags(bulk_s_flags),
        .m_valid(bulk_m_valid), .m_ready(bulk_m_ready),
        .m_data(bulk_m_data), .m_keep(bulk_m_keep), .m_sof(bulk_m_sof), .m_last(bulk_m_last),
        .m_source_id(bulk_m_source_id), .m_msg_id(bulk_m_msg_id),
        .m_timestamp(bulk_m_timestamp), .m_cycle_id(bulk_m_cycle_id), .m_flags(bulk_m_flags),
        .full(bulk_fifo_full), .almost_full(bulk_fifo_afull), .level(bulk_fifo_level),
        .full_stall_pulse(bulk_fifo_full_stall)
    );

    bulk_stream_sink #(
        .STALL_EVERY(3), .STALL_CYCLES(1), .CHECK_IDS(1),
        .EXPECTED_SOURCE_ID(`SRC_DILA0), .EXPECTED_MSG_ID(`MSG_DILA_BLOCK)
    ) u_bulk_sink (
        .clk(clk), .rst_n(rst_n), .valid(bulk_m_valid), .ready(bulk_m_ready),
        .data(bulk_m_data), .keep(bulk_m_keep), .sof(bulk_m_sof), .last(bulk_m_last),
        .source_id(bulk_m_source_id), .msg_id(bulk_m_msg_id),
        .timestamp(bulk_m_timestamp), .cycle_id(bulk_m_cycle_id), .flags(bulk_m_flags),
        .beat_count(bulk_beat_count), .frame_count(bulk_frame_count)
    );

    // ------------------------------------------------------------------
    // CDC regression.
    // ------------------------------------------------------------------
    reg cdc_src_pulse;
    wire cdc_dst_pulse;
    cdc_pulse_sync u_pulse_sync (
        .src_clk(clk), .src_rst_n(rst_n), .src_pulse(cdc_src_pulse),
        .dst_clk(clk2), .dst_rst_n(rst_n), .dst_pulse(cdc_dst_pulse)
    );

    reg cdc_bus_valid;
    wire cdc_bus_ready;
    reg [31:0] cdc_bus_data;
    wire cdc_bus_dst_valid;
    wire [31:0] cdc_bus_dst_data;
    cdc_bus_handshake #(.WIDTH(32)) u_bus_cdc (
        .src_clk(clk), .src_rst_n(rst_n),
        .src_valid(cdc_bus_valid), .src_ready(cdc_bus_ready), .src_data(cdc_bus_data),
        .dst_clk(clk2), .dst_rst_n(rst_n),
        .dst_valid(cdc_bus_dst_valid), .dst_data(cdc_bus_dst_data)
    );

    // Async FIFO regression.
    reg af_wr_valid;
    wire af_wr_ready, af_wr_full, af_wr_full_stall;
    reg [31:0] af_wr_data;
    wire af_rd_valid, af_rd_empty;
    reg af_rd_ready;
    wire [31:0] af_rd_data;

    async_fifo_wrap #(.WIDTH(32), .DEPTH(16)) u_async_fifo (
        .wr_clk(clk), .wr_rst_n(rst_n), .wr_valid(af_wr_valid),
        .wr_ready(af_wr_ready), .wr_data(af_wr_data), .wr_full(af_wr_full),
        .wr_full_stall_pulse(af_wr_full_stall),
        .rd_clk(clk2), .rd_rst_n(rst_n), .rd_valid(af_rd_valid),
        .rd_ready(af_rd_ready), .rd_data(af_rd_data), .rd_empty(af_rd_empty)
    );

    integer i;
    integer scan_seen;
    integer pulse_seen;
    reg [63:0] ts0;
    reg [31:0] expected_af;

    task automatic send_sample;
        input [31:0] d;
        input [7:0] f;
        begin : SEND_SAMPLE
            @(negedge clk);
            sample_valid = 1'b1;
            sample_data  = d;
            sample_flags = f;
            while (!sample_ready)
                @(negedge clk);
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task automatic send_msg_beat;
        input [31:0] d;
        input [3:0] k;
        input s;
        input l;
        input [63:0] ts;
        begin
            @(negedge clk);
            msg_s_valid     = 1'b1;
            msg_s_data      = d;
            msg_s_keep      = k;
            msg_s_sof       = s;
            msg_s_last      = l;
            msg_s_source_id = `SRC_HMP;
            msg_s_msg_id    = `MSG_SENSOR_TLV_RECORD;
            msg_s_timestamp = ts;
            msg_s_cycle_id  = `CYCLE_ID_NONE;
            msg_s_flags     = 32'd0;
            while (!msg_s_ready)
                @(negedge clk);
            @(negedge clk);
            msg_s_valid = 1'b0;
        end
    endtask

    task automatic send_bulk_beat;
        input [31:0] d;
        input [3:0] k;
        input s;
        input l;
        input [63:0] ts;
        input [31:0] cyc;
        begin
            @(negedge clk);
            bulk_s_valid     = 1'b1;
            bulk_s_data      = d;
            bulk_s_keep      = k;
            bulk_s_sof       = s;
            bulk_s_last      = l;
            bulk_s_source_id = `SRC_DILA0;
            bulk_s_msg_id    = `MSG_DILA_BLOCK;
            bulk_s_timestamp = ts;
            bulk_s_cycle_id  = cyc;
            bulk_s_flags     = 32'd0;
            while (!bulk_s_ready)
                @(negedge clk);
            @(negedge clk);
            bulk_s_valid = 1'b0;
        end
    endtask

    initial begin
        sample_valid = 0; sample_data = 0; sample_flags = 0;
        msg_s_valid = 0; msg_s_data = 0; msg_s_keep = 0; msg_s_sof = 0; msg_s_last = 0;
        msg_s_source_id = 0; msg_s_msg_id = 0; msg_s_timestamp = 0; msg_s_cycle_id = 0; msg_s_flags = 0;
        bulk_s_valid = 0; bulk_s_data = 0; bulk_s_keep = 0; bulk_s_sof = 0; bulk_s_last = 0;
        bulk_s_source_id = 0; bulk_s_msg_id = 0; bulk_s_timestamp = 0; bulk_s_cycle_id = 0; bulk_s_flags = 0;
        cdc_src_pulse = 0; cdc_bus_valid = 0; cdc_bus_data = 0;
        af_wr_valid = 0; af_wr_data = 0; af_rd_ready = 0;
        scan_seen = 0; pulse_seen = 0; expected_af = 0;

        wait(rst_n);
        repeat(3) @(posedge clk);

        // Timebase check.
        ts0 = timestamp_now;
        repeat(20) @(posedge clk);
        #1;
        if (timestamp_now - ts0 != 64'd20)
            $fatal(1, "TIME_STUB_FAIL delta=%0d", timestamp_now-ts0);
        if (!time_sync_valid)
            $fatal(1, "TIME_SYNC_VALID_FAIL");

        // WMS stub must produce scan_start in a short simulation window.
        for (i = 0; i < 24; i = i + 1) begin
            @(posedge clk); #1;
            if (scan_start) scan_seen = scan_seen + 1;
        end
        if (scan_seen < 2)
            $fatal(1, "WMS_REFERENCE_SCAN_FAIL count=%0d", scan_seen);

        // cfg_bus: full write/read, byte write and invalid-address error.
        u_cfg_bfm.cfg_write32(32'h0000_9010, 32'h1234_5678);
        if (u_cfg_bfm.last_error)
            $fatal(1, "CFG_WRITE_UNEXPECTED_ERROR");
        u_cfg_bfm.cfg_read32(32'h0000_9010, cfg_readback);
        if (cfg_readback !== 32'h1234_5678)
            $fatal(1, "CFG_READBACK_FAIL actual=%h", cfg_readback);
        u_cfg_bfm.cfg_write_masked(32'h0000_9010, 32'h0000_AA00, 4'b0010);
        u_cfg_bfm.cfg_read32(32'h0000_9010, cfg_readback);
        if (cfg_readback !== 32'h1234_AA78)
            $fatal(1, "CFG_WSTRB_FAIL actual=%h", cfg_readback);
        u_cfg_bfm.cfg_expect_error_read(32'h0000_9098);

        // sample_stream checker/backpressure.
        for (i = 0; i < 10; i = i + 1)
            send_sample(32'hA500_0000 + i, i[7:0]);
        repeat(10) @(posedge clk);
        if (sample_count !== 10)
            $fatal(1, "SAMPLE_COUNT_FAIL count=%0d", sample_count);

        // Two multi-beat HMP messages through the common msg FIFO.
        send_msg_beat(32'h0001_0002, 4'hF, 1'b1, 1'b0, 64'd1000);
        send_msg_beat(32'h0100_0904, 4'hF, 1'b0, 1'b0, 64'd1000);
        send_msg_beat(32'h41F4_7AE1, 4'hF, 1'b0, 1'b1, 64'd1000);
        send_msg_beat(32'h0001_0001, 4'hF, 1'b1, 1'b0, 64'd1001);
        send_msg_beat(32'h0101_0904, 4'hF, 1'b0, 1'b0, 64'd1001);
        send_msg_beat(32'h41C8_0000, 4'hF, 1'b0, 1'b1, 64'd1001);
        repeat(40) @(posedge clk);
        if (msg_count !== 2 || msg_beat_count !== 6)
            $fatal(1, "MSG_STREAM_FAIL messages=%0d beats=%0d", msg_count, msg_beat_count);
        if (msg_fifo_full_stall)
            $fatal(1, "MSG_FIFO_UNEXPECTED_FULL_STALL");

        // One four-beat DILA fragment through bulk FIFO.
        send_bulk_beat(32'h0002_0000, 4'hF, 1'b1, 1'b0, 64'd2000, 32'd9);
        send_bulk_beat(32'h0000_0001, 4'hF, 1'b0, 1'b0, 64'd2000, 32'd9);
        send_bulk_beat(32'h0000_0002, 4'hF, 1'b0, 1'b0, 64'd2000, 32'd9);
        send_bulk_beat(32'hDEAD_BEEF, 4'hF, 1'b0, 1'b1, 64'd2000, 32'd9);
        repeat(30) @(posedge clk);
        if (bulk_frame_count !== 1 || bulk_beat_count !== 4)
            $fatal(1, "BULK_STREAM_FAIL frames=%0d beats=%0d", bulk_frame_count, bulk_beat_count);

        // Pulse CDC.
        @(negedge clk); cdc_src_pulse = 1'b1;
        @(negedge clk); cdc_src_pulse = 1'b0;
        fork
            begin : WAIT_PULSE
                repeat(20) begin
                    @(posedge clk2); #1;
                    if (cdc_dst_pulse) begin
                        pulse_seen = 1;
                        disable WAIT_PULSE;
                    end
                end
            end
        join
        if (!pulse_seen)
            $fatal(1, "CDC_PULSE_FAIL");

        // Bundled-data CDC.
        while (!cdc_bus_ready) @(posedge clk);
        @(negedge clk);
        cdc_bus_data = 32'hCAFE_BABE;
        cdc_bus_valid = 1'b1;
        @(negedge clk);
        cdc_bus_valid = 1'b0;
        begin : WAIT_BUS_CDC
            integer bus_wait;
            bus_wait = 0;
            while (!cdc_bus_dst_valid && bus_wait < 30) begin
                @(posedge clk2); #1;
                bus_wait = bus_wait + 1;
            end
            if (!cdc_bus_dst_valid || cdc_bus_dst_data !== 32'hCAFE_BABE)
                $fatal(1, "CDC_BUS_FAIL valid=%b data=%h", cdc_bus_dst_valid, cdc_bus_dst_data);
        end

        // Async FIFO: write four words at 100 MHz, read them at clk2.
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            while (!af_wr_ready) @(negedge clk);
            af_wr_valid = 1'b1;
            af_wr_data = 32'hD000_0000 + i;
            @(negedge clk);
            af_wr_valid = 1'b0;
        end
        repeat(6) @(posedge clk2);
        expected_af = 32'hD000_0000;
        af_rd_ready = 1'b1;
        for (i = 0; i < 4; i = i + 1) begin : READ_AF
            integer read_wait;
            read_wait = 0;
            while (!af_rd_valid && read_wait < 30) begin
                @(posedge clk2); #1;
                read_wait = read_wait + 1;
            end
            if (!af_rd_valid)
                $fatal(1, "ASYNC_FIFO_TIMEOUT index=%0d", i);
            if (af_rd_data !== expected_af)
                $fatal(1, "ASYNC_FIFO_DATA_FAIL expected=%h actual=%h", expected_af, af_rd_data);
            @(posedge clk2); #1;
            expected_af = expected_af + 1'b1;
        end
        af_rd_ready = 1'b0;

        $display("PREDEV_COMMON_V12_PASS");
        $finish;
    end
endmodule
