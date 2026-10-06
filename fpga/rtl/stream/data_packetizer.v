`default_nettype none
// Whole-fragment buffering determines payload_len before emitting VLP1 header.
// Payload words are little endian; only contiguous final KEEP is accepted.
module data_packetizer #(parameter integer MAX_PAYLOAD_BYTES=8192)(
    input wire sys_clk,rst_sys_n,
    input wire s_valid,
    output wire s_ready,
    input wire [31:0] s_data,
    input wire [3:0] s_keep,
    input wire s_sof,s_last,
    input wire [15:0] s_source_id,s_msg_id,
    input wire [63:0] s_timestamp,
    input wire [31:0] s_cycle_id,s_flags,
    input wire [7:0] s_frame_type,
    input wire [31:0] s_sequence,
    input wire s_sequence_valid,
    output wire m_valid,
    input wire m_ready,
    output reg [31:0] m_data,
    output wire m_last,
    output reg [31:0] last_sequence,frame_count,format_error_count,
    output wire busy
);
    localparam WORDS=(MAX_PAYLOAD_BYTES+3)/4;
    function integer clog2;input integer n;integer t;begin
        t=n-1;for(clog2=0;t>0;clog2=clog2+1)t=t>>1;
    end endfunction
    localparam CAPTURE=0,DRAIN=1,SEND=2;
    reg [1:0] state;
    (* ram_style="block" *) reg [31:0] payload [0:WORDS-1];
    reg [31:0] payload_read;
    reg [clog2(WORDS)-1:0] write_word;
    reg [clog2(MAX_PAYLOAD_BYTES+1)-1:0] length;
    assign busy=state!=CAPTURE || length!=0;
    reg [clog2(WORDS+12)-1:0] word_index;
    reg [31:0] next_sequence;
    reg [31:0] meta_sequence,meta_cycle,meta_flags;
    reg [15:0] meta_source,meta_msg;
    reg [63:0] meta_timestamp;
    reg [7:0] meta_type;
    reg [31:0] crc,crc_next,header_word;
    integer count,j,body_offset,byte_offset,read_address;
    reg bad_keep,bad_frame;
    function [31:0] crc_byte;
        input [31:0] c;input [7:0] b;
        reg [31:0] t;integer k;
        begin
            t=c ^ b;
            for(k=0;k<8;k=k+1)t=t[0] ? ((t>>1)^32'hedb88320) : (t>>1);
            crc_byte=t;
        end
    endfunction
    assign s_ready=state!=SEND;
    assign m_valid=state==SEND;
    assign m_last=word_index==((length+47)/4)-1;
    always @* begin
        count=0;bad_keep=0;
        case(s_keep)
            0:begin count=0;if(!(s_sof && s_last))bad_keep=1;end
            1:count=1;
            3:count=2;
            7:count=3;
            15:count=4;
            default:bad_keep=1;
        endcase
        if(!s_last && s_keep!=15)bad_keep=1;
        bad_frame=bad_keep || length+count>MAX_PAYLOAD_BYTES;
        if(length==0 && !s_sof)bad_frame=1;
        if(length!=0 && (s_sof || s_source_id!=meta_source || s_msg_id!=meta_msg ||
           s_timestamp!=meta_timestamp || s_cycle_id!=meta_cycle || s_flags!=meta_flags ||
           s_frame_type!=meta_type))bad_frame=1;
        case(word_index)
            0:header_word=32'h31504c56;
            1:header_word={8'd10,meta_type,8'd0,8'd1};
            2:header_word=length+44;
            3:header_word=meta_sequence;
            4:header_word={meta_msg,meta_source};
            5:header_word=meta_flags;
            6:header_word=meta_timestamp[31:0];
            7:header_word=meta_timestamp[63:32];
            8:header_word=meta_cycle;
            9:header_word=length;
            default:header_word=0;
        endcase
        crc_next=crc;m_data=0;body_offset=(word_index-10)*4;byte_offset=0;
        if(word_index<10)begin
            m_data=header_word;
            for(j=0;j<4;j=j+1)crc_next=crc_byte(crc_next,header_word[j*8 +: 8]);
        end else begin
            // Compute final CRC before placing the bytes sharing the final
            // payload word. On the following word crc already includes payload.
            for(j=0;j<4;j=j+1)
                if(body_offset+j<length)crc_next=crc_byte(crc_next,payload_read[j*8 +: 8]);
            for(j=0;j<4;j=j+1)begin
                byte_offset=body_offset+j;
                if(byte_offset<length)m_data[j*8 +: 8]=payload_read[j*8 +: 8];
                else if(byte_offset<length+4)m_data[j*8 +: 8]=~(crc_next >> ((byte_offset-length)*8));
                else m_data[j*8 +: 8]=0;
            end
        end
        // Synchronous RAM prefetch follows accepted TX words only.
        read_address=0;
        if(state==SEND && word_index>=10)begin
            read_address=word_index-10;
            if(m_ready)read_address=read_address+1;
            if(read_address>=WORDS)read_address=0;
        end
    end
    always @(posedge sys_clk)begin
        payload_read<=payload[read_address];
        if(rst_sys_n && s_valid && s_ready && state==CAPTURE && !bad_frame && count!=0)
            payload[write_word]<=s_data;
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            state<=CAPTURE;write_word<=0;length<=0;word_index<=0;next_sequence<=0;
            meta_sequence<=0;meta_cycle<=0;meta_flags<=0;meta_source<=0;meta_msg<=0;meta_timestamp<=0;meta_type<=0;
            crc<=32'hffffffff;last_sequence<=0;frame_count<=0;format_error_count<=0;
        end else begin
            if(s_valid && s_ready)begin
                if(state==DRAIN)begin
                    if(s_last)begin state<=CAPTURE;length<=0;write_word<=0;end
                end else if(bad_frame)begin
                    format_error_count<=format_error_count+1'b1;
                    state<=s_last?CAPTURE:DRAIN;length<=0;write_word<=0;
                end else begin
                    if(length==0)begin
                        meta_source<=s_source_id;meta_msg<=s_msg_id;meta_timestamp<=s_timestamp;
                        meta_cycle<=s_cycle_id;meta_flags<=s_flags;meta_type<=s_frame_type;
                        meta_sequence<=s_sequence_valid?s_sequence:next_sequence;
                    end
                    write_word<=write_word+1'b1;length<=length+count;
                    if(s_last)begin state<=SEND;word_index<=0;crc<=32'hffffffff;end
                end
            end
            if(m_valid && m_ready)begin
                crc<=crc_next;word_index<=word_index+1'b1;
                if(m_last)begin
                    state<=CAPTURE;length<=0;write_word<=0;word_index<=0;
                    next_sequence<=next_sequence+1'b1;last_sequence<=meta_sequence;frame_count<=frame_count+1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
