`timescale 1ns/1ps
// Byte-domain parser. LF DATA arrives D6 first; its units/flag mask are configurable.
module tfa1500_parser (
    input wire sys_clk, rst_sys_n, enable, high_mode,
    input wire [7:0] byte_data,
    input wire byte_valid, byte_start, byte_error,
    input wire [63:0] timestamp_now,
    input wire time_sync_valid,
    input wire [31:0] gap_ticks,
    input wire [15:0] lf_mm_per_count,
    input wire [7:0] lf_invalid_mask,
    output reg frame_pulse, distance_pulse, checksum_pulse,
    output reg invalid_pulse, format_pulse, timeout_pulse,
    output reg [31:0] distance_mm,
    output reg [7:0] apd_temp, device_status,
    output reg [63:0] frame_timestamp,
    output reg frame_sync
);
    reg [4:0] pos;
    reg [7:0] checksum, command, length;
    reg [7:0] payload [0:15];
    reg [31:0] gap;
    reg [63:0] byte_timestamp;
    reg byte_sync;
    wire [23:0] hf_raw = {payload[2],payload[1],payload[0]};
    wire [23:0] lf_raw = {payload[1],payload[2],payload[3]};
    wire [39:0] lf_scaled = lf_raw * lf_mm_per_count;
    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            pos<=0; checksum<=0; command<=0; length<=0; gap<=0;
            byte_timestamp<=0; byte_sync<=0; frame_timestamp<=0; frame_sync<=0;
            frame_pulse<=0; distance_pulse<=0; checksum_pulse<=0;
            invalid_pulse<=0; format_pulse<=0; timeout_pulse<=0;
            distance_mm<=0; apd_temp<=0; device_status<=0;
        end else begin
            frame_pulse<=0; distance_pulse<=0; checksum_pulse<=0;
            invalid_pulse<=0; format_pulse<=0; timeout_pulse<=0;
            if (byte_start) begin byte_timestamp<=timestamp_now; byte_sync<=time_sync_valid; end
            if (!enable) begin pos<=0; gap<=0; end
            else if (byte_error) begin pos<=0; gap<=0; format_pulse<=1; end
            else if (byte_valid) begin
                gap<=0;
                if (pos==0) begin
                    if (byte_data==(high_mode ? 8'h5c : 8'h55)) begin
                        pos<=1; checksum<=high_mode ? 0 : 8'h55;
                        frame_timestamp<=byte_timestamp; frame_sync<=byte_sync;
                    end
                end else if (high_mode) begin
                    if (pos<4) begin
                        payload[pos-1]<=byte_data; checksum<=checksum+byte_data; pos<=pos+1'b1;
                    end else begin
                        pos<=0;
                        if (byte_data!=~checksum) checksum_pulse<=1;
                        else begin
                            frame_pulse<=1;
                            if (hf_raw==24'h3fffff || hf_raw>130000) invalid_pulse<=1;
                            else begin distance_mm<=hf_raw*32'd10; distance_pulse<=1; end
                        end
                    end
                end else if (pos==1) begin
                    command<=byte_data; checksum<=checksum^byte_data; pos<=2;
                end else if (pos==2) begin
                    length<=byte_data; checksum<=checksum^byte_data;
                    if (byte_data>16) begin pos<=0; format_pulse<=1; end
                    else pos<=3;
                end else if (pos<length+3) begin
                    payload[pos-3]<=byte_data; checksum<=checksum^byte_data; pos<=pos+1'b1;
                end else begin
                    pos<=0;
                    if (byte_data!=checksum) checksum_pulse<=1;
                    else if ((command==1 || command==2) && length==7) begin
                        frame_pulse<=1; device_status<=payload[0]; apd_temp<=payload[6];
                        if ((payload[0]&lf_invalid_mask)!=0 || lf_scaled[39:32]!=0)
                            invalid_pulse<=1;
                        else begin distance_mm<=lf_scaled[31:0]; distance_pulse<=1; end
                    end else if ((command==0 && length==2) || (command==3 && length==8) ||
                                 command==8'he8 || command==8'hcb) begin
                        frame_pulse<=1;
                        if (command==3) apd_temp<=payload[5];
                    end else format_pulse<=1;
                end
            end else if (pos!=0) begin
                if (gap>=gap_ticks-1) begin pos<=0; gap<=0; timeout_pulse<=1; end
                else gap<=gap+1'b1;
            end
        end
    end
endmodule
