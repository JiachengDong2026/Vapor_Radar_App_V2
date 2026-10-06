module member1_board_clock(
    input wire clk_25mhz,output wire sys_clk,output wire rst_n
);
    wire feedback,feedback_buf,clk100,locked;
    MMCME4_BASE #(.CLKIN1_PERIOD(40.0),.CLKFBOUT_MULT_F(40.0),.CLKOUT0_DIVIDE_F(10.0)) u_mmcm(
        .CLKIN1(clk_25mhz),.CLKFBIN(feedback_buf),.RST(1'b0),.PWRDWN(1'b0),
        .CLKFBOUT(feedback),.CLKOUT0(clk100),.LOCKED(locked),.CLKFBOUTB(),.CLKOUT0B(),
        .CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),.CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6());
    BUFG u_feedback(.I(feedback),.O(feedback_buf));
    BUFG u_sys_buf(.I(clk100),.O(sys_clk));
    (* ASYNC_REG="TRUE" *) reg [3:0] reset_pipe=0;
    always @(posedge sys_clk or negedge locked)begin
        if(!locked)reset_pipe<=0;else reset_pipe<={reset_pipe[2:0],1'b1};
    end
    assign rst_n=reset_pipe[3];
endmodule

