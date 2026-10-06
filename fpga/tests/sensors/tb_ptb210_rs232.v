`timescale 1ns/1ps

module tb_ptb210_rs232;
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
    reg time_sync_valid = 1'b1;
    reg [31:0] time_sync_seq = 32'd7;

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
        .SYS_CLK_HZ(SYS_CLK_HZ),
        .FIFO_DEPTH(256),
        .AUTO_INIT(1),
        .BOOT_DELAY_MS(1),
        .RESET_DELAY_MS(1)
    ) dut (
        .sys_clk(sys_clk), .rst_sys_n(rst_sys_n),
        .uart_rxd(host_rxd), .uart_txd(host_txd),
        .timestamp_now(timestamp_now), .time_sync_valid(time_sync_valid),
        .time_sync_seq(time_sync_seq),
        .cfg_valid(cfg_valid), .cfg_write(cfg_write), .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata), .cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready), .cfg_rdata(cfg_rdata), .cfg_error(cfg_error),
        .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data),
        .m_keep(m_keep), .m_sof(m_sof), .m_last(m_last),
        .m_source_id(m_source_id), .m_msg_id(m_msg_id),
        .m_timestamp(m_timestamp), .m_cycle_id(m_cycle_id), .m_flags(m_flags)
    );

    ptb210_model #(
        .SYS_CLK_HZ(SYS_CLK_HZ),
        .RESPONSE_DELAY_CLKS(1000)
    ) model (
        .sys_clk(sys_clk), .rst_sys_n(rst_sys_n),
        .host_txd(host_txd), .host_rxd(host_rxd),
        .poll_count(model_poll_count), .bp_count(model_bp_count),
        .form_seen(model_form_seen),
        .reset_seen(model_reset_seen)
    );

    task cfg_read;
        input [31:0] address;
        output [31:0] value;
        output error;
        begin
            @(negedge sys_clk);
            cfg_valid = 1'b1;
            cfg_write = 1'b0;
            cfg_addr = address;
            cfg_wdata = 32'd0;
            cfg_wstrb = 4'd0;
            @(posedge sys_clk);
            if (!cfg_ready)
                $fatal(1, "CFG_READ_NOT_READY addr=%h", address);
            value = cfg_rdata;
            error = cfg_error;
            @(negedge sys_clk);
            cfg_valid = 1'b0;
        end
    endtask

    task cfg_write_word;
        input [31:0] address;
        input [31:0] value;
        input [3:0] strobe;
        output error;
        begin
            @(negedge sys_clk);
            cfg_valid = 1'b1;
            cfg_write = 1'b1;
            cfg_addr = address;
            cfg_wdata = value;
            cfg_wstrb = strobe;
            @(posedge sys_clk);
            if (!cfg_ready)
                $fatal(1, "CFG_WRITE_NOT_READY addr=%h", address);
            error = cfg_error;
            @(negedge sys_clk);
            cfg_valid = 1'b0;
            cfg_write = 1'b0;
            cfg_wstrb = 4'd0;
        end
    endtask

    task expect_message;
        input [31:0] expected_pressure;
        input integer apply_backpressure;
        integer beat;
        integer hold_cycles;
        reg [31:0] held_data;
        reg [3:0] held_keep;
        reg held_sof;
        reg held_last;
        reg [63:0] held_timestamp;
        begin
            m_ready = 1'b0;
            while (!m_valid)
                @(posedge sys_clk);

            if (apply_backpressure != 0) begin
                held_data = m_data;
                held_keep = m_keep;
                held_sof = m_sof;
                held_last = m_last;
                held_timestamp = m_timestamp;
                for (hold_cycles = 0; hold_cycles < 50; hold_cycles = hold_cycles + 1) begin
                    @(posedge sys_clk);
                    if (!m_valid || (m_data !== held_data) || (m_keep !== held_keep) ||
                        (m_sof !== held_sof) || (m_last !== held_last) ||
                        (m_timestamp !== held_timestamp))
                        $fatal(1, "PTB_MSG_BACKPRESSURE_STABILITY_FAIL");
                end
            end

            for (beat = 0; beat < 3; beat = beat + 1) begin
                @(negedge sys_clk);
                m_ready = 1'b1;
                @(posedge sys_clk);
                if (!m_valid)
                    $fatal(1, "PTB_MSG_EARLY_END beat=%0d", beat);
                if ((m_source_id != 16'h0040) || (m_msg_id != 16'h1100) ||
                    (m_cycle_id != 32'hFFFF_FFFF) || (m_keep != 4'hF))
                    $fatal(1, "PTB_MSG_METADATA_FAIL beat=%0d", beat);
                if (!m_flags[0] || !m_flags[2])
                    $fatal(1, "PTB_MSG_TIMESTAMP_FLAGS_FAIL flags=%h", m_flags);
                if ((beat == 0) && ((!m_sof) || m_last || (m_data != 32'h0001_0001)))
                    $fatal(1, "PTB_MSG_HEADER_FAIL data=%h", m_data);
                if ((beat == 1) && (m_sof || m_last || (m_data != 32'h0407_0012)))
                    $fatal(1, "PTB_MSG_TLV_HEADER_FAIL data=%h", m_data);
                if ((beat == 2) && (m_sof || !m_last || (m_data != expected_pressure)))
                    $fatal(1, "PTB_MSG_PRESSURE_FAIL expected=%h actual=%h", expected_pressure, m_data);
            end
            @(negedge sys_clk);
            m_ready = 1'b0;
        end
    endtask

    reg [31:0] value;
    reg access_error;
    integer watchdog;
    initial begin
        #500_000_000;
        $fatal(1, "PTB_TEST_GLOBAL_TIMEOUT");
    end

    initial begin
        repeat (10) @(posedge sys_clk);
        rst_sys_n = 1'b1;
        repeat (10) @(posedge sys_clk);

        cfg_read(BASE + 32'h00, value, access_error);
        if (access_error || (value != 32'h0040_0100))
            $fatal(1, "PTB_ID_VERSION_FAIL value=%h error=%b", value, access_error);
        cfg_read(BASE + 32'h10, value, access_error);
        if (access_error || (value != 9600))
            $fatal(1, "PTB_DEFAULT_BAUD_FAIL value=%0d", value);
        cfg_read(BASE + 32'h14, value, access_error);
        if (access_error || (value != 32'h57))
            $fatal(1, "PTB_DEFAULT_FORMAT_FAIL value=%h", value);

        cfg_write_word(BASE + 32'h18, 32'd20, 4'hF, access_error);
        if (access_error)
            $fatal(1, "PTB_POLL_CONFIG_REJECTED");
        cfg_write_word(BASE + 32'h2C, 32'd50, 4'hF, access_error);
        if (access_error)
            $fatal(1, "PTB_TIMEOUT_CONFIG_REJECTED");
        cfg_write_word(BASE + 32'h18, 32'h0000_000A, 4'b0001, access_error);
        if (access_error)
            $fatal(1, "PTB_BYTE_STROBE_REJECTED");
        cfg_read(BASE + 32'h18, value, access_error);
        if (value != 10)
            $fatal(1, "PTB_BYTE_STROBE_FAIL value=%0d", value);

        cfg_write_word(BASE + 32'h10, 32'd1000, 4'hF, access_error);
        if (!access_error)
            $fatal(1, "PTB_BAD_BAUD_NOT_REJECTED");
        cfg_read(BASE + 32'h10, value, access_error);
        if (value != 9600)
            $fatal(1, "PTB_BAD_BAUD_CHANGED_REGISTER value=%0d", value);

        @(negedge sys_clk);
        cfg_valid = 1'b1;
        cfg_write = 1'b0;
        cfg_addr = 32'h0000_6100;
        @(posedge sys_clk);
        if (cfg_ready)
            $fatal(1, "PTB_RESPONDED_OUTSIDE_ADDRESS_PAGE");
        @(negedge sys_clk);
        cfg_valid = 1'b0;

        cfg_write_word(BASE + 32'h04, 32'd1, 4'hF, access_error);
        if (access_error)
            $fatal(1, "PTB_ENABLE_REJECTED");

        expect_message(32'd101_299_000, 1);
        if (!model_form_seen || !model_reset_seen)
            $fatal(1, "PTB_INIT_COMMAND_SEQUENCE_MISSING form=%b reset=%b",
                   model_form_seen, model_reset_seen);

        expect_message(-32'sd1_234_000, 0);

        watchdog = 0;
        while ((model_poll_count < 4) && (watchdog < 2_000_000)) begin
            @(posedge sys_clk);
            watchdog = watchdog + 1;
        end
        if (model_poll_count < 4)
            $fatal(1, "PTB_DID_NOT_REACH_TIMEOUT_VECTOR");

        watchdog = 0;
        value = 0;
        while ((value[0] == 0) && (watchdog < 2_000_000)) begin
            cfg_read(BASE + 32'h0C, value, access_error);
            watchdog = watchdog + 1;
        end
        if (!value[0])
            $fatal(1, "PTB_TIMEOUT_NOT_REPORTED error=%h", value);

        watchdog = 0;
        value = 0;
        while ((value < 2) && (watchdog < 2_000_000)) begin
            cfg_read(BASE + 32'h28, value, access_error);
            watchdog = watchdog + 1;
        end
        if (value < 2)
            $fatal(1, "PTB_PARSE_ERRORS_NOT_COUNTED count=%0d", value);

        expect_message(32'd99_901_000, 0);

        cfg_write_word(BASE + 32'h04, 32'd0, 4'hF, access_error);

        cfg_read(BASE + 32'h20, value, access_error);
        if (value != 32'd99_901_000)
            $fatal(1, "PTB_LAST_PRESSURE_REGISTER_FAIL value=%0d", value);
        cfg_read(BASE + 32'h24, value, access_error);
        if (value != 3)
            $fatal(1, "PTB_RX_FRAME_COUNT_FAIL value=%0d", value);

        repeat (200) @(posedge sys_clk);
        cfg_write_word(BASE + 32'h04, 32'd2, 4'hF, access_error);
        repeat (20) @(posedge sys_clk);
        cfg_read(BASE + 32'h24, value, access_error);
        if (value != 0)
            $fatal(1, "PTB_SOFT_RESET_COUNTER_FAIL value=%0d", value);

        cfg_write_word(BASE + 32'h1C, 32'd1, 4'hF, access_error);
        cfg_write_word(BASE + 32'h04, 32'd1, 4'hF, access_error);
        expect_message(32'd100_000_000, 0);
        if (model_bp_count != 1)
            $fatal(1, "PTB_CONTINUOUS_BP_COMMAND_FAIL count=%0d", model_bp_count);
        cfg_write_word(BASE + 32'h04, 32'd0, 4'hF, access_error);

        $display("PTB210_REGRESSION_PASS polls=%0d bp=%0d form=%b reset=%b",
                 model_poll_count, model_bp_count, model_form_seen, model_reset_seen);
        $finish;
    end
endmodule
