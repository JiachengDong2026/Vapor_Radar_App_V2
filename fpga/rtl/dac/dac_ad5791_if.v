`include "project_defs.vh"
`include "register_map.vh"
`include "error_codes.vh"
`default_nettype none
module dac_ad5791_if #(
    parameter integer SYS_CLK_HZ=`SYS_CLK_HZ,
    parameter [31:0] BASE_ADDR=`REG_BASE_DAC0,
    parameter [15:0] MODULE_ID=16'h0012
)(
    input wire sys_clk,input wire rst_sys_n,input wire enable,
    input wire [63:0] timestamp_now,input wire time_sync_valid,input wire stream_active,
    input wire cfg_valid,input wire cfg_write,input wire [31:0] cfg_addr,
    input wire [31:0] cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg [31:0] cfg_rdata,output reg cfg_error,
    input wire [31:0] dac_sample,input wire dac_sample_valid,output wire dac_sample_ready,
    output wire operational,output wire [31:0] max_update_hz,
    output reg dac_sclk,output reg dac_sync_n,output reg dac_sdin,input wire dac_sdo,
    output reg dac_rst_n,output reg dac_clr_n,output wire dac_ldac_n,
    output reg [3:0] cfg_error_code
);
    // Board IOVCC=1.8 V requires >=40 ns SCLK period. H=2 at 100 MHz
    // sits exactly on that limit; H>=3 reserves physical clock/skew margin.
    localparam integer MAX_SPI_REQUEST_HZ=20000000;
    localparam integer DEFAULT_HALF=(SYS_CLK_HZ+2*MAX_SPI_REQUEST_HZ-1)/(2*MAX_SPI_REQUEST_HZ);
    localparam integer RESET_TICKS=(SYS_CLK_HZ/1000000)+1;
    localparam integer GUARD_TICKS=(SYS_CLK_HZ+19999999)/20000000;
    localparam integer CLEAR_TICKS=(SYS_CLK_HZ+9999999)/10000000;
    reg ctl_enable;
    reg [31:0] sh_ctrl,sh_clear,sh_min,sh_max,sh_spi,sh_gain,sh_offset;
    reg [31:0] a_ctrl,a_clear,a_min,a_max,a_gain,a_offset,a_half,a_spi,a_cap;
    reg [31:0] p_ctrl,p_clear,p_min,p_max,p_gain,p_offset,p_spi,p_half,p_actual;
    reg [31:0] last_code,write_count,error_bits,clamp_count;
    reg [3:0] calc;
    reg calc_error,div_start;
    reg [95:0] div_num,div_den;
    wire div_busy,div_done;
    wire [95:0] div_q,div_rem;
    reg [3:0] state;
    localparam ST_RESET=0,ST_SETTLE=1,ST_INIT=2,ST_IDLE=3,ST_MAP1=4,ST_MAP2=5,ST_MAP3=6,
               ST_LOW=7,ST_HIGH=8,ST_END=9,ST_GUARD=10,ST_CLEAR=11;
    reg [31:0] count;
    reg [2:0] init_index;
    reg initialized,is_sample;
    reg [23:0] shift;
    reg [4:0] bit_index;
    reg [19:0] tx_code;
    reg [51:0] map_product;
    reg [63:0] gain_product;
    reg signed [65:0] adjusted;
    wire hit=cfg_addr[31:8]==BASE_ADDR[31:8];
    wire [7:0] ofs=cfg_addr[7:0];
    wire [31:0] mask={{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    wire [31:0] merged=(cfg_rdata & ~mask)|(cfg_wdata & mask);
    wire control=hit && cfg_write && ofs==`REG_OFS_CONTROL;
    wire commit_req=control && cfg_wstrb[0] && cfg_wdata[2];
    // Validation belongs to the held request, until its ready handshake.
    wire cancel_calc=calc!=0 && (!cfg_valid || !commit_req);
    reg known,writable;
    assign cfg_ready=cfg_valid && hit && (!commit_req || calc==7 || stream_active || state!=ST_IDLE);
    wire access=cfg_valid && cfg_ready;
    wire soft_reset=access && !cfg_error && control && cfg_wstrb[0] && cfg_wdata[1];
    wire clear_req=access && !cfg_error && control && cfg_wstrb[0] && cfg_wdata[4];
    wire commit_apply=access && !cfg_error && commit_req && calc==7;
    assign operational=enable && ctl_enable && initialized && calc==0;
    assign dac_sample_ready=operational && state==ST_IDLE && !commit_req && !clear_req && !soft_reset;
    assign max_update_hz=a_cap;
    assign dac_ldac_n=1'b0;
    wms_unsigned_divider divider(.clk(sys_clk),.rst_n(rst_sys_n && !soft_reset && !cancel_calc),.start(div_start),
        .numerator(div_num),.denominator(div_den),.busy(div_busy),.done(div_done),.quotient(div_q),.remainder(div_rem));
    always @* begin
        cfg_rdata=0;known=1;writable=0;
        case(ofs)
            `REG_OFS_ID_VERSION:cfg_rdata={MODULE_ID,8'd1,8'd3};
            `REG_OFS_CONTROL:begin cfg_rdata={31'd0,ctl_enable};writable=1;end
            `REG_OFS_STATUS:begin
                cfg_rdata[0]=ctl_enable;cfg_rdata[1]=initialized;cfg_rdata[2]=calc!=0;
                cfg_rdata[3]=state!=ST_IDLE;cfg_rdata[4]=initialized;cfg_rdata[7]=|error_bits;cfg_rdata[8]=time_sync_valid;
            end
            `REG_OFS_ERROR:begin cfg_rdata=error_bits;writable=1;end
            `REG_DAC_DEVICE_CTRL:begin cfg_rdata=sh_ctrl;writable=1;end
            `REG_DAC_CLEAR_CODE:begin cfg_rdata=sh_clear;writable=1;end
            `REG_DAC_MIN_CODE:begin cfg_rdata=sh_min;writable=1;end
            `REG_DAC_MAX_CODE:begin cfg_rdata=sh_max;writable=1;end
            `REG_DAC_LAST_CODE:cfg_rdata=last_code;
            `REG_DAC_SPI_CLK_HZ:begin cfg_rdata=sh_spi;writable=1;end
            `REG_DAC_WRITE_COUNT:cfg_rdata=write_count;
            `REG_DAC_SPI_ERROR_COUNT:cfg_rdata=0;
            `REG_DAC_DEVICE_ID_RAW:cfg_rdata=0;
            8'h34:begin cfg_rdata=sh_gain;writable=1;end
            8'h38:begin cfg_rdata=sh_offset;writable=1;end
            8'h3c:cfg_rdata=a_spi;
            8'h40:cfg_rdata=a_cap;
            8'h44:begin cfg_rdata=clamp_count;writable=1;end
            default:known=0;
        endcase
        cfg_error=0;
        if(cfg_valid && hit)begin
            cfg_error=!known || |cfg_addr[1:0] || (cfg_write && !writable);
            if(control && |(cfg_wdata & mask & 32'hffffffe0))cfg_error=1;
            if(control && cfg_wstrb[0] && cfg_wdata[4] && (state!=ST_IDLE || stream_active))cfg_error=1;
            if(commit_req && (stream_active || state!=ST_IDLE || (calc==7 && calc_error)))cfg_error=1;
        end
    end
    always @*begin
        cfg_error_code=0;
        if(cfg_valid && hit && cfg_error)begin
            if(!known || |cfg_addr[1:0])cfg_error_code=5;
            else if(cfg_write && !writable)cfg_error_code=6;
            else if(control && |(cfg_wdata & mask & 32'hffffffe0))cfg_error_code=7;
            else if((control && cfg_wstrb[0] && cfg_wdata[4] && (state!=ST_IDLE || stream_active)) ||
                    (commit_req && (stream_active || state!=ST_IDLE)))cfg_error_code=8;
            else cfg_error_code=7;
        end
    end
    task launch;
        input [23:0] frame;
        input sample_frame;
        begin
            shift<=frame;dac_sdin<=frame[23];dac_sync_n<=0;dac_sclk<=1;
            count<=a_half-1'b1;bit_index<=23;state<=ST_LOW;is_sample<=sample_frame;
        end
    endtask
    always @(posedge sys_clk)begin
        if(!rst_sys_n || soft_reset)begin
            ctl_enable<=0;sh_ctrl<=32'h312;sh_clear<=32'h80000;sh_min<=0;sh_max<=32'hfffff;
            sh_spi<=MAX_SPI_REQUEST_HZ;sh_gain<=32'h40000000;sh_offset<=0;
            a_ctrl<=32'h312;a_clear<=32'h80000;a_min<=0;a_max<=32'hfffff;
            a_gain<=32'h40000000;a_offset<=0;a_half<=DEFAULT_HALF;
            a_spi<=SYS_CLK_HZ/(2*DEFAULT_HALF);a_cap<=SYS_CLK_HZ/(48*DEFAULT_HALF+20);
            p_ctrl<=0;p_clear<=0;p_min<=0;p_max<=0;p_gain<=0;p_offset<=0;p_spi<=0;p_half<=0;p_actual<=0;
            last_code<=0;write_count<=0;error_bits<=0;clamp_count<=0;
            calc<=0;calc_error<=0;div_start<=0;div_num<=0;div_den<=1;
            state<=ST_RESET;count<=RESET_TICKS-1;init_index<=0;initialized<=0;is_sample<=0;
            shift<=0;bit_index<=0;tx_code<=0;map_product<=0;gain_product<=0;adjusted<=0;
            dac_sclk<=1;dac_sync_n<=1;dac_sdin<=0;dac_rst_n<=0;dac_clr_n<=1;
        end else begin
            div_start<=0;
            if(access)begin
                if(cfg_error)error_bits<=error_bits|`ERR_CONFIG_RANGE;
                else if(cfg_write)case(ofs)
                    `REG_OFS_CONTROL:if(cfg_wstrb[0])ctl_enable<=cfg_wdata[0];
                    `REG_OFS_ERROR:error_bits<=error_bits & ~(cfg_wdata & mask);
                    `REG_DAC_DEVICE_CTRL:sh_ctrl<=merged;
                    `REG_DAC_CLEAR_CODE:sh_clear<=merged;
                    `REG_DAC_MIN_CODE:sh_min<=merged;
                    `REG_DAC_MAX_CODE:sh_max<=merged;
                    `REG_DAC_SPI_CLK_HZ:sh_spi<=merged;
                    8'h34:sh_gain<=merged;
                    8'h38:sh_offset<=merged;
                    8'h44:clamp_count<=clamp_count & ~(cfg_wdata & mask);
                    default:begin end
                endcase
            end
            if(calc==0 && cfg_valid && commit_req && !stream_active && state==ST_IDLE)begin
                p_ctrl<=sh_ctrl;p_clear<=sh_clear;p_min<=sh_min;p_max<=sh_max;
                p_gain<=sh_gain;p_offset<=sh_offset;p_spi<=sh_spi;
                calc_error<=sh_spi==0 || sh_spi>MAX_SPI_REQUEST_HZ || sh_min>sh_max || |sh_min[31:20] ||
                    |sh_max[31:20] || |sh_clear[31:20] || sh_clear<sh_min || sh_clear>sh_max ||
                    |(sh_ctrl & 32'hfffffc01) || !sh_ctrl[4] || !sh_ctrl[1] ||
                    (sh_ctrl[9:6]!=0 && sh_ctrl[9:6]!=9 && sh_ctrl[9:6]!=10 && sh_ctrl[9:6]!=11 && sh_ctrl[9:6]!=12);
                if(sh_spi==0 || sh_spi>MAX_SPI_REQUEST_HZ)calc<=7;
                else begin div_num<=SYS_CLK_HZ;div_den<={63'd0,sh_spi,1'b0};div_start<=1;calc<=1;end
            end
            if(cancel_calc)begin calc<=0;calc_error<=0;div_start<=0;end
            else case(calc)
                1:if(div_done)begin p_half<=div_q[31:0]+(|div_rem);calc<=2;end
                2:begin div_num<=SYS_CLK_HZ;div_den<={63'd0,p_half,1'b0};div_start<=1;calc<=3;end
                3:if(div_done)begin p_actual<=div_q[31:0];calc<=4;end
                4:begin div_num<=SYS_CLK_HZ;div_den<=p_half*96'd48+96'd20;div_start<=1;calc<=5;end
                5:if(div_done)begin calc<=7;end
                7:if(access)begin calc<=0;end
                default:begin end
            endcase
            if(commit_apply)begin
                a_ctrl<=p_ctrl;a_clear<=p_clear;a_min<=p_min;a_max<=p_max;a_gain<=p_gain;a_offset<=p_offset;
                a_half<=p_half;a_spi<=p_actual;a_cap<=div_q[31:0];
                initialized<=0;init_index<=0;state<=ST_INIT;
            end else if(clear_req)begin dac_clr_n<=0;state<=ST_CLEAR;count<=CLEAR_TICKS-1;end
            else case(state)
                ST_RESET:if(count==0)begin dac_rst_n<=1;count<=RESET_TICKS-1;state<=ST_SETTLE;end else count<=count-1'b1;
                ST_SETTLE:if(count==0)state<=ST_INIT;else count<=count-1'b1;
                ST_INIT:case(init_index)
                    0:launch({4'h2,a_ctrl[19:0]|20'h0000c},0);
                    1:launch({4'h3,a_clear[19:0]},0);
                    2:launch({4'h1,a_clear[19:0]},0);
                    3:launch({4'h2,a_ctrl[19:0]},0);
                    default:begin initialized<=1;state<=ST_IDLE;end
                endcase
                ST_IDLE:if(dac_sample_valid && dac_sample_ready)begin
                    map_product<=(dac_sample^32'h80000000)*20'hfffff;state<=ST_MAP1;
                end
                ST_MAP1:begin gain_product<=((map_product+52'd2147483648)>>32)*a_gain;state<=ST_MAP2;end
                ST_MAP2:begin adjusted<=$signed({2'b0,(gain_product+64'd536870912)>>30})+$signed({{34{a_offset[31]}},a_offset});state<=ST_MAP3;end
                ST_MAP3:begin
                    if(adjusted<$signed({34'd0,a_min}))begin tx_code<=a_min[19:0];launch({4'h1,a_min[19:0]},1);clamp_count<=clamp_count+1'b1;end
                    else if(adjusted>$signed({34'd0,a_max}))begin tx_code<=a_max[19:0];launch({4'h1,a_max[19:0]},1);clamp_count<=clamp_count+1'b1;end
                    else begin tx_code<=adjusted[19:0];launch({4'h1,adjusted[19:0]},1);end
                end
                ST_LOW:if(count==0)begin dac_sclk<=0;count<=a_half-1'b1;state<=ST_HIGH;end else count<=count-1'b1;
                ST_HIGH:if(count==0)begin
                    dac_sclk<=1;
                    if(bit_index==0)state<=ST_END;
                    else begin bit_index<=bit_index-1'b1;shift<={shift[22:0],1'b0};dac_sdin<=shift[22];count<=a_half-1'b1;state<=ST_LOW;end
                end else count<=count-1'b1;
                ST_END:begin
                    dac_sync_n<=1;count<=GUARD_TICKS-1;state<=ST_GUARD;
                    if(is_sample)begin last_code<={12'd0,tx_code};write_count<=write_count+1'b1;end
                    else if(init_index==2)last_code<=a_clear;
                end
                ST_GUARD:if(count==0)begin
                    if(initialized)state<=ST_IDLE;else begin init_index<=init_index+1'b1;state<=ST_INIT;end
                end else count<=count-1'b1;
                ST_CLEAR:if(count==0)begin dac_clr_n<=1;last_code<=a_clear;state<=ST_IDLE;end else count<=count-1'b1;
                default:state<=ST_RESET;
            endcase
        end
    end
endmodule
`default_nettype wire
