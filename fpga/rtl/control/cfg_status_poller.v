`default_nettype none
module cfg_status_poller #(
    parameter integer N=21,POLL_INTERVAL_TICKS=1000000,TIMEOUT_TICKS=4096,
    parameter [N*8-1:0] PAGE_MAP=168'h807067666564636261605150414031302120100100
)(
    input wire sys_clk,rst_sys_n,
    output reg cfg_valid,
    output wire cfg_write,
    output reg [31:0] cfg_addr,
    output wire [31:0] cfg_wdata,
    output wire [3:0] cfg_wstrb,
    input wire cfg_ready,cfg_error,
    input wire [31:0] cfg_rdata,
    output reg [N*32-1:0] module_status,module_errors,
    output reg [N-1:0] module_present,
    output reg [31:0] timeout_count
);
    reg [31:0] interval_count,wait_count;
    integer index;
    reg read_error;
    reg status_ok;
    assign cfg_write=0;assign cfg_wdata=0;assign cfg_wstrb=4'hf;
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            cfg_valid<=0;cfg_addr<=0;module_status<=0;module_errors<=0;module_present<=0;
            timeout_count<=0;interval_count<=0;wait_count<=0;index<=0;read_error<=0;status_ok<=0;
        end else if(cfg_valid)begin
            if(cfg_ready || wait_count>=TIMEOUT_TICKS-1)begin
                cfg_valid<=0;wait_count<=0;
                if(!cfg_ready || cfg_error)begin
                    module_present[index]<=0;module_errors[index*32 +: 32]<=32'h9;
                    if(!read_error)status_ok<=0;
                    if(!cfg_ready)timeout_count<=timeout_count+1'b1;
                end else if(read_error)begin module_errors[index*32 +: 32]<=cfg_rdata | (status_ok?32'd0:32'h9);module_present[index]<=status_ok;end
                else begin module_status[index*32 +: 32]<=cfg_rdata;status_ok<=1;end
                if(read_error)begin
                    read_error<=0;
                    if(index==N-1)begin index<=0;interval_count<=POLL_INTERVAL_TICKS;end
                    else index<=index+1;
                end else read_error<=1;
            end else wait_count<=wait_count+1'b1;
        end else if(interval_count!=0)interval_count<=interval_count-1'b1;
        else begin
            cfg_addr<={16'd0,PAGE_MAP[index*8 +: 8],(read_error?8'h0c:8'h08)};
            cfg_valid<=1;wait_count<=0;
        end
    end
endmodule
`default_nettype wire
