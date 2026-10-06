`default_nettype none
// Transaction-locked round robin for command, action and status-poll masters.
module cfg_bus_arbiter #(parameter integer N=3)(
    input wire sys_clk,rst_sys_n,
    input wire [N-1:0] s_valid,s_write,
    input wire [N*32-1:0] s_addr,s_wdata,
    input wire [N*4-1:0] s_wstrb,
    output reg [N-1:0] s_ready,s_error,
    output reg [N*32-1:0] s_rdata,
    output wire m_valid,m_write,
    output wire [31:0] m_addr,m_wdata,
    output wire [3:0] m_wstrb,
    input wire m_ready,m_error,
    input wire [31:0] m_rdata,
    input wire [3:0] m_error_code,
    output reg [N*4-1:0] s_error_code
);
    reg active;
    integer grant,cursor,i,index,choice;
    assign m_valid=active && s_valid[grant];
    assign m_write=s_write[grant];
    assign m_addr=s_addr[grant*32 +: 32];
    assign m_wdata=s_wdata[grant*32 +: 32];
    assign m_wstrb=s_wstrb[grant*4 +: 4];
    always @* begin
        s_ready=0;s_error=0;s_rdata=0;s_error_code=0;choice=-1;index=0;
        if(active)begin
            s_ready[grant]=m_ready;
            s_error[grant]=m_error && m_ready;
            if(m_error && m_ready)s_error_code[grant*4 +:4]=m_error_code;
            s_rdata[grant*32 +: 32]=m_rdata;
        end
        for(i=0;i<N;i=i+1)begin
            index=cursor+i;if(index>=N)index=index-N;
            if(choice<0 && s_valid[index])choice=index;
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin active<=0;grant<=0;cursor<=0;end
        else begin
            if(!active && choice>=0)begin active<=1;grant<=choice;end
            if(active && (!s_valid[grant] || m_ready))begin active<=0;cursor<=grant==N-1?0:grant+1;end
        end
    end
endmodule
`default_nettype wire
