`default_nettype none
module word_to_byte_stream(
    input wire sys_clk,rst_sys_n,
    input wire s_valid,
    output wire s_ready,
    input wire [31:0] s_data,
    output wire m_valid,
    input wire m_ready,
    output wire [7:0] m_data
);
    reg full;
    reg [31:0] word_data;
    reg [1:0] index;
    assign s_ready=!full || (m_ready && index==3);
    assign m_valid=full;
    assign m_data=word_data[index*8 +: 8];
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin full<=0;word_data<=0;index<=0;end
        else if(s_valid && s_ready)begin full<=1;word_data<=s_data;index<=0;end
        else if(m_valid && m_ready)begin
            if(index==3)begin full<=0;index<=0;end else index<=index+1'b1;
        end
    end
endmodule
`default_nettype wire
