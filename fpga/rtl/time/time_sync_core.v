`include "register_map.vh"
`include "error_codes.vh"
`default_nettype none
module time_sync_core #(
    parameter integer SYS_CLK_HZ = 100000000,
    parameter integer CHECK_CLOCK_VALID = 0
)(
    input wire sys_clk, rst_sys_n, sync_in_async,
    input wire [63:0] gnss_time_tag,
    input wire gnss_time_tag_valid,
    output reg [63:0] timestamp_now,
    output reg sync_valid,
    output reg [31:0] sync_seq,
    output reg sync_event_pulse,
    output reg [63:0] sync_event_tick,
    output reg [63:0] sync_event_gnss_tag,
    output reg sync_event_gnss_valid,
    output reg [31:0] error_status,
    input wire cfg_valid, cfg_write,
    input wire [31:0] cfg_addr, cfg_wdata,
    input wire [3:0] cfg_wstrb,
    output wire cfg_ready,
    output reg [31:0] cfg_rdata,
    output reg cfg_error,
    input wire clock_valid,
    output reg [3:0] cfg_error_code
);
    localparam integer MS_TICKS = SYS_CLK_HZ / 1000;
    (* ASYNC_REG = "TRUE" *) reg sync_meta, sync_level;
    reg sync_previous, enabled, falling_edge, seen_edge;
    reg [31:0] timeout_ms, sub_ms, elapsed_ms;
    reg [31:0] interval, minimum_interval, maximum_interval;
    reg [63:0] latest_gnss_tag;
    reg latest_gnss_valid;
    reg [31:0] tag_age_ms;
    reg [31:0] tick_snapshot_hi, sync_snapshot_hi;
    wire page_hit = cfg_addr[31:8] == `REG_BASE_TIME_SYNC >> 8;
    wire [7:0] ofs = cfg_addr[7:0];
    wire edge_hit = falling_edge ? (sync_previous && !sync_level) : (!sync_previous && sync_level);
    wire clock_good = !CHECK_CLOCK_VALID || clock_valid;
    wire [63:0] interval64 = timestamp_now - sync_event_tick;
    wire [31:0] measured_interval = |interval64[63:32] ? 32'hffffffff : interval64[31:0];
    wire [31:0] write_mask = {{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    function [31:0] merge_bytes;
        input [31:0] old_value, new_value, mask;
        begin merge_bytes = (old_value & ~mask) | (new_value & mask); end
    endfunction
    assign cfg_ready = cfg_valid && page_hit;
    reg [31:0] merged;
    reg known_register,writable_register;
    always @* begin
        cfg_rdata = 0; cfg_error = 0; merged = 0;cfg_error_code=0;known_register=1;writable_register=0;
        if (cfg_ready) begin
            if (ofs[1:0] != 0) cfg_error = 1;
            else case (ofs)
                8'h00: begin cfg_rdata = 32'h00020101; if(cfg_write) cfg_error=1; end
                8'h04: begin
                    cfg_rdata = {31'd0,enabled};
                    if (cfg_write && (cfg_wdata & write_mask & ~32'h3) != 0) cfg_error=1;
                end
                8'h08: begin
                    cfg_rdata = {23'd0,sync_valid,(|error_status),2'b0,sync_valid,2'b0,1'b1,enabled};
                    if(cfg_write) cfg_error=1;
                end
                8'h0c: cfg_rdata = error_status;
                8'h10: begin cfg_rdata=timestamp_now[31:0]; if(cfg_write) cfg_error=1; end
                8'h14: begin cfg_rdata=tick_snapshot_hi; if(cfg_write) cfg_error=1; end
                8'h18: begin cfg_rdata=sync_event_tick[31:0]; if(cfg_write) cfg_error=1; end
                8'h1c: begin cfg_rdata=sync_snapshot_hi; if(cfg_write) cfg_error=1; end
                8'h20: begin cfg_rdata=sync_seq; if(cfg_write) cfg_error=1; end
                8'h24: begin
                    cfg_rdata={31'd0,falling_edge};
                    merged=merge_bytes(cfg_rdata,cfg_wdata,write_mask);
                    if(cfg_write && merged>1) cfg_error=1;
                end
                8'h28: begin
                    cfg_rdata=timeout_ms; merged=merge_bytes(timeout_ms,cfg_wdata,write_mask);
                    if(cfg_write && (merged==0 || merged>3600000)) cfg_error=1;
                end
                8'h2c: begin cfg_rdata=interval; if(cfg_write) cfg_error=1; end
                8'h30: begin cfg_rdata=minimum_interval; if(cfg_write) cfg_error=1; end
                8'h34: begin cfg_rdata=maximum_interval; if(cfg_write) cfg_error=1; end
                8'h38: cfg_rdata=latest_gnss_tag[31:0];
                8'h3c: cfg_rdata=latest_gnss_tag[63:32];
                8'h40: begin cfg_rdata={31'd0,latest_gnss_valid}; if(cfg_write) cfg_error=1; end
                default: begin cfg_error=1;known_register=0;end
            endcase
            case(ofs)
                8'h04,8'h0c,8'h24,8'h28,8'h38,8'h3c:writable_register=1;
                default:writable_register=0;
            endcase
            if(cfg_error)begin
                if(ofs[1:0]!=0 || !known_register)cfg_error_code=5;
                else if(cfg_write && !writable_register)cfg_error_code=6;
                else cfg_error_code=7;
            end
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            timestamp_now<=0; sync_meta<=0; sync_level<=0; sync_previous<=0;
            enabled<=1; falling_edge<=0; seen_edge<=0; timeout_ms<=2000;
            sub_ms<=0; elapsed_ms<=0; interval<=0; minimum_interval<=0; maximum_interval<=0;
            sync_valid<=0; sync_seq<=0; sync_event_pulse<=0; sync_event_tick<=0;
            sync_event_gnss_tag<=0; sync_event_gnss_valid<=0;
            latest_gnss_tag<=0; latest_gnss_valid<=0; error_status<=0;tag_age_ms<=0;
            tick_snapshot_hi<=0;sync_snapshot_hi<=0;
        end else begin
            if(clock_good)timestamp_now<=timestamp_now+1'b1;
            sync_meta<=sync_in_async; sync_level<=sync_meta; sync_previous<=sync_level;
            sync_event_pulse<=0;
            if (clock_good && sub_ms == MS_TICKS-1) begin
                sub_ms<=0;
                if (tag_age_ms < timeout_ms) tag_age_ms<=tag_age_ms+1'b1;
                else latest_gnss_valid<=0;
                if (enabled) begin
                    if (elapsed_ms < timeout_ms) elapsed_ms<=elapsed_ms+1'b1;
                    if (elapsed_ms >= timeout_ms-1) begin sync_valid<=0; error_status<=error_status|`ERR_TIMEOUT; end
                end
            end else if(clock_good)sub_ms<=sub_ms+1'b1;
            if (cfg_ready && !cfg_write) begin
                if (ofs==8'h10) tick_snapshot_hi<=timestamp_now[63:32];
                if (ofs==8'h18) sync_snapshot_hi<=sync_event_tick[63:32];
            end
            if (cfg_ready && cfg_write && !cfg_error) begin
                case(ofs)
                    8'h04: if(cfg_wstrb[0]) begin
                        enabled<=cfg_wdata[0];
                        if(!cfg_wdata[0] || cfg_wdata[1]) begin
                            sync_valid<=0; seen_edge<=0; elapsed_ms<=0;
                            // The local time never resets on a module soft reset.
                            if(cfg_wdata[1]) begin interval<=0;minimum_interval<=0;maximum_interval<=0;error_status<=0; end
                        end
                    end
                    8'h0c: error_status<=error_status & ~(cfg_wdata & write_mask);
                    8'h24: begin falling_edge<=merged[0];seen_edge<=0;sync_valid<=0;elapsed_ms<=0;end
                    8'h28: begin timeout_ms<=merged;elapsed_ms<=0;end
                    8'h38: begin latest_gnss_tag[31:0]<=merge_bytes(latest_gnss_tag[31:0],cfg_wdata,write_mask);latest_gnss_valid<=0;end
                    8'h3c: begin latest_gnss_tag[63:32]<=merge_bytes(latest_gnss_tag[63:32],cfg_wdata,write_mask);latest_gnss_valid<=1;tag_age_ms<=0;end
                    default: begin end
                endcase
            end
            if(gnss_time_tag_valid) begin latest_gnss_tag<=gnss_time_tag;latest_gnss_valid<=1;tag_age_ms<=0;end
            if (clock_good && enabled && edge_hit && !(cfg_ready && cfg_write && (ofs==8'h04 || ofs==8'h24))) begin
                sync_event_tick<=timestamp_now; sync_event_pulse<=1;sync_seq<=sync_seq+1'b1;
                sync_event_gnss_tag<=gnss_time_tag_valid ? gnss_time_tag : latest_gnss_tag;
                sync_event_gnss_valid<=gnss_time_tag_valid || latest_gnss_valid;
                sync_valid<=1;elapsed_ms<=0;sub_ms<=0;
                seen_edge<=1;
                if(seen_edge) begin
                    interval<=measured_interval;
                    if(minimum_interval==0 || measured_interval<minimum_interval) minimum_interval<=measured_interval;
                    if(measured_interval>maximum_interval) maximum_interval<=measured_interval;
                end
            end
            if(!clock_good)begin
                sync_valid<=0;seen_edge<=0;sync_event_pulse<=0;
                latest_gnss_valid<=0;sync_event_gnss_valid<=0;
                elapsed_ms<=0;sub_ms<=0;tag_age_ms<=0;
                error_status<=error_status | 32'h20;
            end
        end
    end
endmodule
`default_nettype wire
