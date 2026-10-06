`default_nettype none
// VLP-GPIF hardware mapping follows the FX3 pin table and AN65974, not the
// inconsistent CTL2/3 and PKTEND assignments in the original project guide.
module usb_fx3_gpif_if #(
    parameter integer SIMULATION=0
)(
    input wire gpif_clk,rst_gpif_n,
    inout wire [31:0] usb_dq,
    inout wire [12:0] usb_ctl,
    output wire usb_pclk,
    input wire tx_valid,
    output wire tx_ready,
    input wire [31:0] tx_data,
    input wire tx_last,
    output wire rx_valid,
    input wire rx_ready,
    output wire [31:0] rx_data,
    input wire [31:0] rx_free,
    output wire [31:0] tx_word_count,rx_word_count,tx_frame_count,error_count,stall_count,
    output wire idle
);
    wire [31:0] dq_out;
    wire dq_oe,slcs_n,slwr_n,slrd_n,sloe_n,pktend_n;
    wire [1:0] fifo_addr;
    // Master launches at rising edge L; pad registers update at L+1/2.
    // FX3 still samples that transfer at rising edge L+1. Opposite-edge launch
    // gives a real half-cycle hold margin relative to forwarded PCLK, including
    // the clock ODDRE1/OBUF delay. SIMULATION follows the same pad timing.
    (* IOB="TRUE" *) reg [31:0] pad_dq;
    (* IOB="TRUE" *) reg pad_slcs_n,pad_slwr_n,pad_slrd_n,pad_sloe_n,pad_pktend_n;
    (* IOB="TRUE" *) reg [1:0] pad_addr;
    reg pad_dq_oe;
    always @(negedge gpif_clk or negedge rst_gpif_n) begin
        if(!rst_gpif_n) begin
            pad_dq<=0;pad_dq_oe<=0;pad_slcs_n<=1;pad_slwr_n<=1;
            pad_slrd_n<=1;pad_sloe_n<=1;pad_pktend_n<=1;pad_addr<=0;
        end else begin
            pad_dq<=dq_out;pad_dq_oe<=dq_oe;pad_slcs_n<=slcs_n;pad_slwr_n<=slwr_n;
            pad_slrd_n<=slrd_n;pad_sloe_n<=sloe_n;pad_pktend_n<=pktend_n;pad_addr<=fifo_addr;
        end
    end
    assign usb_dq=pad_dq_oe ? pad_dq : 32'bz;
    assign usb_ctl[0]=pad_slcs_n;
    assign usb_ctl[1]=pad_slwr_n;
    assign usb_ctl[2]=pad_sloe_n;
    assign usb_ctl[3]=pad_slrd_n;
    assign usb_ctl[4]=1'bz;
    assign usb_ctl[5]=1'bz;
    assign usb_ctl[6]=1'bz;
    assign usb_ctl[7]=pad_pktend_n;
    assign usb_ctl[8]=1'bz;
    assign usb_ctl[10:9]=2'bzz;
    assign usb_ctl[11]=pad_addr[1];
    assign usb_ctl[12]=pad_addr[0];
    generate if(SIMULATION)begin:g_sim
        assign usb_pclk=gpif_clk;
    end else begin:g_hw
        ODDRE1 #(.IS_C_INVERTED(1'b0),.IS_D1_INVERTED(1'b0),.IS_D2_INVERTED(1'b0),.SRVAL(1'b0)) u_pclk(
            .C(gpif_clk),.D1(1'b1),.D2(1'b0),.SR(!rst_gpif_n),.Q(usb_pclk));
    end endgenerate
    gpif_slave_fifo_master u_master(
        .gpif_clk(gpif_clk),.rst_gpif_n(rst_gpif_n),
        .tx_valid(tx_valid),.tx_ready(tx_ready),.tx_data(tx_data),.tx_last(tx_last),
        .rx_valid(rx_valid),.rx_ready(rx_ready),.rx_data(rx_data),.rx_free(rx_free),
        .flag_tx_ready(usb_ctl[4]),.flag_rx_ready(usb_ctl[5]),
        .flag_tx_partial(usb_ctl[6]),.flag_rx_partial(usb_ctl[8]),
        .dq_in(usb_dq),.dq_out(dq_out),.dq_oe(dq_oe),
        .slcs_n(slcs_n),.slwr_n(slwr_n),.slrd_n(slrd_n),.sloe_n(sloe_n),.pktend_n(pktend_n),
        .fifo_addr(fifo_addr),.tx_word_count(tx_word_count),.rx_word_count(rx_word_count),
        .tx_frame_count(tx_frame_count),.error_count(error_count),.stall_count(stall_count),.idle(idle));
endmodule
`default_nettype wire
