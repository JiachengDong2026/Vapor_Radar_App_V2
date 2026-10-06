`include "project_defs.vh"
module dila_block_framer #(
    parameter integer MAX_POINTS=4096,
    parameter integer OUTPUT_FORMAT=0,
    parameter [15:0] SOURCE_ID=16'h0030
)(
    input wire clk,input wire rst_n,input wire clear,
    input wire point_valid,input wire [191:0] point_data,input wire [193:0] point_tag,
    input wire [31:0] point_flags,input wire [31:0] output_rate,
    input wire [31:0] fragment_points,
    input wire boundary_valid,input wire [31:0] boundary_cycle,input wire boundary_partial,
    output reg [31:0] drop_count,output reg [31:0] last_fragment_count,
    output wire [31:0] level,
    output wire m_valid,input wire m_ready,output reg [31:0] m_data,
    output wire [3:0] m_keep,output wire m_sof,output wire m_last,
    output wire [15:0] m_source_id,output wire [15:0] m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,output wire [31:0] m_flags
);
    localparam integer WORDS=OUTPUT_FORMAT==0?2:(OUTPUT_FORMAT==1?4:6);
    (* ram_style="block" *) reg [191:0] memory[0:2*MAX_POINTS-1];
    reg [1:0] sealed;
    reg active,write_bank;
    reg [31:0] bank_count[0:1],bank_cycle[0:1],bank_flags[0:1],bank_rate[0:1],bank_frag[0:1];
    reg [63:0] bank_tick[0:1];
    reg [2:0] state;
    reg read_bank;
    reg [31:0] frag_index,frag_count,point_index,frag_size,frag_first;
    reg [2:0] header_index,word_index;
    reg [191:0] point_cache;
    reg [31:0] count_left;
    reg mem_write;
    reg [31:0] mem_write_address;
    reg dropped_since;
    wire [31:0] incoming_cycle=point_tag[31:0];
    wire [63:0] incoming_tick=point_tag[191:128];
    wire incoming_sync=point_tag[193];
    wire same_cycle=active && incoming_cycle==bank_cycle[write_bank];
    wire next_bank=!write_bank;
    wire free_bank= !sealed[0] ? 1'b0 : 1'b1;
    wire free_exists=sealed!=2'b11;
    assign level=bank_count[0]+bank_count[1];
    assign m_valid=state==2 || state==4;
    assign m_keep=4'hf;
    assign m_sof=state==2 && header_index==0;
    assign m_last=(state==2 && header_index==7 && frag_size==0) ||
                  (state==4 && word_index==WORDS-1 && point_index+1==frag_first+frag_size);
    assign m_source_id=SOURCE_ID;assign m_msg_id=`MSG_DILA_BLOCK;
    assign m_timestamp=bank_tick[read_bank];assign m_cycle_id=bank_cycle[read_bank];
    assign m_flags=bank_flags[read_bank];
    always @*begin
        m_data=0;
        if(state==2)case(header_index)
            0:m_data=(OUTPUT_FORMAT<<16)|32'd2;
            1:m_data=bank_rate[read_bank];
            2:m_data=bank_count[read_bank];
            3:m_data={frag_count[15:0],frag_index[15:0]};
            4:m_data=frag_first;
            5:m_data=frag_size;
            6:m_data=WORDS*4;
            default:m_data=0;
        endcase
        else if(state==4)begin
            if(OUTPUT_FORMAT==0)m_data=word_index==0?point_cache[159:128]:point_cache[191:160];
            else m_data=point_cache[word_index*32+:32];
        end
    end
    always @*begin
        mem_write=0;mem_write_address=0;
        if(rst_n && !clear && point_valid)begin
            if(same_cycle && bank_count[write_bank]<MAX_POINTS)begin
                mem_write=1;mem_write_address=write_bank*MAX_POINTS+bank_count[write_bank];
            end else if(!same_cycle && active && !sealed[next_bank])begin
                mem_write=1;mem_write_address=next_bank*MAX_POINTS;
            end else if(!active && free_exists)begin
                mem_write=1;mem_write_address=free_bank*MAX_POINTS;
            end
        end
    end
    // RAM ports deliberately have no reset; validity is owned by resettable descriptors.
    always @(posedge clk)begin
        if(mem_write)memory[mem_write_address]<=point_data;
        if(state==3 || (state==2 && m_ready && header_index==7))
            point_cache<=memory[read_bank*MAX_POINTS+point_index];
    end
    integer b;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            sealed<=0;active<=0;write_bank<=0;state<=0;read_bank<=0;
            frag_index<=0;frag_count<=0;point_index<=0;frag_size<=0;frag_first<=0;
            header_index<=0;word_index<=0;count_left<=0;
            drop_count<=0;last_fragment_count<=0;dropped_since<=0;
            for(b=0;b<2;b=b+1)begin bank_count[b]<=0;bank_cycle[b]<=0;bank_flags[b]<=0;bank_rate[b]<=0;bank_frag[b]<=256;bank_tick[b]<=0;end
        end else if(clear)begin
            sealed<=0;active<=0;state<=0;bank_count[0]<=0;bank_count[1]<=0;dropped_since<=0;
        end else begin
            // Seal only after all old tagged arithmetic has completed.
            if(boundary_valid && active && bank_cycle[write_bank]!=boundary_cycle)begin
                sealed[write_bank]<=1;active<=0;
                if(boundary_partial)bank_flags[write_bank]<=bank_flags[write_bank]|32'h20;
            end
            if(point_valid)begin
                if(same_cycle)begin
                    if(bank_count[write_bank]<MAX_POINTS)begin

                        bank_count[write_bank]<=bank_count[write_bank]+1'b1;
                        bank_flags[write_bank]<=bank_flags[write_bank]|point_flags;
                    end else begin
                        drop_count<=drop_count+1'b1;bank_flags[write_bank]<=bank_flags[write_bank]|32'h28;
                    end
                end else if(active)begin
                    sealed[write_bank]<=1;bank_flags[write_bank]<=bank_flags[write_bank]|point_flags;
                    if(!sealed[next_bank])begin
                        write_bank<=next_bank;active<=1;
                        bank_count[next_bank]<=1;
                        bank_cycle[next_bank]<=incoming_cycle;bank_tick[next_bank]<=incoming_tick;
                        bank_flags[next_bank]<=point_flags|32'h3|(incoming_sync?32'h4:0)|(dropped_since?32'h28:0);
                        bank_rate[next_bank]<=output_rate;bank_frag[next_bank]<=fragment_points;dropped_since<=0;
                    end else begin active<=0;drop_count<=drop_count+1'b1;dropped_since<=1;end
                end else if(free_exists)begin
                    write_bank<=free_bank;active<=1;
                    bank_count[free_bank]<=1;
                    bank_cycle[free_bank]<=incoming_cycle;bank_tick[free_bank]<=incoming_tick;
                    bank_flags[free_bank]<=point_flags|32'h3|(incoming_sync?32'h4:0)|(dropped_since?32'h28:0);
                    bank_rate[free_bank]<=output_rate;bank_frag[free_bank]<=fragment_points;dropped_since<=0;
                end else begin drop_count<=drop_count+1'b1;dropped_since<=1;end
            end
            case(state)
                0:if(|sealed)begin
                    read_bank<=sealed[0]?0:1;
                    count_left<=sealed[0]?bank_count[0]:bank_count[1];
                    frag_count<=0;frag_index<=0;frag_first<=0;point_index<=0;state<=1;
                end
                // Bounded repeated subtraction avoids a variable combinational divider.
                1:begin
                    if(count_left<=bank_frag[read_bank])begin
                        frag_count<=frag_count+1'b1;last_fragment_count<=frag_count+1'b1;
                        frag_size<=bank_count[read_bank]<bank_frag[read_bank]?bank_count[read_bank]:bank_frag[read_bank];
                        header_index<=0;state<=2;
                    end else begin count_left<=count_left-bank_frag[read_bank];frag_count<=frag_count+1'b1;end
                end
                2:if(m_ready)begin
                    if(header_index==7)begin

                        word_index<=0;
                        if(frag_size==0)begin sealed[read_bank]<=0;bank_count[read_bank]<=0;state<=0;end
                        else state<=4;
                    end else header_index<=header_index+1'b1;
                end
                3:state<=4;
                4:if(m_ready)begin
                    if(word_index==WORDS-1)begin
                        word_index<=0;point_index<=point_index+1'b1;
                        if(point_index+1==bank_count[read_bank])begin sealed[read_bank]<=0;bank_count[read_bank]<=0;state<=0;end
                        else if(point_index+1==frag_first+frag_size)begin
                            frag_index<=frag_index+1'b1;frag_first<=point_index+1'b1;header_index<=0;
                            frag_size<=bank_count[read_bank]-point_index-1<bank_frag[read_bank]?
                                       bank_count[read_bank]-point_index-1:bank_frag[read_bank];state<=2;
                        end else state<=3;
                    end else word_index<=word_index+1'b1;
                end
                default:state<=0;
            endcase
        end
    end
endmodule

