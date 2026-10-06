`default_nettype none
// Capture-tagged samples are framed by their stored cycle id, never live WMS
// phase. Two independent cycle banks decouple the unthrottled input from USB.
module adc_cycle_framer #(
    parameter integer MAX_SAMPLES=16384,
    parameter integer FRAGMENT_SAMPLES=2040,
    parameter integer V1_MAX_SAMPLES=2043,
    parameter integer FLUSH_IDLE_TICKS=1024,
    parameter [15:0] SOURCE_ID=16'h0020,
    parameter [15:0] ADC_BITS=16'd24,
    parameter [31:0] SAMPLE_FORMAT=0
)(
    input wire sys_clk,rst_sys_n,enable,flush,
    input wire [31:0] sample_rate_hz,
    input wire s_valid,
    output wire s_ready,
    input wire [31:0] s_data,
    input wire [7:0] s_flags,
    input wire [31:0] s_capture_cycle_id,
    input wire [63:0] s_cycle_timestamp,
    input wire s_capture_phase_valid,s_capture_time_sync_valid,
    output wire m_valid,
    input wire m_ready,
    output reg [31:0] m_data,
    output wire [3:0] m_keep,
    output wire m_sof,m_last,
    output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,
    output wire [31:0] m_cycle_id,m_flags,
    output reg [31:0] drop_count,cycle_drop_count,frame_count,
    output wire [31:0] buffered_samples
);
    function integer clog2;input integer n;integer t;begin t=n-1;for(clog2=0;t>0;clog2=clog2+1)t=t>>1;end endfunction
    localparam AW=clog2(MAX_SAMPLES);
    (* ram_style="block" *) reg [31:0] memory [0:2*MAX_SAMPLES-1];
    reg [31:0] memory_data;
    reg [1:0] bank_ready;
    reg capture_active,capture_bank,seen_cycle;
    reg [31:0] capture_id;
    reg [AW:0] bank_count [0:1];
    reg [31:0] bank_id [0:1],bank_flags [0:1],bank_rate [0:1];
    reg [63:0] bank_timestamp [0:1];
    reg [15:0] bank_chunks [0:1];
    reg [31:0] chunk_points,idle_ticks;
    reg flush_pending,flush_previous;
    wire flush_event=flush && !flush_previous;
    reg tx_active,read_bank,read_prefer,schema_v2;
    reg [31:0] first_sample,fragment_size,word_index;
    reg [15:0] fragment_index;
    reg write_mem;
    reg [AW:0] write_address,read_address;
    integer free_bank,read_choice;
    wire sample_event=s_valid && s_capture_phase_valid && enable;
    wire new_cycle=!seen_cycle || s_capture_cycle_id!=capture_id;
    wire [31:0] sample_flags=32'd3 | (s_capture_time_sync_valid?32'd4:0) | ((|s_flags[1:0])?32'h10:0);
    wire [31:0] header_words=schema_v2?8:5;
    assign s_ready=1;
    assign m_valid=tx_active;
    assign m_sof=word_index==0;
    assign m_last=word_index==header_words+fragment_size-1;
    assign m_keep=4'hf;
    assign m_source_id=SOURCE_ID;
    assign m_msg_id=16'h1000;
    assign m_timestamp=bank_timestamp[read_bank];
    assign m_cycle_id=bank_id[read_bank];
    assign m_flags=bank_flags[read_bank];
    assign buffered_samples=(bank_ready[0] || (capture_active && !capture_bank)?bank_count[0]:0)+
                            (bank_ready[1] || (capture_active && capture_bank)?bank_count[1]:0);
    always @* begin
        free_bank=-1;
        if(!bank_ready[0] && !(capture_active && !capture_bank))free_bank=0;
        else if(!bank_ready[1] && !(capture_active && capture_bank))free_bank=1;
        read_choice=-1;
        if(bank_ready[read_prefer])read_choice=read_prefer;
        else if(bank_ready[!read_prefer])read_choice=!read_prefer;
        write_mem=0;write_address=0;
        if(sample_event)begin
            if(new_cycle && free_bank>=0)begin write_mem=1;write_address=free_bank*MAX_SAMPLES;end
            else if(!new_cycle && capture_active && bank_count[capture_bank]<MAX_SAMPLES)begin
                write_mem=1;write_address=capture_bank*MAX_SAMPLES+bank_count[capture_bank];
            end
        end
        read_address=read_bank*MAX_SAMPLES+first_sample;
        if(tx_active && word_index>=header_words)
            read_address=read_bank*MAX_SAMPLES+first_sample+word_index-header_words+(m_ready?1:0);
        m_data=0;
        if(word_index<header_words)begin
            case(word_index)
                0:m_data={ADC_BITS,(schema_v2?16'd2:16'd1)};
                1:m_data=bank_rate[read_bank];
                2:m_data=bank_count[read_bank];
                3:m_data=SAMPLE_FORMAT;
                4:m_data=schema_v2?{bank_chunks[read_bank],fragment_index}:32'd0;
                5:m_data=first_sample;
                6:m_data=fragment_size;
                7:m_data=0;
            endcase
        end else m_data=memory_data;
    end
    always @(posedge sys_clk)begin
        if(rst_sys_n && write_mem)memory[write_address]<=s_data;
        memory_data<=memory[read_address];
    end
    integer k;
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            bank_ready<=0;capture_active<=0;capture_bank<=0;seen_cycle<=0;capture_id<=0;
            chunk_points<=0;idle_ticks<=0;tx_active<=0;read_bank<=0;read_prefer<=0;schema_v2<=0;
            flush_pending<=0;flush_previous<=0;
            first_sample<=0;fragment_size<=0;word_index<=0;fragment_index<=0;
            drop_count<=0;cycle_drop_count<=0;frame_count<=0;
            for(k=0;k<2;k=k+1)begin
                bank_count[k]<=0;bank_id[k]<=0;bank_flags[k]<=0;bank_rate[k]<=0;bank_timestamp[k]<=0;bank_chunks[k]<=0;
            end
        end else begin
            flush_previous<=flush;
            if(flush_event)flush_pending<=1;
            // While masked off, track boundaries so enabling midway through a
            // cycle cannot turn its tail into an apparently complete record.
            if(s_valid && s_capture_phase_valid && !enable)begin
                seen_cycle<=1;capture_id<=s_capture_cycle_id;
            end
            if(sample_event)begin
                idle_ticks<=0;
                if(new_cycle)begin
                    seen_cycle<=1;capture_id<=s_capture_cycle_id;
                    if(capture_active)bank_ready[capture_bank]<=1;
                    if(free_bank>=0)begin
                        capture_active<=1;capture_bank<=free_bank;bank_count[free_bank]<=1;chunk_points<=1;
                        bank_id[free_bank]<=s_capture_cycle_id;bank_timestamp[free_bank]<=s_cycle_timestamp;
                        bank_flags[free_bank]<=sample_flags;bank_rate[free_bank]<=sample_rate_hz;bank_chunks[free_bank]<=1;
                    end else begin
                        capture_active<=0;drop_count<=drop_count+1'b1;cycle_drop_count<=cycle_drop_count+1'b1;
                    end
                end else if(capture_active)begin
                    bank_flags[capture_bank]<=(bank_flags[capture_bank] | (sample_flags & ~32'd4)) &
                                             (s_capture_time_sync_valid?32'hffffffff:32'hfffffffb);
                    if(bank_count[capture_bank]<MAX_SAMPLES)begin
                        bank_count[capture_bank]<=bank_count[capture_bank]+1'b1;
                        if(chunk_points==FRAGMENT_SAMPLES)begin
                            chunk_points<=1;bank_chunks[capture_bank]<=bank_chunks[capture_bank]+1'b1;
                        end else chunk_points<=chunk_points+1'b1;
                    end else begin
                        drop_count<=drop_count+1'b1;
                        bank_flags[capture_bank]<=(bank_flags[capture_bank]|(sample_flags & ~32'd4)|32'h28) &
                            (s_capture_time_sync_valid?32'hffffffff:32'hfffffffb);
                    end
                end else drop_count<=drop_count+1'b1;
            end else if(capture_active && !enable)begin
                bank_ready[capture_bank]<=1;bank_flags[capture_bank]<=bank_flags[capture_bank]|32'h20;
                capture_active<=0;idle_ticks<=0;
            end else if(flush_pending || flush_event)begin
                if(idle_ticks>=FLUSH_IDLE_TICKS-1)begin
                    if(capture_active)begin
                        bank_ready[capture_bank]<=1;bank_flags[capture_bank]<=bank_flags[capture_bank]|32'h20;
                    end
                    capture_active<=0;idle_ticks<=0;flush_pending<=0;
                end else idle_ticks<=idle_ticks+1'b1;
            end else idle_ticks<=0;
            if(!tx_active && read_choice>=0)begin
                tx_active<=1;read_bank<=read_choice;first_sample<=0;word_index<=0;fragment_index<=0;
                schema_v2<=bank_count[read_choice]>V1_MAX_SAMPLES;
                fragment_size<=bank_count[read_choice]>V1_MAX_SAMPLES ?
                    (bank_count[read_choice]>FRAGMENT_SAMPLES?FRAGMENT_SAMPLES:bank_count[read_choice]):bank_count[read_choice];
            end
            if(m_valid && m_ready)begin
                if(m_last)begin
                    frame_count<=frame_count+1'b1;
                    if(first_sample+fragment_size==bank_count[read_bank])begin
                        bank_ready[read_bank]<=0;tx_active<=0;read_prefer<=!read_bank;word_index<=0;
                    end else begin
                        first_sample<=first_sample+fragment_size;fragment_index<=fragment_index+1'b1;word_index<=0;
                        fragment_size<=(bank_count[read_bank]-first_sample-fragment_size>FRAGMENT_SAMPLES)?
                            FRAGMENT_SAMPLES:bank_count[read_bank]-first_sample-fragment_size;
                    end
                end else word_index<=word_index+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
