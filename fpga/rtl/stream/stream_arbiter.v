`default_nettype none
// Registered grant: hold a selected producer through LAST, including stalls
// before its first accepted beat. Aging is counted in completed higher classes.
module stream_arbiter #(parameter integer N=8)(
    input wire sys_clk, rst_sys_n,
    input wire arb_mode,
    input wire [31:0] max_high_burst,
    input wire [N*2-1:0] s_priority,
    input wire [N-1:0] s_valid,
    output reg [N-1:0] s_ready,
    input wire [N*32-1:0] s_data,
    input wire [N*4-1:0] s_keep,
    input wire [N*1-1:0] s_sof,
    input wire [N*1-1:0] s_last,
    input wire [N*16-1:0] s_source_id,
    input wire [N*16-1:0] s_msg_id,
    input wire [N*64-1:0] s_timestamp,
    input wire [N*32-1:0] s_cycle_id,
    input wire [N*32-1:0] s_flags,
    input wire [N*8-1:0] s_frame_type,
    input wire [N*32-1:0] s_sequence,
    input wire [N*1-1:0] s_sequence_valid,
    output wire [32-1:0] m_data,
    output wire [4-1:0] m_keep,
    output wire m_sof,
    output wire m_last,
    output wire [16-1:0] m_source_id,
    output wire [16-1:0] m_msg_id,
    output wire [64-1:0] m_timestamp,
    output wire [32-1:0] m_cycle_id,
    output wire [32-1:0] m_flags,
    output wire [8-1:0] m_frame_type,
    output wire [32-1:0] m_sequence,
    output wire m_sequence_valid,
    output wire m_valid,
    input wire m_ready,
    output reg [63:0] grant_count,
    output wire [N-1:0] pending_mask
);
    reg active;
    integer grant, rr_source, rr_class;
    integer rr_priority [0:3];
    integer i,j,k,idx,selected,selected_class;
    reg [3:0] pending_classes;
    reg [31:0] age [0:3];
    reg [1:0] grant_priority;
    reg found;
    wire [31:0] burst_limit = max_high_burst==0 ? 32'd1 : max_high_burst;
    assign pending_mask=s_valid;
    assign m_valid=active && s_valid[grant];
    assign m_data = s_data[grant*32 +: 32];
    assign m_keep = s_keep[grant*4 +: 4];
    assign m_sof = s_sof[grant];
    assign m_last = s_last[grant];
    assign m_source_id = s_source_id[grant*16 +: 16];
    assign m_msg_id = s_msg_id[grant*16 +: 16];
    assign m_timestamp = s_timestamp[grant*64 +: 64];
    assign m_cycle_id = s_cycle_id[grant*32 +: 32];
    assign m_flags = s_flags[grant*32 +: 32];
    assign m_frame_type = s_frame_type[grant*8 +: 8];
    assign m_sequence = s_sequence[grant*32 +: 32];
    assign m_sequence_valid = s_sequence_valid[grant];
    always @* begin
        s_ready=0;
        if(active) s_ready[grant]=m_ready;
        pending_classes=0;
        for(i=0;i<N;i=i+1) if(s_valid[i]) pending_classes[s_priority[i*2 +: 2]]=1;
        selected=-1;selected_class=-1;found=0;idx=0;
        if(!arb_mode) begin
            for(j=0;j<N;j=j+1) begin
                idx=rr_source+j;if(idx>=N)idx=idx-N;
                if(!found && s_valid[idx])begin selected=idx;found=1;end
            end
        end else begin
            // First serve an overdue class, round-robin across overdue classes.
            for(j=0;j<4;j=j+1)begin
                idx=rr_class+j;if(idx>=4)idx=idx-4;
                if(selected_class<0 && pending_classes[idx] && age[idx]>=burst_limit) selected_class=idx;
            end
            for(j=0;j<4;j=j+1) if(selected_class<0 && pending_classes[j]) selected_class=j;
            for(j=0;j<N;j=j+1)begin
                idx=j;
                if(selected_class>=0)idx=rr_priority[selected_class]+j;
                if(idx>=N)idx=idx-N;
                if(!found && s_valid[idx] && s_priority[idx*2 +: 2]==selected_class)begin selected=idx;found=1;end
            end
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n) begin
        if(!rst_sys_n)begin
            active<=0;grant<=0;rr_source<=0;rr_class<=0;grant_count<=0;grant_priority<=0;
            for(k=0;k<4;k=k+1)begin age[k]<=0;rr_priority[k]<=0;end
        end else begin
            for(k=0;k<4;k=k+1)if(!pending_classes[k])age[k]<=0;
            if(!active && selected>=0)begin
                grant<=selected;grant_priority<=s_priority[selected*2 +: 2];active<=1;
            end
            if(m_valid && m_ready && m_last)begin
                active<=0;grant_count<=grant_count+1'b1;
                rr_source<=(grant==N-1)?0:grant+1;
                rr_priority[grant_priority]<=(grant==N-1)?0:grant+1;
                rr_class<=(grant_priority==3)?0:grant_priority+1;
                for(k=0;k<4;k=k+1)begin
                    if(k==grant_priority)age[k]<=0;
                    else if(pending_classes[k] && grant_priority<k && age[k]!=32'hffffffff)age[k]<=age[k]+1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
