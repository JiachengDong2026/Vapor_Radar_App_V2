`include "project_defs.vh"
`include "register_map.vh"
`default_nettype none
module wms_dac_channel #(
    parameter integer SYS_CLK_HZ=`SYS_CLK_HZ,
    parameter [31:0] WMS_BASE=`REG_BASE_WMS0,DAC_BASE=`REG_BASE_DAC0,
    parameter [15:0] WMS_ID=`SRC_WMS0,DAC_ID=16'h0012
)(
    input wire sys_clk,input wire rst_sys_n,input wire enable,
    input wire [63:0] timestamp_now,input wire time_sync_valid,
    input tri0 pps_pulse,input tri0 pps_qualified,
    input tri0 [63:0] pps_tick,input tri0 [31:0] pps_seq,
    input tri1 dlia_trigger_ready,input tri1 dlia_scan_drained,output wire pps_mode,output wire scan_aborted,
    input wire cfg_valid,input wire cfg_write,input wire [31:0] cfg_addr,
    input wire [31:0] cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output wire [31:0] cfg_rdata,output wire cfg_error,
    output wire scan_start,output wire [31:0] cycle_id,output wire [31:0] sine_phase,
    output wire wms_running,output wire phase_valid,output wire config_changed,
    output wire dac_sclk,output wire dac_sync_n,output wire dac_sdin,input wire dac_sdo,
    output wire dac_rst_n,output wire dac_clr_n,output wire dac_ldac_n,
    output wire [3:0] cfg_error_code
);
    wire wr,dr,we,de;
    wire [3:0] we_code,de_code;
    wire [31:0] wd,dd,sample_data,max_rate;
    wire sample_valid,sample_ready,operational,sample_applied;
    wire scheduled_start,scheduled_valid,sample_window,sample_first;
    wire [31:0] scheduled_cycle,scheduled_phase;
    reg applied_valid,applied_start,tx_window,tx_first;
    reg [31:0] applied_cycle,applied_phase,tx_cycle,tx_phase;
    assign scan_start=pps_mode?(operational && sample_applied && tx_window && tx_first):scheduled_start;
    assign phase_valid=pps_mode?(operational && (sample_applied?tx_window:applied_valid)):scheduled_valid;
    assign cycle_id=pps_mode?(sample_applied?tx_cycle:applied_cycle):scheduled_cycle;
    assign sine_phase=pps_mode?(sample_applied?tx_phase:applied_phase):scheduled_phase;
    // Metadata belongs to the accepted SPI transaction, never live DDS state.
    always @(posedge sys_clk)begin
        if(!rst_sys_n)begin
            applied_valid<=0;applied_start<=0;applied_cycle<=0;applied_phase<=0;
            tx_window<=0;tx_first<=0;tx_cycle<=0;tx_phase<=0;
        end else begin
            applied_start<=0;
            if(sample_valid && sample_ready)begin
                tx_window<=sample_window;tx_first<=sample_first;
                tx_cycle<=scheduled_cycle;tx_phase<=scheduled_phase;
            end
            if(sample_applied)begin
                applied_valid<=tx_window;applied_start<=tx_window && tx_first;
                applied_cycle<=tx_cycle;applied_phase<=tx_phase;
            end
            if(!operational)begin applied_valid<=0;applied_start<=0;end
        end
    end
    assign cfg_ready=wr|dr;
    assign cfg_error=(wr && we)|(dr && de);
    assign cfg_error_code=({4{wr && we}} & we_code)|({4{dr && de}} & de_code);
    assign cfg_rdata=({32{wr}} & wd)|({32{dr}} & dd);
    wms_wavegen #(.SYS_CLK_HZ(SYS_CLK_HZ),.BASE_ADDR(WMS_BASE),.MODULE_ID(WMS_ID)) wms(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.enable(enable),.timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),
        .transport_ready(operational),.max_update_hz(max_rate),
        .pps_pulse(pps_pulse),.pps_qualified(pps_qualified),.pps_tick(pps_tick),.pps_seq(pps_seq),
        .dlia_trigger_ready(dlia_trigger_ready),.dlia_scan_drained(dlia_scan_drained),.sample_applied(sample_applied),
        .applied_window(tx_window),.applied_first(tx_first),.pps_mode(pps_mode),.scan_aborted(scan_aborted),
        .sample_window(sample_window),.sample_first(sample_first),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(wr),.cfg_rdata(wd),.cfg_error(we),.cfg_error_code(we_code),
        .dac_sample(sample_data),.dac_sample_valid(sample_valid),.dac_sample_ready(sample_ready),
        .scan_start(scheduled_start),.cycle_id(scheduled_cycle),.sine_phase(scheduled_phase),.wms_running(wms_running),
        .phase_valid(scheduled_valid),.config_changed(config_changed));
    dac_ad5791_if #(.SYS_CLK_HZ(SYS_CLK_HZ),.BASE_ADDR(DAC_BASE),.MODULE_ID(DAC_ID)) dac(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.enable(enable),.timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),
        .stream_active(wms_running),.cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(dr),.cfg_rdata(dd),.cfg_error(de),.cfg_error_code(de_code),.dac_sample(sample_data),.dac_sample_valid(sample_valid),.dac_sample_ready(sample_ready),
        .operational(operational),.max_update_hz(max_rate),.sample_applied(sample_applied),
        .dac_sclk(dac_sclk),.dac_sync_n(dac_sync_n),.dac_sdin(dac_sdin),.dac_sdo(dac_sdo),
        .dac_rst_n(dac_rst_n),.dac_clr_n(dac_clr_n),.dac_ldac_n(dac_ldac_n));
endmodule
`default_nettype wire
