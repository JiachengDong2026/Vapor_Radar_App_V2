`default_nettype none
// Keep the timebase and register block on the power reset. Software requests
// wait for the response/data path to drain before resetting selected groups.
module system_reset_controller #(
    parameter integer SYS_CLK_HZ=100000000,
    parameter integer DRAIN_TIMEOUT_TICKS=200000,
    parameter integer STARTUP_FX3_RESET_MS=10
)(
    input wire sys_clk,rst_power_n,
    input wire soft_request,clock_request,watchdog_request,
    input wire stream_reset_request,stream_clear_request,usb_clear_request,fx3_request,
    input wire [31:0] reset_mask,fx3_reset_ms,
    input wire path_quiet,
    output wire reset_pending,
    output wire rst_control_n,rst_adc_n,rst_wms_n,rst_sensors_n,rst_motor_n,rst_stream_n,rst_transport_n,
    output wire fx3_reset_n,
    output reg [31:0] forced_clear_count
);
    localparam integer MS_TICKS=SYS_CLK_HZ/1000;
    reg pending,physical_pending;
    reg [5:0] pending_mask,active_mask;
    reg [31:0] timeout_count,ms_div,fx3_remaining_ms;
    reg [5:0] quiet_count;
    reg [4:0] reset_count;
    wire all_request=soft_request || clock_request || watchdog_request;
    wire any_request=all_request || stream_reset_request || stream_clear_request || usb_clear_request || fx3_request;
    wire [5:0] requested_mask=watchdog_request ? 6'h3f :
        ((all_request ? (reset_mask[5:0]==0 ? 6'h3f : reset_mask[5:0]) : 6'd0) |
         ((stream_reset_request || stream_clear_request || usb_clear_request || fx3_request) ? 6'h30 : 6'd0));
    // Resetting any producer also releases locked fragments downstream.
    wire [5:0] expanded_mask=requested_mask | ((|requested_mask[3:0]) ? 6'h30 : 6'd0);
    assign reset_pending=pending || reset_count!=0;
    assign rst_control_n=rst_power_n && reset_count==0;
    assign rst_adc_n=rst_power_n && !(reset_count!=0 && active_mask[0]);
    assign rst_wms_n=rst_power_n && !(reset_count!=0 && active_mask[1]);
    assign rst_sensors_n=rst_power_n && !(reset_count!=0 && active_mask[2]);
    assign rst_motor_n=rst_power_n && !(reset_count!=0 && active_mask[3]);
    assign rst_stream_n=rst_power_n && !(reset_count!=0 && active_mask[4]);
    assign fx3_reset_n=rst_power_n && fx3_remaining_ms==0;
    assign rst_transport_n=rst_power_n && fx3_reset_n && !(reset_count!=0 && active_mask[5]);
    always @(posedge sys_clk or negedge rst_power_n)begin
        if(!rst_power_n)begin
            pending<=0;physical_pending<=0;pending_mask<=0;active_mask<=0;
            timeout_count<=0;quiet_count<=0;reset_count<=0;forced_clear_count<=0;
            ms_div<=0;fx3_remaining_ms<=STARTUP_FX3_RESET_MS;
        end else begin
            if(ms_div==MS_TICKS-1)begin
                ms_div<=0;
                if(fx3_remaining_ms!=0)fx3_remaining_ms<=fx3_remaining_ms-1'b1;
            end else ms_div<=ms_div+1'b1;
            if(reset_count!=0)reset_count<=reset_count-1'b1;
            if(pending)begin
                timeout_count<=timeout_count+1'b1;
                if(path_quiet)begin if(quiet_count<32)quiet_count<=quiet_count+1'b1;end
                else quiet_count<=0;
                if(quiet_count==32 || timeout_count>=DRAIN_TIMEOUT_TICKS-1)begin
                    pending<=0;active_mask<=pending_mask;reset_count<=16;
                    if(quiet_count!=32)forced_clear_count<=forced_clear_count+1'b1;
                    if(physical_pending)begin
                        fx3_remaining_ms<=fx3_reset_ms==0 ? 1 : fx3_reset_ms;ms_div<=0;
                    end
                    physical_pending<=0;pending_mask<=0;
                end
            end
            // A request arriving during execution is retained for another pass.
            if(any_request)begin
                pending<=1;pending_mask<=pending_mask|expanded_mask;
                // Only the explicit USB physical-reset request resets FX3.
                // Internal group resets preserve the running USB firmware.
                physical_pending<=physical_pending || fx3_request;
                timeout_count<=0;quiet_count<=0;
            end
        end
    end
endmodule
`default_nettype wire
