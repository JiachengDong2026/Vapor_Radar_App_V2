`timescale 1ns/1ps
module adc3660_ddr_rx #(
    parameter integer SIMULATION=0
)(
    input wire rst_n, input wire dclk, input wire fclk,
    input wire da5,input wire da6,input wire go,
    output wire rx_clk,output wire clock_locked,
    output reg word_valid,output reg [15:0] word_data,
    output reg alignment_toggle
);
    wire [2:0] rise_bits,fall_bits;
    wire reset_request_n=rst_n && clock_locked;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] capture_reset_pipe;
    always @(posedge rx_clk or negedge reset_request_n)begin
        if(!reset_request_n)capture_reset_pipe<=0;
        else capture_reset_pipe<={capture_reset_pipe[1:0],1'b1};
    end
    wire capture_rst_n=capture_reset_pipe[2];
    generate if(SIMULATION!=0)begin:g_sim
        assign #5 rx_clk=dclk;
        assign clock_locked=rst_n;
        reg [2:0] r,f,r_delay,f_delay;
        always @(posedge rx_clk)begin r<={fclk,da5,da6};r_delay<=r;f_delay<=f;end
        always @(negedge rx_clk)f<={fclk,da5,da6};
        assign rise_bits=r_delay;assign fall_bits=f_delay;
    end else begin:g_hw
        wire feedback,feedback_buf,shifted;
        MMCME4_BASE #(.CLKIN1_PERIOD(20.0),.CLKFBOUT_MULT_F(20.0),
            .DIVCLK_DIVIDE(1),.CLKOUT0_DIVIDE_F(20.0),.CLKOUT0_PHASE(90.0)) u_mmcm(
            .CLKIN1(dclk),.CLKFBIN(feedback_buf),.RST(!rst_n),.PWRDWN(1'b0),
            .CLKFBOUT(feedback),.CLKOUT0(shifted),.LOCKED(clock_locked),
            .CLKFBOUTB(),.CLKOUT0B(),.CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),
            .CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6());
        BUFG u_feedback(.I(feedback),.O(feedback_buf));
        BUFG u_capture_clock(.I(shifted),.O(rx_clk));
        wire [2:0] pins={fclk,da5,da6};
        genvar g;
        for(g=0;g<3;g=g+1)begin:g_iddr
            IDDRE1 #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),.IS_C_INVERTED(1'b0),.IS_CB_INVERTED(1'b1)) u_iddr(
                .C(rx_clk),.CB(rx_clk),.D(pins[g]),.R(!capture_rst_n),.Q1(rise_bits[g]),.Q2(fall_bits[g]));
        end
    end endgenerate
    (* ASYNC_REG="TRUE" *) reg go_meta,go_sync;
    reg prev_fclk,active;
    reg [3:0] count;
    reg [7:0] high_byte,low_byte;
    reg p,a;
    reg [3:0] c;
    reg [7:0] h,l;
    reg [2:0] b;
    integer j;
    always @(posedge rx_clk or negedge capture_rst_n)begin
        if(!capture_rst_n)begin
            go_meta<=0;go_sync<=0;prev_fclk<=0;active<=0;count<=0;
            high_byte<=0;low_byte<=0;word_valid<=0;word_data<=0;alignment_toggle<=0;
        end else begin
            go_meta<=go;go_sync<=go_meta;word_valid<=0;
            p=prev_fclk;a=active;c=count;h=high_byte;l=low_byte;
            for(j=0;j<2;j=j+1)begin
                b=j==0?rise_bits:fall_bits;
                // LOCKED only asserts capture_reset_pipe asynchronously; its
                // synchronized release protects this entire sequential block.
                if(!go_sync)begin a=0;c=0;end
                else if(!a)begin if(!p && b[2])begin a=1;c=0;end end
                else if(p!=b[2])begin
                    if(c!=0)alignment_toggle<=~alignment_toggle;
                    c=0;
                end
                if(a)begin
                    h={h[6:0],b[1]};l={l[6:0],b[0]};
                    if(c==7)begin word_data<={h,l};word_valid<=1;c=0;end
                    else c=c+1'b1;
                end
                p=b[2];
            end
            prev_fclk<=p;active<=a;count<=c;high_byte<=h;low_byte<=l;
        end
    end
endmodule

