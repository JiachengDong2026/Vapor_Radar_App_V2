`default_nettype none
// The board reference continues while the MMCM output is unavailable. A LOCKED
// low interval spanning two reference samples is counted once; initial startup
// is not a fault. Transfer fault_total with registered-Gray counter_cdc.
module clock_health_monitor(
    input wire ref_clk,por_n,clock_locked,
    output reg [31:0] fault_total
);
    (* ASYNC_REG="TRUE" *) reg locked_meta,locked_sync;
    reg was_locked;
    always @(posedge ref_clk or negedge por_n)begin
        if(!por_n)begin
            locked_meta<=0;locked_sync<=0;was_locked<=0;fault_total<=0;
        end else begin
            locked_meta<=clock_locked;locked_sync<=locked_meta;was_locked<=locked_sync;
            if(was_locked && !locked_sync)fault_total<=fault_total+1'b1;
        end
    end
endmodule
`default_nettype wire
