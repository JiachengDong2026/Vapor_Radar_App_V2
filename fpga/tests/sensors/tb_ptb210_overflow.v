`timescale 1ns/1ps

module tb_ptb210_overflow;
    localparam integer SYS_CLK_HZ = 10_000_000;
    localparam [31:0] BASE = 32'h0000_6000;

    reg sys_clk = 1'b0;
    reg rst_sys_n = 1'b0;
    always #50 sys_clk = ~sys_clk;

    reg [63:0] timestamp_now = 64'd0;
    always @(posedge sys_clk)
        if (rst_sys_n)
            timestamp_now <= timestamp_now + 1'b1;

    wire host_txd;
    wire host_rxd;
    reg cfg_valid = 1'b0;
    reg cfg_write = 1'b0;
    reg [31:0] cfg_addr = 32'd0;
    reg [31:0] cfg_wdata = 32'd0;
    reg [3:0] cfg_wstrb = 4'd0;
    wire cfg_ready;
    wire [31:0] cfg_rdata;
    wire cfg_error;
    wire m_valid;
    reg m_ready = 1'b0;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire m_sof;
    wire m_last;
    wire [15:0] m_source_id;
    wire [15:0] m_msg_id;
    wire [63:0] m_timestamp;
    wire [31:0] m_cycle_id;
    wire [31:0] m_flags;
    wire [31:0] model_poll_count;
    wire [31:0] model_bp_count;
    wire model_form_seen;
    wire model_reset_seen;

    ptb210_rs232 #(
        .SYS_CLK_HZ(SYS_CLK_HZ), .FIFO_DEPTH(8), .AUTO_INIT(0)
    ) dut (
        .sys_clk(sys_clk), .rst_sys_n(rst_sys_n),
        .uart_rxd(host_rxd), .uart_txd(host_txd),
        .timestamp_now(timestamp_now), .time_sync_valid(1'b0),
        .time_sync_seq(32'd0),
        .cfg_valid(cfg_valid), .cfg_write(cfg_write), .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata), .cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready), .cfg_rdata(cfg_rdata), .cfg_error(cfg_error),
        .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data),
        .m_keep(m_keep), .m_sof(m_sof), .m_last(m_last),
        .m_source_id(m_source_id), .m_msg_id(m_msg_id),
        .m_timestamp(m_timestamp), .m_cycle_id(m_cycle_id), .m_flags(m_flags)
    );

    ptb210_model #(
        .SYS_CLK_HZ(SYS_CLK_HZ), .RESPONSE_DELAY_CLKS(1000), .REPEAT_VALID(1)
    ) model (
        .sys_clk(sys_clk), .rst_sys_n(rst_sys_n),
        .host_txd(host_txd), .host_rxd(host_rxd),
        .poll_count(model_poll_count), .bp_count(model_bp_count),
        .form_seen(model_form_seen), .reset_seen(model_reset_seen)
    );

    task cfg_write_full;
        input [31:0] address;
        input [31:0] data;
        begin
            @(negedge sys_clk);
            cfg_valid = 1'b1;
            cfg_write = 1'b1;
            cfg_addr = address;
            cfg_wdata = data;
            cfg_wstrb = 4'hF;
            @(posedge sys_clk);
            if (!cfg_ready || cfg_error)
                $fatal(1, "OVERFLOW_CFG_WRITE_FAIL addr=%h", address);
            @(negedge sys_clk);
            cfg_valid = 1'b0;
            cfg_write = 1'b0;
        end
    endtask

    task cfg_read_full;
        input [31:0] address;
        output [31:0] data;
        begin
            @(negedge sys_clk);
            cfg_valid = 1'b1;
            cfg_write = 1'b0;
            cfg_addr = address;
            cfg_wstrb = 4'd0;
            @(posedge sys_clk);
            if (!cfg_ready || cfg_error)
                $fatal(1, "OVERFLOW_CFG_READ_FAIL addr=%h", address);
            data = cfg_rdata;
            @(negedge sys_clk);
            cfg_valid = 1'b0;
        end
    endtask

    reg [31:0] value;
    integer watchdog;
    integer beat_count;
    initial begin
        #300_000_000;
        $fatal(1, "PTB_OVERFLOW_GLOBAL_TIMEOUT");
    end

    initial begin
        repeat (10) @(posedge sys_clk);
        rst_sys_n = 1'b1;
        repeat (10) @(posedge sys_clk);
        cfg_write_full(BASE + 32'h18, 32'd1);
        cfg_write_full(BASE + 32'h2C, 32'd30);
        cfg_write_full(BASE + 32'h04, 32'd1);

        watchdog = 0;
        value = 0;
        while ((value == 0) && (watchdog < 500000)) begin
            cfg_read_full(BASE + 32'h38, value);
            watchdog = watchdog + 1;
        end
        if (value == 0)
            $fatal(1, "PTB_FIFO_OVERFLOW_DROP_NOT_COUNTED");
        cfg_read_full(BASE + 32'h0C, value);
        if (!value[2])
            $fatal(1, "PTB_FIFO_OVERFLOW_ERROR_NOT_SET error=%h", value);

        m_ready = 1'b1;
        beat_count = 0;
        while (beat_count < 6) begin
            @(posedge sys_clk);
            if (m_valid)
                beat_count = beat_count + 1;
        end
        m_ready = 1'b0;

        cfg_write_full(BASE + 32'h04, 32'd9);
        repeat (5) @(posedge sys_clk);
        cfg_read_full(BASE + 32'h34, value);
        if (value != 0)
            $fatal(1, "PTB_CLEAR_FIFO_FAIL level=%0d", value);

        $display("PTB210_OVERFLOW_PASS polls=%0d drop_count=%0d", model_poll_count,
                 dut.drop_count_reg);
        $finish;
    end

    wire unused_outputs = ^{m_data, m_keep, m_sof, m_last, m_source_id, m_msg_id,
                            m_timestamp, m_cycle_id, m_flags, model_bp_count,
                            model_form_seen, model_reset_seen};
endmodule
