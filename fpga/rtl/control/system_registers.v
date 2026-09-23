`default_nettype none
module system_registers #(
    parameter integer SYS_CLK_HZ=100000000,GPIF_CLK_HZ=100000000,
    parameter [31:0] CAPABILITIES0=32'h0000ffff,
    parameter integer USE_EXTERNAL_CLOCK_FAULTS=0
)(
    input wire sys_clk,rst_sys_n,
    input wire [63:0] timestamp_now,
    input wire clock_locked,link_ready,acquisition_running,watchdog_expired,
    input wire [31:0] module_error_summary,module_irq,
    input wire [31:0] protocol_error_count,crc_error_count,
    input wire [31:0] tx_fifo_level,rx_fifo_level,total_drop_count,
    input wire [31:0] adc0_fifo_level,adc1_fifo_level,dila0_fifo_level,dila1_fifo_level,sensor_fifo_level,
    input wire [31:0] msg_pending_mask,bulk_pending_mask,
    input wire [63:0] arb_grant_count,tx_word_count,rx_word_count,
    input wire [31:0] gpif_stall_count,last_sequence_rx,last_sequence_tx,
    input wire cfg_valid,cfg_write,
    input wire [31:0] cfg_addr,cfg_wdata,
    input wire [3:0] cfg_wstrb,
    output wire cfg_ready,
    output reg cfg_error,
    output reg [31:0] cfg_rdata,
    output reg global_enable,soft_reset_pulse,watchdog_kick,
    output reg [31:0] watchdog_timeout_ms,reset_mask,
    output reg [63:0] stream_mask,raw_stream_mask,
    output reg arb_mode,
    output reg [31:0] max_high_burst,tx_high_water,
    output reg [31:0] fx3_reset_ms,
    output reg fx3_reset_request,
    output reg [31:0] error_summary,irq_summary,reset_reason,clock_fault_count,
    output reg stream_enable,usb_enable,
    output reg clock_reset_request,stream_reset_pulse,stream_clear_pulse,usb_clear_pulse,
    input wire [31:0] clock_fault_total,
    output reg [3:0] cfg_error_code
);
    wire [7:0] page=cfg_addr[15:8],offset=cfg_addr[7:0];
    wire selected=cfg_valid && cfg_addr[31:16]==0 && (page==0 || page==1 || page==8'h70 || page==8'h80);
    wire [31:0] mask={{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    reg [31:0] merged;
    reg known_register,writable_register;
    reg [31:0] uptime_hi,grant_hi,tx_hi,rx_hi;
    reg [31:0] displayed_drop_count,previous_drop_count;
    reg [31:0] clock_errors,stream_errors,usb_errors;
    reg [31:0] previous_protocol_count,previous_crc_count;
    reg was_locked,was_watchdog;
    reg [31:0] clock_fault_base,previous_clock_fault_total;
    wire external_clock_event=USE_EXTERNAL_CLOCK_FAULTS && clock_fault_total!=previous_clock_fault_total;
    wire clock_fault_event=USE_EXTERNAL_CLOCK_FAULTS ? external_clock_event : (was_locked && !clock_locked);
    // Upstream producers can reset while this diagnostic page is retained.
    // A decreasing total starts a new epoch, never a huge unsigned increment.
    wire [31:0] new_drops=total_drop_count<previous_drop_count ? total_drop_count :
        total_drop_count-previous_drop_count;
    wire watchdog_event=watchdog_expired && !was_watchdog;
    wire [31:0] clock_events=(!clock_locked || external_clock_event) ? 32'h20 : 32'd0;
    wire [31:0] stream_events=new_drops!=0 ? 32'h4 : 32'd0;
    wire [31:0] usb_events=(!link_ready && usb_enable ? 32'h8 : 32'd0) |
        ((protocol_error_count>previous_protocol_count || crc_error_count>previous_crc_count) ? 32'h2 : 32'd0);
    wire [31:0] system_events=module_error_summary | clock_errors | stream_errors | usb_errors |
        clock_events | stream_events | usb_events | (watchdog_event ? 32'h1 : 32'd0);
    wire write_fire=selected && cfg_write && !cfg_error;
    wire [31:0] write_bits=cfg_wdata & mask;
    wire [31:0] reason_clear=(write_fire && {page,offset}==16'h003c) ? write_bits : 32'd0;
    wire software_event=write_fire && {page,offset}==16'h0004 && write_bits[1];
    assign cfg_ready=selected;
    always @* begin
        cfg_error=0;cfg_rdata=0;merged=0;cfg_error_code=0;known_register=1;writable_register=1;
        if(selected)begin
            case({page,offset})
                16'h0000:cfg_rdata=32'h00010101;
                16'h0004:cfg_rdata={31'd0,global_enable};
                16'h0008:cfg_rdata={24'd0,(|error_summary),2'd0,link_ready,acquisition_running,1'b0,clock_locked,global_enable};
                16'h000c:cfg_rdata=error_summary;
                16'h0010:cfg_rdata=32'h20260916;
                16'h0014,16'h0018,16'h001c:cfg_rdata=0;
                16'h0020:cfg_rdata=CAPABILITIES0;
                16'h0024:cfg_rdata=timestamp_now[31:0];
                16'h0028:cfg_rdata=uptime_hi;
                16'h002c:cfg_rdata=stream_mask[31:0];
                16'h0030:cfg_rdata=stream_mask[63:32];
                16'h0034:cfg_rdata=raw_stream_mask[31:0];
                16'h0038:cfg_rdata=irq_summary;
                16'h003c:cfg_rdata=reset_reason;
                16'h0040:cfg_rdata=watchdog_timeout_ms;
                16'h0044:cfg_rdata=0;
                16'h0048:cfg_rdata=protocol_error_count;
                16'h004c:cfg_rdata=crc_error_count;
                16'h0050:cfg_rdata=raw_stream_mask[63:32];
                16'h0100:cfg_rdata=32'h00030101;
                16'h0104:cfg_rdata=1;
                16'h0108:cfg_rdata={24'd0,(|clock_errors),2'd0,clock_locked,2'd0,clock_locked,1'b1};
                16'h010c:cfg_rdata=clock_errors;
                16'h0110,16'h0114:cfg_rdata=SYS_CLK_HZ;
                16'h0118:cfg_rdata=GPIF_CLK_HZ;
                16'h011c:cfg_rdata={31'd0,clock_locked};
                16'h0120:cfg_rdata=reset_mask;
                16'h0124:cfg_rdata=clock_fault_count;
                16'h7000:cfg_rdata=32'h00500101;
                16'h7004:cfg_rdata={31'd0,stream_enable};
                16'h7008:cfg_rdata={24'd0,(|stream_errors),stream_errors[2],tx_fifo_level>=tx_high_water,
                    1'b1,(|msg_pending_mask || |bulk_pending_mask),1'b0,stream_enable,stream_enable};
                16'h700c:cfg_rdata=stream_errors;
                16'h7010:cfg_rdata={31'd0,arb_mode};
                16'h7014,16'h802c:cfg_rdata=tx_fifo_level;
                16'h7018:cfg_rdata=tx_high_water;
                16'h701c:cfg_rdata=displayed_drop_count;
                16'h7020:cfg_rdata=adc0_fifo_level;
                16'h7024:cfg_rdata=adc1_fifo_level;
                16'h7028:cfg_rdata=dila0_fifo_level;
                16'h702c:cfg_rdata=dila1_fifo_level;
                16'h7030:cfg_rdata=sensor_fifo_level;
                16'h7034:cfg_rdata=max_high_burst;
                16'h7038:cfg_rdata=msg_pending_mask;
                16'h703c:cfg_rdata=bulk_pending_mask;
                16'h7040:cfg_rdata=arb_grant_count[31:0];
                16'h7044:cfg_rdata=grant_hi;
                16'h8000:cfg_rdata=32'h00510101;
                16'h8004:cfg_rdata={31'd0,usb_enable};
                16'h8008:cfg_rdata={24'd0,(|usb_errors),2'd0,link_ready,
                    (tx_fifo_level!=0 || rx_fifo_level!=0),1'b0,(link_ready && usb_enable),usb_enable};
                16'h800c:cfg_rdata=usb_errors;
                16'h8010:cfg_rdata=GPIF_CLK_HZ;
                16'h8014:cfg_rdata={31'd0,link_ready};
                16'h8018:cfg_rdata=tx_word_count[31:0];
                16'h801c:cfg_rdata=tx_hi;
                16'h8020:cfg_rdata=rx_word_count[31:0];
                16'h8024:cfg_rdata=rx_hi;
                16'h8028:cfg_rdata=rx_fifo_level;
                16'h8030:cfg_rdata=fx3_reset_ms;
                16'h8034:cfg_rdata=gpif_stall_count;
                16'h8038:cfg_rdata=last_sequence_rx;
                16'h803c:cfg_rdata=last_sequence_tx;
                default:begin cfg_error=1;known_register=0;end
            endcase
            merged=(cfg_rdata & ~mask)|(cfg_wdata & mask);
            if(cfg_write)begin
                case({page,offset})
                    16'h0004:if((cfg_wdata & mask & ~32'd3)!=0)cfg_error=1;
                    16'h000c,16'h0038,16'h003c,16'h010c,16'h700c,16'h800c:begin end
                    16'h002c,16'h0030,16'h0034,16'h0050:begin end
                    16'h0040:if(merged>3600000)cfg_error=1;
                    16'h0044:begin end
                    16'h0120:if(merged[31:6]!=0)cfg_error=1;
                    // The clock-management page itself must stay accessible.
                    16'h0104:if((write_bits & ~32'd3)!=0 || !merged[0])cfg_error=1;
                    16'h7010:if(merged>1)cfg_error=1;
                    16'h7018:if(merged==0)cfg_error=1;
                    16'h7034:if(merged==0 || merged>65535)cfg_error=1;
                    16'h701c:begin end
                    16'h7004,16'h8004:if((write_bits & ~32'd11)!=0)cfg_error=1;
                    16'h8030:if(merged==0 || merged>10000)cfg_error=1;
                    default:begin cfg_error=1;writable_register=0;end
                endcase
            end
            if(offset[1:0]!=0)cfg_error=1;
            if(cfg_error)begin
                if(!known_register || offset[1:0]!=0)cfg_error_code=5;
                else if(cfg_write && !writable_register)cfg_error_code=6;
                else cfg_error_code=7;
            end
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            global_enable<=0;soft_reset_pulse<=0;watchdog_kick<=0;watchdog_timeout_ms<=0;reset_mask<=0;
            stream_mask<=64'hffffffffffffffff;raw_stream_mask<=0;arb_mode<=1;max_high_burst<=4;tx_high_water<=1536;
            fx3_reset_ms<=10;fx3_reset_request<=0;error_summary<=0;irq_summary<=0;reset_reason<=1;clock_fault_count<=0;
            uptime_hi<=0;grant_hi<=0;tx_hi<=0;rx_hi<=0;was_locked<=0;was_watchdog<=0;
            displayed_drop_count<=0;previous_drop_count<=0;
            clock_errors<=0;stream_errors<=0;usb_errors<=0;
            previous_protocol_count<=0;previous_crc_count<=0;
            clock_fault_base<=0;previous_clock_fault_total<=0;
            stream_enable<=1;usb_enable<=1;
            clock_reset_request<=0;stream_reset_pulse<=0;stream_clear_pulse<=0;usb_clear_pulse<=0;
        end else begin
            soft_reset_pulse<=0;watchdog_kick<=0;fx3_reset_request<=0;was_locked<=clock_locked;
            clock_reset_request<=0;stream_reset_pulse<=0;stream_clear_pulse<=0;usb_clear_pulse<=0;
            was_watchdog<=watchdog_expired;
            previous_drop_count<=total_drop_count;
            previous_protocol_count<=protocol_error_count;previous_crc_count<=crc_error_count;
            displayed_drop_count<=displayed_drop_count+new_drops;
            clock_errors<=clock_errors | clock_events;
            stream_errors<=stream_errors | stream_events;
            usb_errors<=usb_errors | usb_events;
            error_summary<=error_summary | system_events;
            irq_summary<=irq_summary | module_irq;
            reset_reason<=(reset_reason & ~reason_clear) | (software_event ? 32'd4 : 32'd0) |
                (watchdog_event ? 32'd2 : 32'd0) | (clock_fault_event ? 32'd8 : 32'd0);
            if(USE_EXTERNAL_CLOCK_FAULTS)begin
                previous_clock_fault_total<=clock_fault_total;
                clock_fault_count<=clock_fault_total-clock_fault_base;
            end else if(was_locked && !clock_locked)clock_fault_count<=clock_fault_count+1'b1;
            if(selected && !cfg_error)begin
                if(!cfg_write)case({page,offset})
                    16'h0024:uptime_hi<=timestamp_now[63:32];
                    16'h7040:grant_hi<=arb_grant_count[63:32];
                    16'h8018:tx_hi<=tx_word_count[63:32];
                    16'h8020:rx_hi<=rx_word_count[63:32];
                endcase
                else case({page,offset})
                    16'h0004:begin
                        global_enable<=merged[0];
                        if(write_bits[1])soft_reset_pulse<=1;
                    end
                    16'h000c:error_summary<=(error_summary & ~write_bits) | system_events;
                    16'h002c:stream_mask[31:0]<=merged;
                    16'h0030:stream_mask[63:32]<=merged;
                    16'h0034:raw_stream_mask[31:0]<=merged;
                    16'h0050:raw_stream_mask[63:32]<=merged;
                    16'h0038:irq_summary<=(irq_summary & ~(cfg_wdata & mask)) | module_irq;
                    16'h0040:watchdog_timeout_ms<=merged;
                    16'h0044:if(|cfg_wstrb)watchdog_kick<=1;
                    16'h0104:if(write_bits[1])begin
                        clock_reset_request<=1;
                        if(USE_EXTERNAL_CLOCK_FAULTS)begin
                            // Retain a new event arriving on the clear cycle.
                            clock_fault_base<=previous_clock_fault_total;
                            clock_fault_count<=clock_fault_total-previous_clock_fault_total;
                        end else clock_fault_count<=(was_locked && !clock_locked) ? 1 : 0;
                        clock_errors<=clock_events;
                    end
                    16'h010c:clock_errors<=(clock_errors & ~write_bits) | clock_events;
                    16'h0120:reset_mask<=merged;
                    16'h7010:arb_mode<=merged[0];
                    16'h7018:tx_high_water<=merged;
                    16'h7034:max_high_burst<=merged;
                    16'h7004:begin
                        stream_enable<=merged[0];
                        if(write_bits[1])begin
                            stream_reset_pulse<=1;arb_mode<=1;max_high_burst<=4;tx_high_water<=1536;
                            stream_errors<=stream_events;displayed_drop_count<=new_drops;
                        end
                        if(write_bits[3])stream_clear_pulse<=1;
                    end
                    16'h700c:stream_errors<=(stream_errors & ~write_bits) | stream_events;
                    16'h701c:displayed_drop_count<=(displayed_drop_count & ~write_bits)+new_drops;
                    16'h8004:begin
                        usb_enable<=merged[0];
                        if(write_bits[1])begin fx3_reset_request<=1;usb_errors<=usb_events;end
                        if(write_bits[3])usb_clear_pulse<=1;
                    end
                    16'h800c:usb_errors<=(usb_errors & ~write_bits) | usb_events;
                    16'h8030:fx3_reset_ms<=merged;
                endcase
            end
            if(watchdog_expired)global_enable<=0;
            if(clock_fault_event)global_enable<=0;
            if(watchdog_event)soft_reset_pulse<=1;
        end
    end
endmodule
`default_nettype wire
