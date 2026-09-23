`default_nettype none
// Separate queues preserve P0 error / P1 time / P2 status priorities.
module status_manager #(
    parameter integer N=21,STATUS_INTERVAL_TICKS=100000000,QUEUE_DEPTH=32,
    parameter [N*8-1:0] PAGE_MAP=168'h807067666564636261605150414031302120100100
)(
    input wire sys_clk,rst_sys_n,
    input wire [63:0] timestamp_now,
    input wire time_sync_valid,
    input wire [N*32-1:0] module_status,module_errors,
    input wire [N-1:0] module_present,
    input wire [31:0] system_status,total_drop_count,reset_reason,
    input wire sync_event_pulse,
    input wire [31:0] sync_seq,
    input wire [63:0] sync_event_tick,sync_event_gnss_tag,
    input wire sync_event_gnss_valid,
    input wire motor_done,
    input wire [31:0] motion_id,motor_position,motor_remaining,motor_errors,
    output reg [31:0] error_summary,module_irq,
    output wire [31:0] event_drop_count,
    output wire [2:0] m_valid,
    input wire [2:0] m_ready,
    output wire [95:0] m_data,m_cycle_id,m_flags,
    output wire [11:0] m_keep,
    output wire [2:0] m_sof,m_last,
    output wire [47:0] m_source_id,m_msg_id,
    output wire [191:0] m_timestamp,
    output wire [23:0] m_frame_type,
    output wire [95:0] queue_level
);
    reg [31:0] previous_errors [0:N-1],previous_status [0:N-1];
    reg [2:0] event_valid;
    reg [255:0] event_payload [0:2];
    reg [15:0] event_source [0:2],event_msg [0:2];
    reg [63:0] event_timestamp [0:2];
    reg [31:0] event_flags [0:2];
    reg [7:0] event_type [0:2];
    wire [95:0] drop_counts;
    reg [31:0] timer,online_mask;
    reg periodic_pending;
    integer index,k;
    wire [31:0] observed_error=module_errors[index*32 +: 32];
    wire [31:0] observed_status=module_status[index*32 +: 32];
    wire [31:0] new_error=observed_error & ~previous_errors[index];
    wire [7:0] observed_page=PAGE_MAP[index*8 +: 8];
    wire [31:0] common_flags=32'd1 | (time_sync_valid?32'd4:0);
    function [15:0] source_for_page;input [7:0] page;begin
        case(page)
            8'h00:source_for_page=1;
            8'h10:source_for_page=2;
            8'h20,8'h30:source_for_page=16'h10;
            8'h21,8'h31:source_for_page=16'h11;
            8'h40:source_for_page=16'h20;
            8'h41:source_for_page=16'h21;
            8'h50:source_for_page=16'h30;
            8'h51:source_for_page=16'h31;
            8'h60,8'h61,8'h62,8'h63,8'h64,8'h65,8'h66,8'h67:source_for_page={8'd0,page}-16'h20;
            default:source_for_page=16'h50;
        endcase
    end endfunction
    always @* begin
        error_summary=0;online_mask=0;
        for(k=0;k<N;k=k+1)begin
            // SYSTEM summary must not feed its own previously polled value.
            if(PAGE_MAP[k*8 +: 8]!=0)error_summary=error_summary|module_errors[k*32 +: 32];
            online_mask[k]=module_present[k] && module_status[k*32+4];
        end
    end
    assign event_drop_count=drop_counts[31:0]+drop_counts[63:32]+drop_counts[95:64];
    genvar q;
    generate for(q=0;q<3;q=q+1)begin:queues
        event_record_fifo #(.DEPTH(QUEUE_DEPTH)) u_queue(.sys_clk(sys_clk),.rst_sys_n(rst_sys_n),
            .event_valid(event_valid[q]),.event_payload(event_payload[q]),.event_words(4'd8),
            .event_frame_type(event_type[q]),.event_source(event_source[q]),.event_msg(event_msg[q]),
            .event_timestamp(event_timestamp[q]),.event_cycle(32'hffffffff),.event_flags(event_flags[q]),
            .drop_count(drop_counts[q*32 +: 32]),.level(queue_level[q*32 +: 32]),
            .m_valid(m_valid[q]),.m_ready(m_ready[q]),.m_data(m_data[q*32 +: 32]),.m_keep(m_keep[q*4 +: 4]),
            .m_sof(m_sof[q]),.m_last(m_last[q]),.m_source_id(m_source_id[q*16 +: 16]),.m_msg_id(m_msg_id[q*16 +: 16]),
            .m_timestamp(m_timestamp[q*64 +: 64]),.m_cycle_id(m_cycle_id[q*32 +: 32]),.m_flags(m_flags[q*32 +: 32]),
            .m_frame_type(m_frame_type[q*8 +: 8]));
    end endgenerate
    integer n;
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            event_valid<=0;module_irq<=0;index<=0;timer<=0;periodic_pending<=0;
            for(n=0;n<N;n=n+1)begin previous_errors[n]<=0;previous_status[n]<=0;end
            for(n=0;n<3;n=n+1)begin
                event_payload[n]<=0;event_source[n]<=0;event_msg[n]<=0;
                event_timestamp[n]<=0;event_flags[n]<=0;event_type[n]<=0;
            end
        end else begin
            event_valid<=0;module_irq<=0;
            index<=index==N-1?0:index+1;
            previous_errors[index]<=observed_error;
            if(timer>=STATUS_INTERVAL_TICKS-1)begin timer<=0;periodic_pending<=1;end
            else timer<=timer+1'b1;
            if(new_error!=0 && observed_page!=0)begin
                event_valid[0]<=1;event_source[0]<=source_for_page(observed_page);event_msg[0]<=16'h1402;
                event_timestamp[0]<=timestamp_now;event_flags[0]<=common_flags|32'h110;event_type[0]<=8'h11;
                event_payload[0]<={96'd0,observed_status,new_error,observed_error,24'd0,observed_page,32'd1};
                module_irq<=32'd1<<index;
            end
            if(sync_event_pulse)begin
                event_valid[1]<=1;event_source[1]<=2;event_msg[1]<=16'h1201;
                event_timestamp[1]<=sync_event_tick;event_flags[1]<=common_flags;event_type[1]<=8'h11;
                event_payload[1]<={32'd0,31'd0,sync_event_gnss_valid,sync_event_gnss_tag,sync_event_tick,sync_seq,32'd1};
            end
            if(motor_done)begin
                event_valid[2]<=1;event_source[2]<=16'h47;event_msg[2]<=16'h1300;
                event_timestamp[2]<=timestamp_now;event_flags[2]<=common_flags|(motor_errors!=0?32'h10:0);event_type[2]<=8'h11;
                event_payload[2]<={96'd0,motor_errors,motor_remaining,motor_position,motion_id,32'd1};
            end else if(periodic_pending)begin
                periodic_pending<=0;event_valid[2]<=1;event_source[2]<=1;event_msg[2]<=16'h1400;
                event_timestamp[2]<=timestamp_now;event_flags[2]<=common_flags;event_type[2]<=8'h12;
                event_payload[2]<={reset_reason,total_drop_count,event_drop_count,32'd0,online_mask,error_summary,system_status,32'd1};
            end else if(observed_status!=previous_status[index])begin
                previous_status[index]<=observed_status;
                event_valid[2]<=1;event_source[2]<=source_for_page(observed_page);event_msg[2]<=16'h1401;
                event_timestamp[2]<=timestamp_now;event_flags[2]<=common_flags;event_type[2]<=8'h12;
                event_payload[2]<={96'd0,31'd0,module_present[index],observed_error,observed_status,24'd0,observed_page,32'd1};
            end
        end
    end
endmodule
`default_nettype wire
