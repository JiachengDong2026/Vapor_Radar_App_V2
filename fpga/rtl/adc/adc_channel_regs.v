`include "project_defs.vh"
`include "register_map.vh"
`include "error_codes.vh"
module adc_channel_regs #(
    parameter integer CHANNEL = 0,
    parameter integer SYS_CLK_HZ = 100000000,
    parameter integer DEFAULT_RATE = 1000000,
    parameter integer SHARED_AD4630 = 0,
    parameter [31:0] BASE_ADDR = 32'h4000
)(
    input wire clk, input wire rst_n, input wire scan_start,
    input wire cfg_valid, input wire cfg_write, input wire [31:0] cfg_addr,
    input wire [31:0] cfg_wdata, input wire [3:0] cfg_wstrb,
    output wire cfg_ready, output reg [31:0] cfg_rdata, output reg cfg_error,
    input wire initialized, input wire phy_busy, input wire capture_pulse,
    input wire overflow_pulse, input wire timeout_pulse, input wire align_pulse,
    input wire [1:0] external_drop_increment,
    input wire [31:0] fifo_level, input wire [31:0] sync_count,
    output reg enable, output reg raw_enable, output wire soft_reset,
    output wire clear_fifo, output reg [31:0] period_ticks,
    output reg [31:0] rate_actual, output reg [31:0] cnv_ticks,
    output reg [31:0] busy_timeout, output reg [31:0] expected_per_cycle,
    output reg [31:0] error_status,
    output reg [3:0] cfg_error_code,
    input wire shared_peer_enable, input wire shared_timing_pending,
    input wire [31:0] shared_rate_actual,
    input wire [31:0] shared_cnv_ticks, input wire [31:0] shared_busy_timeout,
    output wire timing_pending
);
    reg [31:0] requested, cnv_shadow, timeout_shadow, expected_shadow;
    reg pending;
    assign timing_pending=pending;
    reg div_start;
    reg [1:0] div_state;
    reg [31:0] div_num,div_den,period_next,rate_next;
    reg [31:0] requested_commit,cnv_commit,timeout_commit,expected_commit;
    wire div_done,div_busy;
    wire [31:0] div_result;
    member1_divider u_rate_div(.clk(clk),.rst_n(rst_n && !soft_reset),.start(div_start),
        .numerator(div_num),.denominator(div_den),.busy(div_busy),.done(div_done),.quotient(div_result));
    reg [31:0] drops;
    reg [63:0] samples;
    wire hit=cfg_valid && cfg_addr[31:8]==BASE_ADDR[31:8];
    wire [7:0] ofs=cfg_addr[7:0];
    wire [31:0] mask={{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    wire [31:0] wd=cfg_wdata & mask;
    reg [31:0] merged;
    assign cfg_ready=hit;
    wire wr=hit && cfg_write && !cfg_error;
    assign soft_reset=wr && ofs==4 && wd[1];
    assign clear_fifo=soft_reset || (wr && ofs==4 && wd[3]);
    always @* begin
        cfg_rdata=0; cfg_error=0; merged=0;
        if(hit) begin
            case(ofs)
                8'h00: begin
                    cfg_rdata=SHARED_AD4630 ? (CHANNEL==0 ? `ADC_DUAL_AD4630_ID0:`ADC_DUAL_AD4630_ID1) :
                        (CHANNEL==0 ? 32'h00200100:32'h00210100);
                    cfg_error=cfg_write;
                end
                8'h04: begin
                    cfg_rdata={31'd0,enable};
                    if(cfg_write && ((wd[2] && pending) || |wd[31:4]))cfg_error=1;
                    // Channel zero owns the shared PHY. Require a stopped,
                    // drained conversion before resetting or committing it.
                    if(SHARED_AD4630 && cfg_write)begin
                        if(wd[0] && shared_timing_pending)cfg_error=1;
                        if(CHANNEL==0 && (wd[1] || wd[2]) &&
                           (enable || shared_peer_enable || phy_busy || wd[0]))cfg_error=1;
                    end
                end
                8'h08: begin
                    cfg_rdata[0]=enable; cfg_rdata[1]=initialized;
                    cfg_rdata[2]=pending; cfg_rdata[3]=phy_busy;
                    cfg_rdata[4]=initialized; cfg_rdata[5]=fifo_level>=240;
                    cfg_rdata[6]=error_status[2];cfg_rdata[7]=|error_status;
                    cfg_error=cfg_write;
                end
                8'h0c: cfg_rdata=error_status;
                8'h10: begin
                    cfg_rdata=requested; merged=(requested & ~mask)|wd;
                    if(cfg_write && (CHANNEL==0 ? (merged<1000 || merged>1000000) : merged!=DEFAULT_RATE)) cfg_error=1;
                    if(SHARED_AD4630 && CHANNEL==1)begin cfg_rdata=shared_rate_actual;cfg_error=cfg_write;end
                end
                8'h14: begin cfg_rdata=(SHARED_AD4630 && CHANNEL==1)?shared_rate_actual:rate_actual;cfg_error=cfg_write;end
                8'h18: begin cfg_rdata=(CHANNEL==0 || SHARED_AD4630)?32'h00011800:32'h00011000;cfg_error=cfg_write;end
                8'h1c: cfg_rdata=expected_shadow;
                8'h20: begin cfg_rdata=fifo_level;cfg_error=cfg_write;end
                8'h24: cfg_rdata=drops;
                8'h28: begin cfg_rdata=samples[31:0];cfg_error=cfg_write;end
                8'h2c: begin cfg_rdata=samples[63:32];cfg_error=cfg_write;end
                8'h30: begin
                    cfg_rdata=CHANNEL==0?cnv_shadow:32'h00000210;
                    merged=(cnv_shadow & ~mask)|wd;
                    if(cfg_write && (CHANNEL==0 ? (merged<2 || merged>20) : wd!=32'h210)) cfg_error=1;
                    if(SHARED_AD4630 && CHANNEL==1)begin cfg_rdata=shared_cnv_ticks;cfg_error=cfg_write;end
                end
                8'h34: begin
                    cfg_rdata=CHANNEL==0?timeout_shadow:{31'd0,initialized};
                    merged=(timeout_shadow & ~mask)|wd;
                    if(cfg_write && (CHANNEL!=0 || merged<40 || merged>1000000)) cfg_error=1;
                    if(SHARED_AD4630 && CHANNEL==1)begin cfg_rdata=shared_busy_timeout;cfg_error=cfg_write;end
                end
                8'h38: begin cfg_rdata=(CHANNEL==0 || SHARED_AD4630)?32'h80:sync_count;cfg_error=cfg_write;end
                8'h3c: begin cfg_rdata={31'd0,raw_enable};if(cfg_write && |wd[31:1])cfg_error=1;end
                8'h40: begin cfg_rdata=5000000;cfg_error=cfg_write || CHANNEL==0 || SHARED_AD4630;end
                default:cfg_error=1;
            endcase
        end
    end
    // VLP transaction cause; acquisition timeouts remain runtime ERROR bits.
    always @*begin
        cfg_error_code=0;
        if(hit && cfg_error)case(ofs)
            8'h00,8'h08,8'h14,8'h18,8'h20,8'h28,8'h2c,8'h38:cfg_error_code=6;
            8'h04:cfg_error_code=(|wd[31:4])?7:8;
            8'h10,8'h30:cfg_error_code=(SHARED_AD4630 && CHANNEL==1)?6:7;
            8'h3c:cfg_error_code=7;
            8'h34:cfg_error_code=CHANNEL==0?7:6;
            8'h40:cfg_error_code=(CHANNEL==0 || SHARED_AD4630)?5:6;
            default:cfg_error_code=5;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            enable<=0;raw_enable<=0;pending<=0;requested<=DEFAULT_RATE;
            div_start<=0;div_state<=0;div_num<=0;div_den<=1;period_next<=SYS_CLK_HZ/DEFAULT_RATE;
            rate_next<=DEFAULT_RATE;requested_commit<=DEFAULT_RATE;cnv_commit<=2;timeout_commit<=100;expected_commit<=0;
            period_ticks<=SYS_CLK_HZ/DEFAULT_RATE;rate_actual<=DEFAULT_RATE;
            cnv_shadow<=2;cnv_ticks<=2;timeout_shadow<=100;busy_timeout<=100;
            expected_shadow<=0;expected_per_cycle<=0;drops<=0;samples<=0;error_status<=0;
        end else begin
            div_start<=0;
            if(wr) case(ofs)
                8'h04: begin
                    enable<=(enable & ~mask[0])|wd[0];
                    if(wd[2])begin
                        pending<=1;requested_commit<=requested;cnv_commit<=cnv_shadow;
                        timeout_commit<=timeout_shadow;expected_commit<=expected_shadow;
                    end
                end
                8'h0c:error_status<=error_status & ~wd;
                8'h10:requested<=(requested & ~mask)|wd;
                8'h1c:expected_shadow<=(expected_shadow & ~mask)|wd;
                8'h24:drops<=drops & ~wd;
                8'h30:if(CHANNEL==0)cnv_shadow<=(cnv_shadow & ~mask)|wd;
                8'h34:if(CHANNEL==0)timeout_shadow<=(timeout_shadow & ~mask)|wd;
                8'h3c:raw_enable<=(raw_enable & ~mask[0])|wd[0];
                default:begin end
            endcase
            if(pending && div_state==0) begin
                div_num<=SYS_CLK_HZ+requested_commit-1;div_den<=requested_commit;
                div_start<=1;div_state<=1;
            end
            if(div_done && div_state==1)begin
                period_next<=div_result;div_num<=SYS_CLK_HZ;div_den<=div_result;
                div_start<=1;div_state<=2;
            end
            if(div_done && div_state==2)begin
                rate_next<=div_result;div_state<=3;
            end
            if(pending && div_state==3 && (scan_start || !enable))begin
                period_ticks<=period_next;rate_actual<=rate_next;
                cnv_ticks<=cnv_commit;busy_timeout<=timeout_commit;
                expected_per_cycle<=expected_commit;pending<=0;div_state<=0;
            end
            if(hit && cfg_write && cfg_error)error_status[4]<=1;
            if(capture_pulse)samples<=samples+1'b1;
            if(overflow_pulse || external_drop_increment!=0)begin drops<=drops+overflow_pulse+external_drop_increment;error_status[2]<=1;end
            if(timeout_pulse)error_status[0]<=1;
            if(align_pulse)error_status[7]<=1;
            if(soft_reset)begin drops<=0;samples<=0;error_status<=0;pending<=0;div_state<=0;end
        end
    end
endmodule

