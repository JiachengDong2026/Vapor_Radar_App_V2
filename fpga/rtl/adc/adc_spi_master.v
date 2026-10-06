`timescale 1ns/1ps
// Mode 0, MSB first, 24-bit transaction. SDIO is released for read data.
module adc_spi_master #(
    parameter integer HALF_TICKS = 10,
    // One retains the original ADC3660 completion timing; AD4630 selects two.
    parameter integer CS_HOLD_TICKS = 1
)(
    input wire clk, input wire rst_n,
    input wire start, input wire [23:0] tx_word,
    input wire read_enable, input wire sdi,
    output reg cs_n, output reg sck, output wire sdo,
    output wire sdo_enable, output reg busy,
    output reg done, output reg [7:0] read_data
);
    reg [23:0] shift;
    reg [5:0] bit_count;
    reg [15:0] ticks;
    reg reading;
    reg finishing;
    assign sdo = shift[23];
    assign sdo_enable = !(reading && bit_count >= 16);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_n <= 1; sck <= 0; busy <= 0; done <= 0;
            shift <= 0; bit_count <= 0; ticks <= 0;
            reading <= 0; read_data <= 0; finishing <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                cs_n <= 1; sck <= 0;
                if (start && (CS_HOLD_TICKS == 1 || !done)) begin
                    shift <= tx_word; reading <= read_enable;
                    bit_count <= 0; ticks <= HALF_TICKS-1;
                    busy <= 1; cs_n <= 0; read_data <= 0;
                end
            end else if (finishing) begin
                if (ticks != 0) ticks <= ticks-1'b1;
                else begin
                    cs_n <= 1; busy <= 0; done <= 1; finishing <= 0;
                end
            end else if (ticks != 0) ticks <= ticks-1'b1;
            else begin
                ticks <= HALF_TICKS-1;
                if (!sck) begin
                    sck <= 1;
                    if (bit_count >= 16) read_data <= {read_data[6:0],sdi};
                end else begin
                    sck <= 0;
                    if (bit_count == 23) begin
                        if (CS_HOLD_TICKS == 1) begin
                            // Preserve the qualified ADC3660 default waveform.
                            busy <= 0; done <= 1;
                        end else begin
                            // Count full SYS periods from this final falling edge.
                            finishing <= 1; ticks <= CS_HOLD_TICKS-1;
                        end
                    end else begin
                        shift <= {shift[22:0],1'b0};
                        bit_count <= bit_count+1'b1;
                    end
                end
            end
        end
    end
endmodule

