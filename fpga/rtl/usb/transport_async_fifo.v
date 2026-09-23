`default_nettype none
// Public FIFO plus synchronized occupancy counters. Both domains reset
// together; deassertion is synchronized independently to each clock.
module transport_async_fifo #(parameter integer WIDTH=33,DEPTH=2048)(
    input wire reset_n,wr_clk,rd_clk,
    input wire s_valid,
    output wire s_ready,
    input wire [WIDTH-1:0] s_data,
    output wire m_valid,
    input wire m_ready,
    output wire [WIDTH-1:0] m_data,
    output wire [31:0] wr_level,rd_level
);
    function integer clog2;input integer n;integer t;begin t=n-1;for(clog2=0;t>0;clog2=clog2+1)t=t>>1;end endfunction
    localparam PW=clog2(DEPTH)+1;
    (* ASYNC_REG="TRUE" *) reg [2:0] wr_reset,rd_reset;
    reg [PW-1:0] wr_count,rd_count,wr_gray,rd_gray;
    (* ASYNC_REG="TRUE" *) reg [PW-1:0] rd_gray_meta,rd_gray_sync,wr_gray_meta,wr_gray_sync;
    wire write_ready,read_valid;
    wire wf=s_valid && s_ready,rf=m_valid && m_ready;
    wire [PW-1:0] wr_next=wr_count+wf,rd_next=rd_count+rf;
    function [PW-1:0] gray_to_binary;input [PW-1:0] g;integer k;begin
        gray_to_binary[PW-1]=g[PW-1];
        for(k=PW-2;k>=0;k=k-1)gray_to_binary[k]=gray_to_binary[k+1]^g[k];
    end endfunction
    wire [PW-1:0] occupied_wr=wr_count-gray_to_binary(rd_gray_sync);
    wire [PW-1:0] occupied_rd=gray_to_binary(wr_gray_sync)-rd_count;
    assign wr_level=occupied_wr;
    assign rd_level=occupied_rd;
    assign s_ready=write_ready && wr_reset[2];
    assign m_valid=read_valid && rd_reset[2];
    always @(posedge wr_clk or negedge reset_n)begin
        if(!reset_n)wr_reset<=0;else wr_reset<={wr_reset[1:0],1'b1};
    end
    always @(posedge rd_clk or negedge reset_n)begin
        if(!reset_n)rd_reset<=0;else rd_reset<={rd_reset[1:0],1'b1};
    end
    async_fifo_wrap #(.WIDTH(WIDTH),.DEPTH(DEPTH)) u_fifo(
        .wr_clk(wr_clk),.wr_rst_n(wr_reset[2]),.wr_valid(s_valid && wr_reset[2]),.wr_ready(write_ready),.wr_data(s_data),
        .wr_full(),.wr_full_stall_pulse(),.rd_clk(rd_clk),.rd_rst_n(rd_reset[2]),.rd_valid(read_valid),
        .rd_ready(m_ready && rd_reset[2]),.rd_data(m_data),.rd_empty());
    always @(posedge wr_clk or negedge reset_n)begin
        if(!reset_n)begin wr_count<=0;wr_gray<=0;rd_gray_meta<=0;rd_gray_sync<=0;end
        else if(wr_reset[2])begin
            wr_count<=wr_next;wr_gray<=(wr_next>>1)^wr_next;
            rd_gray_meta<=rd_gray;rd_gray_sync<=rd_gray_meta;
        end
    end
    always @(posedge rd_clk or negedge reset_n)begin
        if(!reset_n)begin rd_count<=0;rd_gray<=0;wr_gray_meta<=0;wr_gray_sync<=0;end
        else if(rd_reset[2])begin
            rd_count<=rd_next;rd_gray<=(rd_next>>1)^rd_next;
            wr_gray_meta<=wr_gray;wr_gray_sync<=wr_gray_meta;
        end
    end
endmodule
`default_nettype wire
