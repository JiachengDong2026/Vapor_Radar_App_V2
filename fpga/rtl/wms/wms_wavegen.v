`include "project_defs.vh"
`include "register_map.vh"
`include "error_codes.vh"
`default_nettype none
module wms_wavegen #(
    parameter integer SYS_CLK_HZ=`SYS_CLK_HZ,
    parameter [31:0] BASE_ADDR=`REG_BASE_WMS0,
    parameter [15:0] MODULE_ID=`SRC_WMS0
)(
    input wire sys_clk,input wire rst_sys_n,input wire enable,
    input wire [63:0] timestamp_now,input wire time_sync_valid,
    input wire transport_ready,input wire [31:0] max_update_hz,
    input wire cfg_valid,input wire cfg_write,input wire [31:0] cfg_addr,
    input wire [31:0] cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg [31:0] cfg_rdata,output reg cfg_error,
    output reg [31:0] dac_sample,output reg dac_sample_valid,input wire dac_sample_ready,
    output reg scan_start,output reg [31:0] cycle_id,output reg [31:0] sine_phase,
    output wire wms_running,output reg phase_valid,output reg config_changed,
    output reg [3:0] cfg_error_code
);
    localparam [7:0] REG_OVERRUN=8'h44,REG_PERIOD=8'h48;
    reg ctl_enable,configured,fault,pending;
    reg [31:0] error_bits,sat_count,overrun_count;
    reg [63:0] last_scan;
    reg [31:0] sh_saw_freq,sh_saw_ampl,sh_offset,sh_sine_freq,sh_sine_ampl,sh_phase,sh_rate,sh_mode;
    reg [31:0] p_saw_freq,p_saw_ampl,p_offset,p_sine_freq,p_sine_ampl,p_phase,p_rate,p_mode;
    reg [31:0] p_period,p_actual,p_saw_inc,p_sine_inc;
    reg [31:0] a_saw_ampl,a_offset,a_sine_ampl,a_phase,a_mode,a_period,a_actual,a_saw_inc,a_sine_inc;
    reg [31:0] saw_phase,sin_acc,timer;
    reg first_sample;
    reg [2:0] pipe;
    reg signed [31:0] saw_term,pipe_offset,pipe_saw_ampl,pipe_sine_ampl;
    reg signed [63:0] saw_product,sine_product;
    reg signed [65:0] sum;
    wire signed [31:0] sine_value;
    wire [31:0] lut_phase=sin_acc+a_phase;
    sine_lut lut(.clk(sys_clk),.phase(lut_phase),.sin_value(sine_value));
    wire run=enable && ctl_enable && configured && !fault && transport_ready;
    assign wms_running=run;
    wire [32:0] saw_advance={1'b0,saw_phase}+{1'b0,a_saw_inc};
    wire hit=cfg_addr[31:8]==BASE_ADDR[31:8];
    wire [7:0] ofs=cfg_addr[7:0];
    reg known,writable;
    wire [31:0] mask={{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    wire [31:0] merged=(cfg_rdata & ~mask)|(cfg_wdata & mask);
    wire control=hit && ofs==`REG_OFS_CONTROL && cfg_write;
    wire commit_req=control && cfg_wstrb[0] && cfg_wdata[`CTRL_BIT_COMMIT];
    reg [3:0] calc;
    reg calc_error;
    reg div_start;
    reg [95:0] div_num,div_den;
    wire div_busy,div_done;
    wire [95:0] div_q,div_rem;
    reg [63:0] freq_period;
    // An unacknowledged snapshot must not survive request withdrawal.
    wire cancel_calc=calc!=0 && (!cfg_valid || !commit_req);
    wms_unsigned_divider divider(.clk(sys_clk),.rst_n(rst_sys_n && !soft_reset && !cancel_calc),.start(div_start),
        .numerator(div_num),.denominator(div_den),.busy(div_busy),.done(div_done),.quotient(div_q),.remainder(div_rem));
    assign cfg_ready=cfg_valid && hit && (!commit_req || pending || calc==9);
    wire access=cfg_valid && cfg_ready;
    wire soft_reset=access && !cfg_error && control && cfg_wstrb[0] && cfg_wdata[`CTRL_BIT_SOFT_RESET];
    always @* begin
        cfg_rdata=0; known=1; writable=0;
        case(ofs)
            `REG_OFS_ID_VERSION:cfg_rdata={MODULE_ID,8'd1,8'd3};
            `REG_OFS_CONTROL:begin cfg_rdata={31'd0,ctl_enable};writable=1;end
            `REG_OFS_STATUS:begin
                cfg_rdata[`STATUS_BIT_ENABLED]=ctl_enable;
                cfg_rdata[`STATUS_BIT_READY]=configured && transport_ready;
                cfg_rdata[`STATUS_BIT_CFG_PENDING]=pending || calc!=0;
                cfg_rdata[`STATUS_BIT_BUSY]=run;
                cfg_rdata[`STATUS_BIT_ONLINE]=transport_ready;
                cfg_rdata[`STATUS_BIT_OVERFLOW]=error_bits[8];
                cfg_rdata[`STATUS_BIT_ERROR]=|error_bits;
                cfg_rdata[`STATUS_BIT_TIME_SYNC]=time_sync_valid;
            end
            `REG_OFS_ERROR:begin cfg_rdata=error_bits;writable=1;end
            `REG_WMS_SAW_FREQ_MHZ:begin cfg_rdata=sh_saw_freq;writable=1;end
            `REG_WMS_SAW_AMPL_Q31:begin cfg_rdata=sh_saw_ampl;writable=1;end
            `REG_WMS_SAW_OFFSET_Q31:begin cfg_rdata=sh_offset;writable=1;end
            `REG_WMS_SINE_FREQ_MHZ:begin cfg_rdata=sh_sine_freq;writable=1;end
            `REG_WMS_SINE_AMPL_Q31:begin cfg_rdata=sh_sine_ampl;writable=1;end
            `REG_WMS_SINE_PHASE_U32:begin cfg_rdata=sh_phase;writable=1;end
            `REG_WMS_DAC_UPDATE_HZ_REQ:begin cfg_rdata=sh_rate;writable=1;end
            `REG_WMS_DAC_UPDATE_HZ_ACT:cfg_rdata=a_actual;
            `REG_WMS_CYCLE_ID:cfg_rdata=cycle_id;
            `REG_WMS_LAST_SCAN_TICK_LO:cfg_rdata=last_scan[31:0];
            `REG_WMS_LAST_SCAN_TICK_HI:cfg_rdata=last_scan[63:32];
            `REG_WMS_SAT_COUNT:begin cfg_rdata=sat_count;writable=1;end
            `REG_WMS_PHASE_MODE:begin cfg_rdata=sh_mode;writable=1;end
            REG_OVERRUN:begin cfg_rdata=overrun_count;writable=1;end
            REG_PERIOD:cfg_rdata=a_period;
            default:known=0;
        endcase
        cfg_error=0;cfg_error_code=0;
        if (cfg_valid && hit) begin
            cfg_error=!known || |cfg_addr[1:0] || (cfg_write && !writable);
            if(cfg_write && ofs==`REG_OFS_CONTROL && |(cfg_wdata & mask & 32'hfffffff0))cfg_error=1;
            if(cfg_write && ofs==`REG_WMS_PHASE_MODE && |merged[31:2])cfg_error=1;
            if(commit_req && (pending || (calc==9 && calc_error)))cfg_error=1;
            if(cfg_error)begin
                if(!known || |cfg_addr[1:0])cfg_error_code=5;
                else if(cfg_write && !writable)cfg_error_code=6;
                else if(commit_req && pending && !(|(cfg_wdata & mask & 32'hfffffff0)))cfg_error_code=8;
                else cfg_error_code=7;
            end
        end
    end
    function signed [64:0] round_q31;
        input signed [63:0] v;
        reg signed [64:0] ext;
        begin ext={v[63],v}+65'sd1073741824;round_q31=ext>>>31;end
    endfunction
    always @(posedge sys_clk) begin
        if(!rst_sys_n || soft_reset) begin
            ctl_enable<=0;configured<=0;fault<=0;pending<=0;error_bits<=0;
            sat_count<=0;overrun_count<=0;last_scan<=0;cycle_id<=0;
            sh_saw_freq<=100000;sh_saw_ampl<=32'h20000000;sh_offset<=0;
            sh_sine_freq<=1000000;sh_sine_ampl<=32'h10000000;sh_phase<=0;sh_rate<=100000;sh_mode<=1;
            p_saw_freq<=0;p_saw_ampl<=0;p_offset<=0;p_sine_freq<=0;p_sine_ampl<=0;p_phase<=0;p_rate<=0;p_mode<=0;
            p_period<=1000;p_actual<=0;p_saw_inc<=0;p_sine_inc<=0;
            a_saw_ampl<=0;a_offset<=0;a_sine_ampl<=0;a_phase<=0;a_mode<=1;a_period<=1000;a_actual<=0;a_saw_inc<=0;a_sine_inc<=0;
            saw_phase<=0;sin_acc<=0;timer<=0;first_sample<=1;
            pipe<=0;saw_term<=0;pipe_offset<=0;pipe_saw_ampl<=0;pipe_sine_ampl<=0;
            saw_product<=0;sine_product<=0;sum<=0;dac_sample<=0;dac_sample_valid<=0;
            scan_start<=0;sine_phase<=0;phase_valid<=0;config_changed<=0;
            calc<=0;calc_error<=0;div_start<=0;div_num<=0;div_den<=1;freq_period<=0;
        end else begin
            scan_start<=0;config_changed<=0;div_start<=0;
            if(dac_sample_valid && dac_sample_ready)dac_sample_valid<=0;
            if(access) begin
                if(cfg_error)error_bits<=error_bits|`ERR_CONFIG_RANGE;
                else if(cfg_write)case(ofs)
                    `REG_OFS_CONTROL:begin
                        if(cfg_wstrb[0])begin ctl_enable<=cfg_wdata[0];if(!cfg_wdata[0])fault<=0;end
                    end
                    `REG_OFS_ERROR:error_bits<=error_bits & ~(cfg_wdata & mask);
                    `REG_WMS_SAW_FREQ_MHZ:sh_saw_freq<=merged;
                    `REG_WMS_SAW_AMPL_Q31:sh_saw_ampl<=merged;
                    `REG_WMS_SAW_OFFSET_Q31:sh_offset<=merged;
                    `REG_WMS_SINE_FREQ_MHZ:sh_sine_freq<=merged;
                    `REG_WMS_SINE_AMPL_Q31:sh_sine_ampl<=merged;
                    `REG_WMS_SINE_PHASE_U32:sh_phase<=merged;
                    `REG_WMS_DAC_UPDATE_HZ_REQ:sh_rate<=merged;
                    `REG_WMS_PHASE_MODE:sh_mode<=merged;
                    `REG_WMS_SAT_COUNT:sat_count<=sat_count & ~(cfg_wdata & mask);
                    REG_OVERRUN:overrun_count<=overrun_count & ~(cfg_wdata & mask);
                    default:begin end
                endcase
            end
            // The whole request is captured once; shadow writes cannot alter pending data.
            if(calc==0 && cfg_valid && commit_req && !pending)begin
                p_saw_freq<=sh_saw_freq;p_saw_ampl<=sh_saw_ampl;p_offset<=sh_offset;
                p_sine_freq<=sh_sine_freq;p_sine_ampl<=sh_sine_ampl;p_phase<=sh_phase;p_rate<=sh_rate;p_mode<=sh_mode;
                calc_error<=sh_rate==0 || sh_rate>max_update_hz || sh_saw_freq==0;
                if(sh_rate==0 || sh_rate>max_update_hz || sh_saw_freq==0)calc<=9;
                else begin div_num<=SYS_CLK_HZ;div_den<=sh_rate;div_start<=1;calc<=1;end
            end
            if(cancel_calc)begin calc<=0;calc_error<=0;div_start<=0;end
            else case(calc)
                1:if(div_done)begin p_period<=div_q[31:0]+(|div_rem);calc<=2;end
                2:begin div_num<=SYS_CLK_HZ;div_den<=p_period;div_start<=1;calc<=3;end
                3:if(div_done)begin p_actual<=div_q[31:0];freq_period<={32'd0,p_saw_freq}*p_period;calc<=4;end
                4:begin
                    div_num<={freq_period,32'd0}+SYS_CLK_HZ*96'd500;
                    div_den<=SYS_CLK_HZ*96'd1000;div_start<=1;calc<=5;
                    if(freq_period*2>SYS_CLK_HZ*64'd1000)calc_error<=1;
                end
                5:if(div_done)begin p_saw_inc<=div_q[31:0];if(div_q==0)calc_error<=1;freq_period<={32'd0,p_sine_freq}*p_period;calc<=6;end
                6:begin
                    div_num<={freq_period,32'd0}+SYS_CLK_HZ*96'd500;
                    div_den<=SYS_CLK_HZ*96'd1000;div_start<=1;calc<=7;
                    if(freq_period*2>SYS_CLK_HZ*64'd1000)calc_error<=1;
                end
                7:if(div_done)begin p_sine_inc<=div_q[31:0];calc<=9;end
                9:if(access && commit_req)begin calc<=0;if(!cfg_error)pending<=1;end
                default:begin end
            endcase
            if(!run)begin timer<=0;first_sample<=1;phase_valid<=0;end
            // Copy on the old scan's wrap boundary, then launch the new scan next clock.
            if(pending && pipe==0 && (!dac_sample_valid || dac_sample_ready) &&
               (!run || (timer==0 && !first_sample && saw_advance[32])))begin
                a_saw_ampl<=p_saw_ampl;a_offset<=p_offset;a_sine_ampl<=p_sine_ampl;
                a_phase<=p_phase;a_mode<=p_mode;a_period<=p_period;a_actual<=p_actual;
                a_saw_inc<=p_saw_inc;a_sine_inc<=p_sine_inc;
                saw_phase<=0;if(p_mode[1] || !p_mode[0])sin_acc<=0;
                pending<=0;configured<=1;config_changed<=1;first_sample<=1;timer<=0;
            end else if(run)begin
                if(timer!=0)timer<=timer-1'b1;
                else begin
                    timer<=a_period-1'b1;
                    if((dac_sample_valid && !dac_sample_ready) || pipe!=0)begin
                        error_bits<=error_bits|32'h00000100;overrun_count<=overrun_count+1'b1;fault<=1;phase_valid<=0;
                    end else begin
                        pipe<=1;
                        phase_valid<=1;
                        if(first_sample)begin
                            saw_term<=32'h80000000;saw_phase<=0;
                            if(!a_mode[0])sin_acc<=0;
                            sine_phase<=(a_mode[0] ? sin_acc : 32'd0)+a_phase;
                            first_sample<=0;scan_start<=1;cycle_id<=cycle_id+1'b1;last_scan<=timestamp_now;
                        end else begin
                            saw_phase<=saw_advance[31:0];saw_term<=saw_advance[31:0]^32'h80000000;
                            sin_acc<=sin_acc+a_sine_inc;
                            sine_phase<=sin_acc+a_sine_inc+a_phase;
                            if(saw_advance[32])begin scan_start<=1;cycle_id<=cycle_id+1'b1;last_scan<=timestamp_now;end
                        end
                        pipe_offset<=a_offset;pipe_saw_ampl<=a_saw_ampl;pipe_sine_ampl<=a_sine_ampl;
                    end
                end
            end
            // Reference phase and scan_start are aligned on the scheduling tick.
            if(pipe==1)begin pipe<=2;end
            if(pipe==2)begin saw_product<=saw_term*pipe_saw_ampl;sine_product<=sine_value*pipe_sine_ampl;pipe<=3;end
            if(pipe==3)begin sum<=round_q31(saw_product)+round_q31(sine_product)+$signed({{34{pipe_offset[31]}},pipe_offset});pipe<=4;end
            if(pipe==4)begin
                pipe<=0;dac_sample_valid<=1;
                if(sum>66'sd2147483647)begin dac_sample<=32'h7fffffff;sat_count<=sat_count+1'b1;end
                else if(sum< -66'sd2147483648)begin dac_sample<=32'h80000000;sat_count<=sat_count+1'b1;end
                else dac_sample<=sum[31:0];
            end
        end
    end
endmodule
`default_nettype wire
