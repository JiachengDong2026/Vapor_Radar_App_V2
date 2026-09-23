`default_nettype none
module event_record_fifo #(parameter integer DEPTH=32)(
    input wire sys_clk,rst_sys_n,
    input wire event_valid,
    input wire [255:0] event_payload,
    input wire [3:0] event_words,
    input wire [7:0] event_frame_type,
    input wire [15:0] event_source,event_msg,
    input wire [63:0] event_timestamp,
    input wire [31:0] event_cycle,event_flags,
    output reg [31:0] drop_count,
    output wire [31:0] level,
    output wire m_valid,
    input wire m_ready,
    output wire [31:0] m_data,
    output wire [3:0] m_keep,
    output wire m_sof,m_last,
    output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,
    output wire [31:0] m_cycle_id,m_flags,
    output wire [7:0] m_frame_type
);
    reg [2:0] word_index;
    wire [3:0] words;
    wire [255:0] payload;
    wire [427:0] fifo_data;
    wire ready;
    wire valid_words=event_words>=1 && event_words<=8;
    sync_fifo #(.WIDTH(428),.DEPTH(DEPTH),.ALMOST_FULL_THRESHOLD(DEPTH-2)) u_fifo(
        .clk(sys_clk),.rst_n(rst_sys_n),.s_valid(event_valid && valid_words),.s_ready(ready),
        .s_data({event_words,event_frame_type,event_source,event_msg,event_timestamp,event_cycle,event_flags,event_payload}),
        .m_valid(m_valid),.m_ready(m_ready && m_last),.m_data(fifo_data),
        .full(),.empty(),.almost_full(),.level(level),.full_stall_pulse());
    assign {words,m_frame_type,m_source_id,m_msg_id,m_timestamp,m_cycle_id,m_flags,payload}=fifo_data;
    assign m_data=payload[word_index*32 +: 32];
    assign m_keep=4'hf;
    assign m_sof=word_index==0;
    assign m_last={1'b0,word_index}==words-1'b1;
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin word_index<=0;drop_count<=0;end
        else begin
            if(event_valid && (!ready || !valid_words))drop_count<=drop_count+1'b1;
            if(m_valid && m_ready)word_index<=m_last?0:word_index+1'b1;
        end
    end
endmodule
`default_nettype wire
