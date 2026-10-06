`timescale 1ns/1ps

module tb_uart;
    localparam integer SYS_CLK_HZ = 100_000_000;

    reg sys_clk = 1'b0;
    reg rst_sys_n = 1'b0;
    always #5 sys_clk = ~sys_clk;

    reg enable = 1'b1;
    reg [31:0] tx_baud_hz = 32'd115200;
    reg [31:0] rx_baud_hz = 32'd115200;
    reg [3:0] tx_data_bits = 4'd8;
    reg [1:0] tx_parity_mode = 2'd0;
    reg [1:0] tx_stop_bits = 2'd1;
    reg tx_byte_valid = 1'b0;
    wire tx_byte_ready;
    reg [7:0] tx_byte_data = 8'd0;
    wire txd;
    wire tx_busy;
    wire tx_done;

    reg [3:0] rx_data_bits = 4'd8;
    reg [1:0] rx_parity_mode = 2'd0;
    reg [1:0] rx_stop_bits = 2'd1;
    wire rx_byte_valid;
    reg rx_byte_ready = 1'b1;
    wire [7:0] rx_byte_data;
    wire rx_start;
    wire rx_framing_error;
    wire rx_parity_error;
    wire rx_busy;

    reg manual_mode = 1'b0;
    reg manual_rxd = 1'b1;
    wire serial_line = manual_mode ? manual_rxd : txd;

    integer parity_error_count = 0;
    integer framing_error_count = 0;
    integer done_count = 0;
    integer start_count = 0;
    reg continuous_capture = 1'b0;
    integer continuous_count = 0;
    reg [7:0] continuous_data0;
    reg [7:0] continuous_data1;

    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) dut_tx (
        .sys_clk(sys_clk), .rst_sys_n(rst_sys_n), .enable(enable),
        .baud_hz(tx_baud_hz), .data_bits(tx_data_bits),
        .parity_mode(tx_parity_mode), .stop_bits(tx_stop_bits),
        .byte_valid(tx_byte_valid), .byte_ready(tx_byte_ready),
        .byte_data(tx_byte_data), .txd(txd), .busy(tx_busy),
        .frame_done_pulse(tx_done)
    );

    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) dut_rx (
        .sys_clk(sys_clk), .rst_sys_n(rst_sys_n), .enable(enable),
        .baud_hz(rx_baud_hz), .data_bits(rx_data_bits),
        .parity_mode(rx_parity_mode), .stop_bits(rx_stop_bits),
        .rxd(serial_line), .byte_valid(rx_byte_valid),
        .byte_ready(rx_byte_ready), .byte_data(rx_byte_data),
        .byte_start_pulse(rx_start),
        .framing_error_pulse(rx_framing_error),
        .parity_error_pulse(rx_parity_error), .busy(rx_busy)
    );

    always @(posedge sys_clk) begin
        if (rx_parity_error)
        begin
            parity_error_count = parity_error_count + 1;
        end
        if (rx_framing_error)
            framing_error_count = framing_error_count + 1;
        if (tx_done)
            done_count = done_count + 1;
        if (rx_start)
            start_count = start_count + 1;
        if (continuous_capture && rx_byte_valid && rx_byte_ready) begin
            if (continuous_count == 0)
                continuous_data0 = rx_byte_data;
            else if (continuous_count == 1)
                continuous_data1 = rx_byte_data;
            continuous_count = continuous_count + 1;
        end
    end

    task reset_dut;
        begin
            rst_sys_n = 1'b0;
            repeat (8) @(posedge sys_clk);
            rst_sys_n = 1'b1;
            repeat (8) @(posedge sys_clk);
        end
    endtask

    task send_and_expect;
        input [7:0] value;
        input [3:0] bits;
        input [1:0] parity;
        input [1:0] stops;
        input [31:0] tx_baud;
        input [31:0] rx_baud;
        integer watchdog;
        reg [7:0] expected;
        begin
            while (tx_busy || rx_busy || rx_byte_valid)
                @(posedge sys_clk);
            tx_baud_hz = tx_baud;
            rx_baud_hz = rx_baud;
            tx_data_bits = bits;
            rx_data_bits = bits;
            tx_parity_mode = parity;
            rx_parity_mode = parity;
            tx_stop_bits = stops;
            rx_stop_bits = stops;
            expected = (bits == 7) ? {1'b0, value[6:0]} : value;
            @(negedge sys_clk);
            tx_byte_data = value;
            tx_byte_valid = 1'b1;
            while (!tx_byte_ready)
                @(negedge sys_clk);
            @(posedge sys_clk);
            @(negedge sys_clk);
            tx_byte_valid = 1'b0;

            watchdog = 0;
            while (!rx_byte_valid && watchdog < 2_000_000) begin
                @(posedge sys_clk);
                watchdog = watchdog + 1;
            end
            if (!rx_byte_valid)
                $fatal(1, "UART_RX_TIMEOUT tx_baud=%0d rx_baud=%0d format=%0d/%0d/%0d",
                       tx_baud, rx_baud, bits, parity, stops);
            if (rx_byte_data !== expected)
                $fatal(1, "UART_DATA_MISMATCH expected=%h actual=%h", expected, rx_byte_data);
            @(posedge sys_clk);
        end
    endtask

    task send_manual_bad_stop;
        input [7:0] value;
        input [31:0] baud;
        integer bit_clks;
        integer i;
        begin
            bit_clks = (SYS_CLK_HZ + baud/2) / baud;
            tx_baud_hz = baud;
            rx_baud_hz = baud;
            rx_data_bits = 4'd8;
            rx_parity_mode = 2'd0;
            rx_stop_bits = 2'd1;
            manual_mode = 1'b1;
            manual_rxd = 1'b1;
            repeat (bit_clks) @(posedge sys_clk);
            manual_rxd = 1'b0;
            repeat (bit_clks) @(posedge sys_clk);
            for (i = 0; i < 8; i = i + 1) begin
                manual_rxd = value[i];
                repeat (bit_clks) @(posedge sys_clk);
            end
            manual_rxd = 1'b0;
            repeat (bit_clks) @(posedge sys_clk);
            manual_rxd = 1'b1;
            repeat (bit_clks * 2) @(posedge sys_clk);
            manual_mode = 1'b0;
        end
    endtask

    integer before_count;
    reg [7:0] held_data;
    integer i;
    initial begin
        reset_dut();

        send_and_expect(8'hA5, 4'd8, 2'd0, 2'd1, 32'd115200, 32'd115200);
        send_and_expect(8'h3C, 4'd8, 2'd0, 2'd2, 32'd115200, 32'd115200);
        send_and_expect(8'hD5, 4'd7, 2'd1, 2'd1, 32'd115200, 32'd115200);
        send_and_expect(8'h5A, 4'd8, 2'd1, 2'd1, 32'd115200, 32'd115200);
        send_and_expect(8'h96, 4'd8, 2'd2, 2'd1, 32'd115200, 32'd115200);

        send_and_expect(8'h11, 4'd8, 2'd0, 2'd1, 32'd9600, 32'd9600);
        send_and_expect(8'h22, 4'd8, 2'd0, 2'd1, 32'd19200, 32'd19200);
        send_and_expect(8'h33, 4'd8, 2'd0, 2'd1, 32'd38400, 32'd38400);
        send_and_expect(8'h44, 4'd8, 2'd0, 2'd1, 32'd500000, 32'd500000);
        send_and_expect(8'h55, 4'd8, 2'd0, 2'd1, 32'd921600, 32'd921600);
        send_and_expect(8'h6C, 4'd8, 2'd0, 2'd1, 32'd115200, 32'd117000);

        while (tx_busy || rx_busy || rx_byte_valid)
            @(posedge sys_clk);
        tx_baud_hz = 32'd115200;
        rx_baud_hz = 32'd115200;
        tx_data_bits = 4'd8;
        rx_data_bits = 4'd8;
        tx_parity_mode = 2'd0;
        rx_parity_mode = 2'd0;
        tx_stop_bits = 2'd1;
        rx_stop_bits = 2'd1;
        rx_byte_ready = 1'b0;
        @(negedge sys_clk);
        tx_byte_data = 8'hC3;
        tx_byte_valid = 1'b1;
        while (!tx_byte_ready)
            @(negedge sys_clk);
        @(posedge sys_clk);
        @(negedge sys_clk);
        tx_byte_valid = 1'b0;
        while (!rx_byte_valid)
            @(posedge sys_clk);
        held_data = rx_byte_data;
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge sys_clk);
            if (!rx_byte_valid || (rx_byte_data !== held_data))
                $fatal(1, "UART_BACKPRESSURE_STABILITY_FAIL");
        end
        rx_byte_ready = 1'b1;
        @(posedge sys_clk);

        before_count = parity_error_count;
        while (tx_busy || rx_busy || rx_byte_valid)
            @(posedge sys_clk);
        tx_parity_mode = 2'd2;
        rx_parity_mode = 2'd1;
        @(negedge sys_clk);
        tx_byte_data = 8'h35;
        tx_byte_valid = 1'b1;
        while (!tx_byte_ready)
            @(negedge sys_clk);
        @(posedge sys_clk);
        @(negedge sys_clk);
        tx_byte_valid = 1'b0;
        while (!rx_byte_valid)
            @(posedge sys_clk);
        repeat (3) @(posedge sys_clk);
        if (parity_error_count != before_count + 1)
            $fatal(1, "UART_PARITY_ERROR_NOT_DETECTED");

        while (tx_busy || rx_busy || rx_byte_valid)
            @(posedge sys_clk);
        before_count = framing_error_count;
        send_manual_bad_stop(8'h69, 32'd115200);
        repeat (100) @(posedge sys_clk);
        if (framing_error_count != before_count + 1)
            $fatal(1, "UART_FRAMING_ERROR_NOT_DETECTED");

        while (tx_busy || rx_busy || rx_byte_valid)
            @(posedge sys_clk);
        tx_baud_hz = 32'd115200;
        rx_baud_hz = 32'd115200;
        tx_data_bits = 4'd8;
        rx_data_bits = 4'd8;
        tx_parity_mode = 2'd0;
        rx_parity_mode = 2'd0;
        tx_stop_bits = 2'd1;
        rx_stop_bits = 2'd1;
        rx_byte_ready = 1'b1;
        continuous_count = 0;
        continuous_capture = 1'b1;
        @(negedge sys_clk);
        tx_byte_data = 8'h12;
        tx_byte_valid = 1'b1;
        @(posedge sys_clk);
        @(negedge sys_clk);
        tx_byte_data = 8'h34;
        while (!tx_byte_ready)
            @(negedge sys_clk);
        @(posedge sys_clk);
        @(negedge sys_clk);
        tx_byte_valid = 1'b0;
        while (continuous_count < 2)
            @(posedge sys_clk);
        continuous_capture = 1'b0;
        if ((continuous_data0 != 8'h12) || (continuous_data1 != 8'h34))
            $fatal(1, "UART_CONTINUOUS_BYTES_FAIL first=%h second=%h",
                   continuous_data0, continuous_data1);

        while (tx_busy || rx_busy || rx_byte_valid)
            @(posedge sys_clk);
        before_count = start_count;
        manual_mode = 1'b1;
        manual_rxd = 1'b0;
        repeat (2) @(posedge sys_clk);
        manual_rxd = 1'b1;
        repeat (200) @(posedge sys_clk);
        manual_mode = 1'b0;
        if (rx_byte_valid)
            $fatal(1, "UART_START_GLITCH_ACCEPTED_AS_BYTE");

        if (done_count < 15)
            $fatal(1, "UART_FRAME_DONE_COUNT_TOO_SMALL count=%0d", done_count);
        $display("UART_REGRESSION_PASS done=%0d starts=%0d parity_err=%0d frame_err=%0d",
                 done_count, start_count, parity_error_count, framing_error_count);
        $finish;
    end
endmodule
