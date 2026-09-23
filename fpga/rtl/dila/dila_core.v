`timescale 1ns/1ps
`include "project_defs.vh"
module dila_core #(
    parameter integer SYS_CLK_HZ=100000000,
    parameter integer INPUT_RATE_HZ=1000000,
    parameter integer USE_CAPTURE_TAGS=0,
    parameter integer OUTPUT_FORMAT=0,
    parameter integer MAX_POINTS=4096,
    parameter [15:0] SOURCE_ID=16'h0030,
    parameter [31:0] BASE_ADDR=32'h5000
)(
    input wire sys_clk,input wire rst_sys_n,
    input wire sample_valid,output wire sample_ready,input wire [31:0] sample_data,input wire [7:0] sample_flags,
    input wire wms_scan_start,input wire [31:0] wms_cycle_id,input wire [31:0] wms_sine_phase,input wire wms_phase_valid,
    input wire [63:0] timestamp_now,input wire time_sync_valid,
    input wire [193:0] capture_tag,input wire [31:0] input_sample_rate_hz,
    input wire [31:0] expected_per_cycle,input wire input_overflow_pulse,
    input wire cfg_valid,input wire cfg_write,input wire [31:0] cfg_addr,input wire [31:0] cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg [31:0] cfg_rdata,output reg cfg_error,
    output wire m_valid,input wire m_ready,output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,output wire m_last,output wire [15:0] m_source_id,output wire [15:0] m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,output wire [31:0] m_flags,
    output wire [31:0] output_queue_level,output wire datapath_idle,
    output reg [3:0] cfg_error_code
);
    reg enable,pending,prepared,div_start,phase_start;
    reg [1:0] calc_state;
    reg [31:0] frequency_shadow,phase1_shadow,phase2_shadow,rate_shadow,mode_shadow,frag_shadow;
    reg [31:0] frequency_commit,phase1_commit,phase2_commit,rate_commit,mode_commit,frag_commit,input_rate_commit;
    reg [31:0] phase1_active,phase2_active,mode_active,frag_active,decimation,rate_actual,phase_step;
    reg [31:0] factor_next,rate_next,phase_next,div_num,div_den;
    reg [31:0] error_status,in_sat_count,mix_sat_count,lpf_sat_count,out_count;
    reg [31:0] last_input_cycle,input_count,last_filter_cycle,decim_count;
    reg have_input_cycle,have_filter_cycle,cycle_partial;
    reg [63:0] cycle_timestamp;
    reg [31:0] live_cycle;
    reg [9:0] flush_timer;
    reg flush_pending,drain_pending,wms_valid_prev;
    reg [31:0] flush_cycle;
    reg [2:0] cooldown;
    wire hit=cfg_valid && cfg_addr[31:8]==BASE_ADDR[31:8];
    wire [7:0] ofs=cfg_addr[7:0];
    wire [31:0] mask={{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    wire [31:0] wd=cfg_wdata&mask;
    wire wr=hit && cfg_write && !cfg_error;
    wire soft_reset=wr && ofs==4 && wd[1];
    wire clear_fifo=soft_reset || (wr && ofs==4 && wd[3]);
    wire local_rst_n=rst_sys_n && !clear_fifo;
    wire [31:0] input_rate=USE_CAPTURE_TAGS?input_sample_rate_hz:INPUT_RATE_HZ;
    reg [31:0] merged;
    wire [31:0] frame_level,frame_drops,frame_fragments;
    wire div_done,div_busy,phase_done,phase_busy;
    wire [31:0] div_result;
    wire [63:0] phase_result;
    member1_divider u_rate(.clk(sys_clk),.rst_n(local_rst_n),.start(div_start),.numerator(div_num),.denominator(div_den),
        .busy(div_busy),.done(div_done),.quotient(div_result));
    member1_divider64 u_phase(.clk(sys_clk),.rst_n(local_rst_n),.start(phase_start),
        .numerator({frequency_commit,32'd0} + SYS_CLK_HZ*64'd500),.denominator(SYS_CLK_HZ*64'd1000),
        .busy(phase_busy),.done(phase_done),.quotient(phase_result));
    assign cfg_ready=hit;
    always @*begin
        cfg_rdata=0;cfg_error=0;merged=0;
        if(hit)case(ofs)
            8'h00:begin cfg_rdata={SOURCE_ID,16'h0100};cfg_error=cfg_write;end
            8'h04:begin cfg_rdata={31'd0,enable};if(cfg_write && ((wd[2] && pending) || |wd[31:4]))cfg_error=1;end
            8'h08:begin cfg_rdata={23'd0,time_sync_valid,|error_status,error_status[2],frame_level>=MAX_POINTS,enable,1'b0,pending,1'b1,enable};cfg_error=cfg_write;end
            8'h0c:cfg_rdata=error_status;
            8'h10:begin cfg_rdata=frequency_shadow;merged=(frequency_shadow&~mask)|wd;if(cfg_write && (merged==0 || merged>1000000000))cfg_error=1;end
            8'h14:cfg_rdata=phase1_shadow;
            8'h18:cfg_rdata=phase2_shadow;
            8'h1c:begin cfg_rdata=rate_shadow;merged=(rate_shadow&~mask)|wd;if(cfg_write && (merged==0 || merged>(input_rate>>3)))cfg_error=1;end
            8'h20:begin cfg_rdata=mode_shadow;merged=(mode_shadow&~mask)|wd;if(cfg_write && (|merged[31:3] || (OUTPUT_FORMAT!=1 && !merged[1])))cfg_error=1;end
            8'h24:begin cfg_rdata=INPUT_RATE_HZ==12500000?32'h00020102:32'h00020101;cfg_error=cfg_write;end
            8'h28:begin cfg_rdata=32'h20112e10;cfg_error=cfg_write;end
            8'h2c:cfg_rdata=in_sat_count;
            8'h30:cfg_rdata=mix_sat_count;
            8'h34:cfg_rdata=lpf_sat_count;
            8'h38:begin cfg_rdata=out_count;cfg_error=cfg_write;end
            8'h3c:begin cfg_rdata=frame_level;cfg_error=cfg_write;end
            8'h40:begin cfg_rdata=frag_shadow;merged=(frag_shadow&~mask)|wd;if(cfg_write && (merged<1 || merged>256))cfg_error=1;end
            8'h44:begin cfg_rdata=frame_fragments;cfg_error=cfg_write;end
            8'h48:begin cfg_rdata=frame_drops;cfg_error=cfg_write;end
            8'h4c:begin cfg_rdata=rate_actual;cfg_error=cfg_write;end
            8'h50:begin cfg_rdata=decimation;cfg_error=cfg_write;end
            8'h54:begin cfg_rdata=phase_step;cfg_error=cfg_write;end
            default:cfg_error=1;
        endcase
    end
    wire [193:0] sample_tag=USE_CAPTURE_TAGS?capture_tag:
        {time_sync_valid,wms_phase_valid,wms_scan_start?timestamp_now:cycle_timestamp,
         timestamp_now,wms_sine_phase,wms_scan_start?wms_cycle_id:live_cycle};
    wire input_new_cycle=!have_input_cycle || sample_tag[31:0]!=last_input_cycle;
    wire config_boundary_request=pending && prepared && (!enable || (sample_valid && input_new_cycle));
    wire config_pipeline_idle;
    wire apply_config=config_boundary_request && config_pipeline_idle;
    assign sample_ready=(enable || drain_pending) && cooldown==0 && !config_boundary_request;
    wire sample_fire=sample_valid && sample_ready;
    reg ref_valid;
    reg [193:0] ref_tag;
    reg signed [31:0] ref_sample;
    reg [31:0] ref_phase;
    wire signed [17:0] sin1,cos1,sin2,cos2;
    dila_ref_gen u_ref(.phase(ref_phase),.phase_1f(phase1_active),.phase_2f_correction(phase2_active),
        .sin_1f(sin1),.cos_1f(cos1),.sin_2f(sin2),.cos_2f(cos2));
    wire mix_valid,mix_sat;
    wire [127:0] mix_iq;
    wire [193:0] mix_tag;
    dila_mixer u_mix(.clk(sys_clk),.rst_n(local_rst_n),.in_valid(ref_valid),.sample(ref_sample),
        .cos_1f(cos1),.sin_1f(sin1),.cos_2f(cos2),.sin_2f(sin2),.in_tag(ref_tag),
        .out_valid(mix_valid),.out_iq(mix_iq),.out_tag(mix_tag),.saturation(mix_sat));
    localparam signed [47:0] B0=INPUT_RATE_HZ==12500000?48'sd4443295:48'sd691437427;
    localparam signed [47:0] B1=INPUT_RATE_HZ==12500000?48'sd8886591:48'sd1382874854;
    localparam signed [47:0] B2=B0;
    localparam signed [47:0] A1=INPUT_RATE_HZ==12500000?-48'sd140687465942571:-48'sd140112212256429;
    localparam signed [47:0] A2=INPUT_RATE_HZ==12500000?48'sd70318739538089:48'sd69746233828473;
    wire filtered_valid,filter_sat,filter_busy;
    wire [127:0] filtered_iq;
    wire [193:0] filtered_tag;
    dila_lpf #(.B0(B0),.B1(B1),.B2(B2),.A1(A1),.A2(A2)) u_filter(
        .clk(sys_clk),.rst_n(local_rst_n),.clear(1'b0),.in_valid(mix_valid),.in_iq(mix_iq),.in_tag(mix_tag),
        .bypass(mode_active[2]),.out_valid(filtered_valid),.out_iq(filtered_iq),.out_tag(filtered_tag),.saturation(filter_sat),.busy(filter_busy));
    wire filter_new_cycle=!have_filter_cycle || filtered_tag[31:0]!=last_filter_cycle;
    wire point_due=filtered_valid && ((filter_new_cycle?32'd1:decim_count+1'b1)>=decimation);
    wire magnitude_busy,mag_valid,point_valid;
    wire [191:0] mag_data;
    wire [193:0] mag_tag;
    reg direct_valid;
    reg [127:0] direct_iq;
    reg [193:0] direct_tag;
    always @(posedge sys_clk or negedge local_rst_n)begin
        if(!local_rst_n)begin direct_valid<=0;direct_iq<=0;direct_tag<=0;end
        else begin direct_valid<=point_due && !mode_active[1];direct_iq<=filtered_iq;direct_tag<=filtered_tag;end
    end
    always @*begin
        cfg_error_code=0;
        if(hit && cfg_error)case(ofs)
            8'h00,8'h08,8'h24,8'h28,8'h38,8'h3c,8'h44,8'h48,8'h4c,8'h50,8'h54:cfg_error_code=6;
            8'h04:cfg_error_code=(|wd[31:4])?7:8;
            8'h10,8'h1c,8'h20,8'h40:cfg_error_code=7;
            default:cfg_error_code=5;
        endcase
    end
    wire [191:0] point_data=mode_active[1]?mag_data:{64'd0,direct_iq};
    wire [193:0] point_tag=mode_active[1]?mag_tag:direct_tag;
    assign point_valid=mode_active[1]?mag_valid:direct_valid;
    assign config_pipeline_idle=!ref_valid && !mix_valid && !filter_busy && !filtered_valid && !magnitude_busy && !mag_valid && !direct_valid;
    assign output_queue_level=frame_level;
    assign datapath_idle=!enable && !sample_valid && config_pipeline_idle && frame_level==0 && !m_valid && !flush_pending && !drain_pending;
    dila_magnitude u_magnitude(.clk(sys_clk),.rst_n(local_rst_n),.start(point_due && mode_active[1] && !magnitude_busy),
        .iq(filtered_iq),.tag(filtered_tag),.valid(mag_valid),.busy(magnitude_busy),.point(mag_data),.point_tag(mag_tag));
    wire boundary_fire=flush_pending && flush_timer==0 && !sample_valid && !ref_valid && !mix_valid &&
        !filter_busy && !filtered_valid && !magnitude_busy && !point_valid;
    dila_block_framer #(.MAX_POINTS(MAX_POINTS),.OUTPUT_FORMAT(OUTPUT_FORMAT),.SOURCE_ID(SOURCE_ID)) u_frame(
        .clk(sys_clk),.rst_n(local_rst_n),.clear(clear_fifo),.point_valid(point_valid),.point_data(point_data),.point_tag(point_tag),
        .point_flags((|error_status?32'h10:0)|(cycle_partial?32'h20:0)),.output_rate(rate_actual),.fragment_points(frag_active),
        .boundary_valid(boundary_fire),.boundary_cycle(flush_cycle),.boundary_partial(drain_pending),.drop_count(frame_drops),.last_fragment_count(frame_fragments),.level(frame_level),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags));
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            enable<=0;pending<=0;prepared<=0;calc_state<=0;div_start<=0;phase_start<=0;
            frequency_shadow<=1000000;phase1_shadow<=0;phase2_shadow<=0;rate_shadow<=10000;mode_shadow<=3;frag_shadow<=256;
            frequency_commit<=1000000;phase1_commit<=0;phase2_commit<=0;rate_commit<=10000;mode_commit<=3;frag_commit<=256;input_rate_commit<=INPUT_RATE_HZ;
            phase1_active<=0;phase2_active<=0;mode_active<=3;frag_active<=256;
            decimation<=INPUT_RATE_HZ/10000;rate_actual<=10000;phase_step<=42950;
            factor_next<=INPUT_RATE_HZ/10000;rate_next<=10000;phase_next<=42950;div_num<=0;div_den<=1;
            error_status<=0;in_sat_count<=0;mix_sat_count<=0;lpf_sat_count<=0;out_count<=0;
            last_input_cycle<=0;input_count<=0;last_filter_cycle<=0;decim_count<=0;
            have_input_cycle<=0;have_filter_cycle<=0;cycle_partial<=0;cycle_timestamp<=0;live_cycle<=0;
            flush_timer<=0;flush_pending<=0;drain_pending<=0;wms_valid_prev<=0;flush_cycle<=0;cooldown<=0;ref_valid<=0;ref_tag<=0;ref_sample<=0;ref_phase<=0;
        end else begin
            div_start<=0;phase_start<=0;ref_valid<=sample_fire && (!mode_active[0] || sample_tag[192]);
            wms_valid_prev<=wms_phase_valid;
            if(cooldown!=0)cooldown<=cooldown-1'b1;
            if(flush_timer!=0)flush_timer<=flush_timer-1'b1;
            if(wms_scan_start)begin cycle_timestamp<=timestamp_now;live_cycle<=wms_cycle_id;flush_pending<=1;flush_timer<=512;flush_cycle<=wms_cycle_id;end
            if(boundary_fire)begin flush_pending<=0;drain_pending<=0;end
            if((wms_valid_prev && !wms_phase_valid) || (wr && ofs==4 && mask[0] && !wd[0] && enable))begin
                drain_pending<=1;flush_pending<=1;flush_timer<=512;flush_cycle<=live_cycle+1'b1;cycle_partial<=1;
            end
            if(wr)case(ofs)
                8'h04:begin
                    enable<=(enable&~mask[0])|wd[0];
                    if(wd[2])begin
                        pending<=1;prepared<=0;frequency_commit<=frequency_shadow;phase1_commit<=phase1_shadow;phase2_commit<=phase2_shadow;
                        rate_commit<=rate_shadow;mode_commit<=mode_shadow;frag_commit<=frag_shadow;input_rate_commit<=input_rate;
                    end
                end
                8'h0c:error_status<=error_status&~wd;
                8'h10:frequency_shadow<=(frequency_shadow&~mask)|wd;
                8'h14:phase1_shadow<=(phase1_shadow&~mask)|wd;
                8'h18:phase2_shadow<=(phase2_shadow&~mask)|wd;
                8'h1c:rate_shadow<=(rate_shadow&~mask)|wd;
                8'h20:mode_shadow<=(mode_shadow&~mask)|wd;
                8'h2c:in_sat_count<=in_sat_count&~wd;
                8'h30:mix_sat_count<=mix_sat_count&~wd;
                8'h34:lpf_sat_count<=lpf_sat_count&~wd;
                8'h40:frag_shadow<=(frag_shadow&~mask)|wd;
                default:begin end
            endcase
            if(pending && !prepared && calc_state==0)begin
                div_num<=input_rate_commit+rate_commit-1;div_den<=rate_commit;div_start<=1;phase_start<=1;calc_state<=1;
            end
            if(phase_done)phase_next<=phase_result[31:0];
            if(div_done && calc_state==1)begin
                factor_next<=div_result;div_num<=input_rate_commit;div_den<=div_result;div_start<=1;calc_state<=2;
            end
            if(div_done && calc_state==2)begin rate_next<=div_result;calc_state<=3;end
            if(calc_state==3 && !phase_busy)begin prepared<=1;calc_state<=0;end
            if(apply_config)begin
                phase1_active<=phase1_commit;phase2_active<=phase2_commit;mode_active<=mode_commit;frag_active<=frag_commit;
                decimation<=factor_next;rate_actual<=rate_next;phase_step<=phase_next;pending<=0;prepared<=0;
            end
            if(sample_fire)begin
                cooldown<=5;ref_tag<=sample_tag;ref_sample<=sample_data;
                ref_phase<=mode_active[0]?sample_tag[63:32]:(sample_tag[95:64]*phase_step);
                if(input_new_cycle)begin
                    if(have_input_cycle && expected_per_cycle!=0 && input_count!=expected_per_cycle)cycle_partial<=1;
                    last_input_cycle<=sample_tag[31:0];input_count<=1;have_input_cycle<=1;
                end else input_count<=input_count+1'b1;
                if(sample_flags[0])in_sat_count<=in_sat_count+1'b1;
                if(|sample_flags || (mode_active[0] && !sample_tag[192]))begin error_status[7]<=1;cycle_partial<=1;end
            end
            if(filtered_valid)begin
                last_filter_cycle<=filtered_tag[31:0];have_filter_cycle<=1;
                if(point_due)decim_count<=0;else if(filter_new_cycle)decim_count<=1;else decim_count<=decim_count+1'b1;
            end
            if(input_overflow_pulse)begin error_status[2]<=1;cycle_partial<=1;end
            if(mix_sat)mix_sat_count<=mix_sat_count+1'b1;
            if(filter_sat)begin lpf_sat_count<=lpf_sat_count+1'b1;error_status[6]<=1;end
            if(point_due && magnitude_busy)begin error_status[5]<=1;cycle_partial<=1;end
            if(point_valid)out_count<=out_count+1'b1;
            if(frame_drops!=0)begin error_status[2]<=1;cycle_partial<=1;end
            if(hit && cfg_write && cfg_error)error_status[4]<=1;
            if(soft_reset)begin
                error_status<=0;in_sat_count<=0;mix_sat_count<=0;lpf_sat_count<=0;out_count<=0;
                have_input_cycle<=0;have_filter_cycle<=0;cycle_partial<=0;ref_valid<=0;cooldown<=0;
                pending<=0;prepared<=0;calc_state<=0;flush_pending<=0;drain_pending<=0;
            end
            if(clear_fifo)begin
                have_input_cycle<=0;have_filter_cycle<=0;cycle_partial<=0;ref_valid<=0;cooldown<=0;
                pending<=0;prepared<=0;calc_state<=0;flush_pending<=0;drain_pending<=0;decim_count<=0;
            end
        end
    end
endmodule

