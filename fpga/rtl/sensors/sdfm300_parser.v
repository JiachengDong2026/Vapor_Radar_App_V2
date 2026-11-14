`timescale 1ns/1ps
// SDFM300 only: 5C, centimetres LE16, ~(low+high). Header is excluded.
module sdfm300_parser (
    input wire sys_clk, rst_sys_n, enable,
    input wire [7:0] byte_data,
    input wire byte_valid, byte_start, byte_error,
    input wire [63:0] timestamp_now,
    input wire time_sync_valid,
    input wire [31:0] gap_ticks,
    output reg frame_pulse, distance_pulse, checksum_pulse,
    output reg invalid_pulse, format_pulse, timeout_pulse,
    output reg [31:0] distance_mm,
    output reg [63:0] frame_timestamp,
    output reg frame_sync
);
    reg [1:0] pos;
    reg [7:0] low_byte, high_byte, checksum;
    reg [31:0] gap;
    reg [63:0] byte_timestamp;
    reg byte_sync;
    wire [15:0] distance_cm={high_byte,low_byte};
    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            pos<=0; low_byte<=0; high_byte<=0; checksum<=0; gap<=0;
            byte_timestamp<=0; byte_sync<=0; frame_timestamp<=0; frame_sync<=0;
            frame_pulse<=0; distance_pulse<=0; checksum_pulse<=0;
            invalid_pulse<=0; format_pulse<=0; timeout_pulse<=0; distance_mm<=0;
        end else begin
            frame_pulse<=0; distance_pulse<=0; checksum_pulse<=0;
            invalid_pulse<=0; format_pulse<=0; timeout_pulse<=0;
            if (byte_start) begin byte_timestamp<=timestamp_now; byte_sync<=time_sync_valid; end
            if (!enable) begin pos<=0; gap<=0; end
            else if (byte_error) begin pos<=0; gap<=0; format_pulse<=1; end
            else if (byte_valid) begin
                gap<=0;
                case(pos)
                    0: if (byte_data==8'h5c) begin
                        pos<=1; frame_timestamp<=byte_timestamp; frame_sync<=byte_sync;
                    end
                    1: begin low_byte<=byte_data; checksum<=byte_data; pos<=2; end
                    2: begin high_byte<=byte_data; checksum<=checksum+byte_data; pos<=3; end
                    3: begin
                        pos<=0;
                        if (byte_data!=~checksum) begin
                            checksum_pulse<=1;
                            // Reuse a possible next header after corruption or byte loss.
                            if (byte_data==8'h5c) begin
                                pos<=1; frame_timestamp<=byte_timestamp; frame_sync<=byte_sync;
                            end
                        end else begin
                            frame_pulse<=1;
                            if (distance_cm<5 || distance_cm>30000) invalid_pulse<=1;
                            else begin distance_mm<={16'd0,distance_cm}*32'd10; distance_pulse<=1; end
                        end
                    end
                endcase
            end else if (pos!=0) begin
                if (gap>=gap_ticks-1) begin pos<=0; gap<=0; timeout_pulse<=1; end
                else gap<=gap+1'b1;
            end
        end
    end
endmodule
