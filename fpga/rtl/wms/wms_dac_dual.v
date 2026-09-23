`include "project_defs.vh"
`include "register_map.vh"
`default_nettype none
module wms_dac_dual(
    input wire sys_clk,input wire rst_sys_n,input wire [1:0] enable,
    input wire [63:0] timestamp_now,input wire time_sync_valid,
    input wire cfg_valid,input wire cfg_write,input wire [31:0] cfg_addr,
    input wire [31:0] cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output wire [31:0] cfg_rdata,output wire cfg_error,
    output wire [1:0] scan_start,output wire [63:0] cycle_id,output wire [63:0] sine_phase,
    output wire [1:0] wms_running,output wire [1:0] phase_valid,output wire [1:0] config_changed,
    output wire [1:0] dac_sclk,output wire [1:0] dac_sync_n,output wire [1:0] dac_sdin,input wire [1:0] dac_sdo,
    output wire [1:0] dac_rst_n,output wire [1:0] dac_clr_n,output wire [1:0] dac_ldac_n,
    output wire [3:0] cfg_error_code
);
    wire [1:0] ready,err;
    wire [7:0] err_code;
    wire [63:0] rdata;
    assign cfg_ready=|ready;
    assign cfg_error=|(ready & err);
    assign cfg_error_code=({4{ready[0] && err[0]}} & err_code[3:0])|({4{ready[1] && err[1]}} & err_code[7:4]);
    assign cfg_rdata=({32{ready[0]}} & rdata[31:0])|({32{ready[1]}} & rdata[63:32]);
    genvar c;
    generate for(c=0;c<2;c=c+1)begin:channels
        wms_dac_channel #(.WMS_BASE(`REG_BASE_WMS0+c*256),.DAC_BASE(`REG_BASE_DAC0+c*256),
            .WMS_ID(`SRC_WMS0+c),.DAC_ID(16'h0012+c)) channel(
            .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.enable(enable[c]),.timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),
            .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
            .cfg_ready(ready[c]),.cfg_rdata(rdata[c*32+:32]),.cfg_error(err[c]),.cfg_error_code(err_code[c*4+:4]),
            .scan_start(scan_start[c]),.cycle_id(cycle_id[c*32+:32]),.sine_phase(sine_phase[c*32+:32]),
            .wms_running(wms_running[c]),.phase_valid(phase_valid[c]),.config_changed(config_changed[c]),
            .dac_sclk(dac_sclk[c]),.dac_sync_n(dac_sync_n[c]),.dac_sdin(dac_sdin[c]),.dac_sdo(dac_sdo[c]),
            .dac_rst_n(dac_rst_n[c]),.dac_clr_n(dac_clr_n[c]),.dac_ldac_n(dac_ldac_n[c]));
    end endgenerate
endmodule
`default_nettype wire
