`default_nettype none
// Source may increment by at most one per src_clk; zero on a coupled reset.
// Registered Gray representation avoids combinational glitches crossing clocks.
module counter_cdc(
    input wire src_clk,src_rst_n,dst_clk,dst_rst_n,
    input wire [31:0] src_count,
    output reg [31:0] dst_count
);
    reg [31:0] src_gray;
    (* ASYNC_REG="TRUE" *) reg [31:0] gray_meta,gray_sync;
    integer i;
    reg [31:0] decoded;
    always @(posedge src_clk or negedge src_rst_n)
        if(!src_rst_n) src_gray<=0;
        else src_gray<=src_count^(src_count>>1);
    always @* begin
        decoded[31]=gray_sync[31];
        for(i=30;i>=0;i=i-1) decoded[i]=decoded[i+1]^gray_sync[i];
    end
    always @(posedge dst_clk or negedge dst_rst_n)
        if(!dst_rst_n)begin gray_meta<=0;gray_sync<=0;dst_count<=0;end
        else begin gray_meta<=src_gray;gray_sync<=gray_meta;dst_count<=decoded;end
endmodule
`default_nettype wire
