`default_nettype none
// Real board MMCM and two unmodified AD5791 serializers. This physical fixture
// retains sample traffic at both DAC pads; it is not an application bitstream.
module dac_phy_smoke(
    input wire CLK_FPGA_25MHZ,
    output wire [1:0] dac_sclk,dac_sync_n,dac_sdin,dac_rst_n,dac_clr_n,dac_ldac_n,
    input wire [1:0] dac_sdo
);
    reg [7:0] por=0;
    always @(posedge CLK_FPGA_25MHZ)por<={por[6:0],1'b1};
    wire sys_clk,gpif_clk,rst_sys_n,rst_gpif_n,locked;
    clk_rst_mgr #(.GPIF_CLK_HZ(50000000)) u_clock(
        .ref_clk(CLK_FPGA_25MHZ),.ext_reset_n(&por),.sw_global_reset(1'b0),
        .sys_clk(sys_clk),.gpif_clk(gpif_clk),.rst_sys_n(rst_sys_n),.rst_gpif_n(rst_gpif_n),.clocks_locked(locked),.rst_persistent_n());
    wire [1:0] ready,ce,cr,operational;
    wire [63:0] rd,cap;
    reg [1:0] configured;
    reg [31:0] sample0,sample1;reg [9:0] heartbeat;
    always @(posedge sys_clk)begin
        if(!rst_sys_n)begin configured<=0;sample0<=32'h5a3c19e7;sample1<=32'hc3146ab9;heartbeat<=0;end
        else begin
            heartbeat<=heartbeat+1'b1;
            if(cr[0])configured[0]<=1;if(cr[1])configured[1]<=1;
            if(ready[0])sample0<={sample0[30:0],sample0[31]^sample0[21]^sample0[1]^sample0[0]};
            if(ready[1])sample1<=sample1+32'h10203041;
        end
    end
    genvar c;
    generate for(c=0;c<2;c=c+1)begin:channels
        dac_ad5791_if #(.BASE_ADDR(32'h3000+c*256)) u_dac(
            .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.enable(1'b1),.timestamp_now(64'd0),.time_sync_valid(1'b0),.stream_active(1'b0),
            .cfg_valid(!configured[c] || heartbeat==c),.cfg_write(1'b1),.cfg_addr(32'h3004+c*256),.cfg_wdata(configured[c]?32'd17:32'd1),.cfg_wstrb(4'hf),
            .cfg_ready(cr[c]),.cfg_error(ce[c]),.cfg_rdata(rd[c*32+:32]),.cfg_error_code(),
            .dac_sample(c==0?sample0:sample1),.dac_sample_valid(1'b1),.dac_sample_ready(ready[c]),
            .operational(operational[c]),.max_update_hz(cap[c*32+:32]),
            .dac_sclk(dac_sclk[c]),.dac_sync_n(dac_sync_n[c]),.dac_sdin(dac_sdin[c]),.dac_sdo(dac_sdo[c]),
            .dac_rst_n(dac_rst_n[c]),.dac_clr_n(dac_clr_n[c]),.dac_ldac_n(dac_ldac_n[c]));
    end endgenerate
endmodule
`default_nettype wire
