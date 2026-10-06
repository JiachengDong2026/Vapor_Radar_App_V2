`default_nettype none
// Physical timing fixture: real board MMCM and GPIF pads. Synthetic bidirectional
// traffic retains data/control/FIFO logic; this is not a VLP application image.
module gpif_phy_smoke #(parameter integer GPIF_CLK_HZ=100000000)(
    input wire CLK_FPGA_25MHZ,
    inout wire [31:0] FPGA_GPIF_DQ,
    inout wire [12:0] FPGA_GPIF_CTL,
    output wire FPGA_GPIF_PCLK,CYUSB_RSTN
);
    reg [7:0] por=0;
    always @(posedge CLK_FPGA_25MHZ)por<={por[6:0],1'b1};
    wire sys_clk,gpif_clk,rst_sys_n,rst_gpif_n,locked;
    clk_rst_mgr #(.GPIF_CLK_HZ(GPIF_CLK_HZ)) u_clock(
        .ref_clk(CLK_FPGA_25MHZ),.ext_reset_n(&por),.sw_global_reset(1'b0),
        .sys_clk(sys_clk),.gpif_clk(gpif_clk),.rst_sys_n(rst_sys_n),.rst_gpif_n(rst_gpif_n),.clocks_locked(locked));
    assign CYUSB_RSTN=rst_gpif_n;
    wire tx_ready,rx_valid,rx_ready,phy_idle;
    wire [31:0] rx_data,tx_words,rx_words,tx_frames,phy_errors,stalls;
    wire [31:0] level,sink_data;
    wire sink_valid;
    reg [31:0] tx_data,tx_sequence,rx_signature;
    reg [5:0] pacer;
    always @(posedge gpif_clk or negedge rst_gpif_n)begin
        if(!rst_gpif_n)begin tx_data<=32'h5a5aa5a5;tx_sequence<=0;rx_signature<=0;pacer<=0;end
        else begin
            pacer<=pacer+1'b1;
            if(tx_ready)begin
                tx_sequence<=tx_sequence+1'b1;
                tx_data<=tx_data+32'h10203041+rx_signature+tx_words+rx_words+tx_frames+phy_errors+stalls;
            end
            if(sink_valid && pacer[2:0]!=0)rx_signature<={rx_signature[30:0],rx_signature[31]}^sink_data;
        end
    end
    sync_fifo #(.WIDTH(32),.DEPTH(64)) u_rx_sink(
        .clk(gpif_clk),.rst_n(rst_gpif_n),.s_valid(rx_valid),.s_ready(rx_ready),.s_data(rx_data),
        .m_valid(sink_valid),.m_ready(pacer[2:0]!=0),.m_data(sink_data),
        .full(),.empty(),.almost_full(),.level(level),.full_stall_pulse());
    usb_fx3_gpif_if u_gpif(.gpif_clk(gpif_clk),.rst_gpif_n(rst_gpif_n),
        .usb_dq(FPGA_GPIF_DQ),.usb_ctl(FPGA_GPIF_CTL),.usb_pclk(FPGA_GPIF_PCLK),
        .tx_valid(1'b1),.tx_ready(tx_ready),.tx_data(tx_data),.tx_last(tx_sequence[7:0]==8'hff),
        .rx_valid(rx_valid),.rx_ready(rx_ready),.rx_data(rx_data),.rx_free(32'd64-level),
        .tx_word_count(tx_words),.rx_word_count(rx_words),.tx_frame_count(tx_frames),.error_count(phy_errors),.stall_count(stalls),.idle(phy_idle));
endmodule
`default_nettype wire
