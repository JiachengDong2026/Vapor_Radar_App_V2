`default_nettype none
// Board's 25 MHz AK17 reference -> 100 MHz sys and GPIF. SIMULATION supplies
// already-scaled clocks for fast tests; the production branch uses MMCME4.
module clk_rst_mgr #(
    parameter integer SIMULATION=0,
    parameter integer GPIF_CLK_HZ=100000000,
    parameter integer RELEASE_CYCLES=16
)(
    input wire ref_clk,ext_reset_n,sw_global_reset,
    output wire sys_clk,gpif_clk,rst_sys_n,rst_gpif_n,clocks_locked,
    output wire rst_persistent_n
);
    wire clock_locked, sys_raw,gpif_raw;
    generate if(SIMULATION)begin:g_sim
        reg [4:0] lock_count;
        always @(posedge ref_clk or negedge ext_reset_n)
            if(!ext_reset_n)lock_count<=0;
            else if(lock_count!=31)lock_count<=lock_count+1'b1;
        assign clock_locked=&lock_count;
        assign sys_clk=ref_clk;
        if(GPIF_CLK_HZ==50000000)begin:g_half
            reg gpif_half;
            always @(posedge ref_clk or negedge ext_reset_n)
                if(!ext_reset_n)gpif_half<=0;
                else gpif_half<=!gpif_half;
            assign gpif_clk=gpif_half;
        end else begin:g_full
            assign gpif_clk=ref_clk;
        end
    end else begin:g_hw
        wire feedback,feedback_buffered;
        MMCME4_BASE #(.CLKIN1_PERIOD(40.0),.DIVCLK_DIVIDE(1),
            .CLKFBOUT_MULT_F(40.0),.CLKOUT0_DIVIDE_F(10.0),.CLKOUT1_DIVIDE(1000000000/GPIF_CLK_HZ),
            .STARTUP_WAIT("FALSE")) u_mmcm(
            .CLKIN1(ref_clk),.CLKFBIN(feedback_buffered),.RST(!ext_reset_n),.PWRDWN(1'b0),
            .CLKFBOUT(feedback),.CLKFBOUTB(),.CLKOUT0(sys_raw),.CLKOUT0B(),
            .CLKOUT1(gpif_raw),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),
            .CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.LOCKED(clock_locked));
        BUFG u_feedback(.I(feedback),.O(feedback_buffered));
        BUFG u_sys(.I(sys_raw),.O(sys_clk));
        BUFG u_gpif(.I(gpif_raw),.O(gpif_clk));
    end endgenerate
    wire release_reset=ext_reset_n && clock_locked && !sw_global_reset;
    (* ASYNC_REG="TRUE" *)reg[RELEASE_CYCLES-1:0] sys_release,gpif_release;
    // Diagnostic/time state survives a later MMCM unlock. POR alone clears it.
    // Latch the already synchronized operational release. Raw MMCM LOCKED must
    // never fan into synchronous data/enable logic outside its first capture.
    reg persistent_ready;
    always @(posedge sys_clk or negedge ext_reset_n)
        if(!ext_reset_n)persistent_ready<=0;
        else if(sys_release[RELEASE_CYCLES-1])persistent_ready<=1;
    assign rst_persistent_n=persistent_ready;
    always @(posedge sys_clk or negedge release_reset)
        if(!release_reset)sys_release<=0;
        else sys_release<={sys_release[RELEASE_CYCLES-2:0],1'b1};
    always @(posedge gpif_clk or negedge release_reset)
        if(!release_reset)gpif_release<=0;
        else gpif_release<={gpif_release[RELEASE_CYCLES-2:0],1'b1};
    assign clocks_locked=clock_locked;
    assign rst_sys_n=sys_release[RELEASE_CYCLES-1];
    assign rst_gpif_n=gpif_release[RELEASE_CYCLES-1];
endmodule
`default_nettype wire
