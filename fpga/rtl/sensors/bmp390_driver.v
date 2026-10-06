`include "sensor_cfg_codes.vh"
`include "project_defs.vh"
`include "error_codes.vh"
module bmp390_driver #(
    parameter integer SYS_CLK_HZ=100000000,FIFO_DEPTH=256
)(
    input wire sys_clk,rst_sys_n,bmp_int,
    input wire [63:0] timestamp_now,input wire time_sync_valid,input wire [31:0] time_sync_seq,
    input wire cfg_valid,cfg_write,input wire [31:0] cfg_addr,cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg [31:0] cfg_rdata,output reg cfg_error,
    output wire req_valid,input wire req_ready,
    output wire [6:0] req_addr,output reg [5:0] req_write_len,req_read_len,
    output reg [255:0] req_write_data,input wire done,input wire [2:0] error,input wire [255:0] read_data,
    output wire m_valid,input wire m_ready,output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,m_last,output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,m_flags,
    output reg online,output reg [31:0] errors,output wire [31:0] drop_count,fifo_level,
    output reg [3:0] cfg_error_code
);
    localparam OFF=0,BOOT=1,ISSUE=2,WAIT_DONE=3,PROCESS=4,POLL=5,CAL_WAIT=6;
    // op: reset,chip,calibration,OSR,ODR,IIR,PWR,status,raw,error,forced trigger
    reg [3:0] state,op;
    reg enabled,soft_reset,clear_fifo,pending;
    reg [6:0] address;
    reg [31:0] interval_ms,elapsed_ms,divider,i2c_errors;
    reg [7:0] osr_shadow,odr_shadow,iir_shadow,pwr_shadow,osr,odr,iir,pwr,chip_id;
    reg [23:0] raw_pressure,raw_temperature;
    reg [255:0] response;
    reg [63:0] sample_time,int_time;
    reg sample_sync,int_sync,int_pending;
    (* ASYNC_REG="TRUE" *) reg int_meta,int_ff;
    reg int_previous;
    reg record_valid;
    reg [2175:0] record_data;
    reg [8:0] record_length;
    wire accepted,drop_pulse,afull;
    wire selected=cfg_addr[31:8]==24'h000063;
    wire [7:0] offset=cfg_addr[7:0];
    wire access=cfg_valid&&selected;
    wire write_fire=access&&cfg_write&&!cfg_error;
    wire ms_tick=divider>=SYS_CLK_HZ/1000-1;
    wire local_rst_n=rst_sys_n&&!soft_reset;
    reg [31:0] merged,mask;
    integer j;
    assign cfg_ready=access;
    assign req_addr=address;
    assign req_valid=state==ISSUE;
    always @* begin
        req_write_len=1;req_read_len=1;req_write_data=0;
        case(op)
            0:begin req_write_len=2;req_read_len=0;req_write_data[15:0]=16'hb67e;end
            1:req_write_data[7:0]=8'h00;
            2:begin req_write_data[7:0]=8'h31;req_read_len=21;end
            3:begin req_write_len=2;req_read_len=0;req_write_data[15:0]={osr,8'h1c};end
            4:begin req_write_len=2;req_read_len=0;req_write_data[15:0]={odr,8'h1d};end
            5:begin req_write_len=2;req_read_len=0;req_write_data[15:0]={iir,8'h1f};end
            6,10:begin req_write_len=2;req_read_len=0;req_write_data[15:0]={pwr,8'h1b};end
            7:req_write_data[7:0]=8'h03;
            8:begin req_write_data[7:0]=8'h04;req_read_len=6;end
            9:req_write_data[7:0]=8'h02;
            default:;
        endcase
    end
    always @* begin
        cfg_rdata=0;cfg_error=0;mask=0;
        for(j=0;j<4;j=j+1) mask[j*8+:8]={8{cfg_wstrb[j]}};
        case(offset)
            0:cfg_rdata={`SRC_BMP390,16'h0101};4:cfg_rdata={31'd0,enabled};
            8:cfg_rdata={23'd0,time_sync_valid,(|errors),errors[2],afull,online,(state!=OFF&&state!=POLL),pending,online,enabled};
            12:cfg_rdata=errors;16:cfg_rdata=address;20:cfg_rdata=interval_ms;
            24:cfg_rdata=osr_shadow;28:cfg_rdata=odr_shadow;32:cfg_rdata=iir_shadow;36:cfg_rdata=pwr_shadow;
            40:cfg_rdata=chip_id;44:cfg_rdata=raw_pressure;48:cfg_rdata=raw_temperature;
            52:cfg_rdata=i2c_errors;56:cfg_rdata=0;60:cfg_rdata=fifo_level;64:cfg_rdata=drop_count;
            default:cfg_error=1;
        endcase
        merged=(cfg_rdata&~mask)|(cfg_wdata&mask);
        if(cfg_addr[1:0]!=0)cfg_error=1;
        if(cfg_write)case(offset)
            4:if(merged>15)cfg_error=1;
            12:;
            16:if(enabled||(merged!=7'h76&&merged!=7'h77))cfg_error=1;
            20:if(merged==0||merged>3600000)cfg_error=1;
            24:if(merged>63||merged[2:0]>5||merged[5:3]>5)cfg_error=1;
            28:if(merged>17)cfg_error=1;
            32:if(merged>14||merged[0])cfg_error=1;
            36:if((merged&32'hffffffcc)!=0)cfg_error=1;
            56:if(merged!=0)cfg_error=1;
            default:cfg_error=1;
        endcase
        if(!access)begin cfg_error=0;cfg_rdata=0;end
    end
    always @(posedge sys_clk) begin
        if(!rst_sys_n)begin soft_reset<=0;clear_fifo<=0;int_meta<=0;int_ff<=0;int_previous<=0;end
        else begin
            soft_reset<=write_fire&&offset==4&&cfg_wstrb[0]&&cfg_wdata[1];
            clear_fifo<=write_fire&&offset==4&&cfg_wstrb[0]&&cfg_wdata[3];
            int_meta<=bmp_int;int_ff<=int_meta;int_previous<=int_ff;
        end
    end
    sensor_record_fifo #(.SOURCE_ID(`SRC_BMP390),.FIFO_DEPTH(FIFO_DEPTH))u_records(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.clear_fifo(clear_fifo),
        .record_valid(record_valid),.record_data(record_data),.record_length(record_length),
        .record_msg_id(`MSG_SENSOR_TLV_RECORD),.record_timestamp(sample_time),.record_flags(32'd1|(sample_sync?32'd4:0)),
        .accepted(accepted),.drop_pulse(drop_pulse),.drop_count(drop_count),.fifo_level(fifo_level),.fifo_almost_full(afull),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags));
    always @(posedge sys_clk)begin
        if(!local_rst_n)begin
            state<=OFF;op<=0;enabled<=0;address<=7'h76;interval_ms<=1000;
            osr_shadow<=0;odr_shadow<=5;iir_shadow<=0;pwr_shadow<=8'h33;
            osr<=0;odr<=5;iir<=0;pwr<=8'h33;pending<=0;chip_id<=0;
            elapsed_ms<=0;divider<=0;i2c_errors<=0;raw_pressure<=0;raw_temperature<=0;
            response<=0;sample_time<=0;sample_sync<=0;record_valid<=0;record_data<=0;record_length<=0;
            online<=0;errors<=0;int_time<=0;int_sync<=0;int_pending<=0;
        end else begin
            record_valid<=0;
            if(ms_tick)begin divider<=0;if(elapsed_ms<3600000)elapsed_ms<=elapsed_ms+1'b1;end
            else divider<=divider+1'b1;
            if(int_ff&&!int_previous)begin int_time<=timestamp_now;int_sync<=time_sync_valid;int_pending<=1;end
            if(access&&cfg_write&&cfg_error)errors<=errors|`ERR_CONFIG_RANGE;
            if(write_fire)case(offset)
                4:begin enabled<=merged[0];if(cfg_wstrb[0]&&cfg_wdata[2])pending<=1;end
                12:errors<=errors&~(cfg_wdata&mask);16:address<=merged[6:0];20:interval_ms<=merged;
                24:osr_shadow<=merged[7:0];28:odr_shadow<=merged[7:0];32:iir_shadow<=merged[7:0];36:pwr_shadow<=merged[7:0];
                default:;
            endcase
            if(drop_pulse)errors[2]<=1;
            case(state)
                OFF:if(enabled)begin
                    state<=BOOT;elapsed_ms<=0;op<=0;osr<=osr_shadow;odr<=odr_shadow;iir<=iir_shadow;pwr<=pwr_shadow;pending<=0;
                end
                BOOT:if(elapsed_ms>=5)state<=ISSUE;
                ISSUE:if(req_ready)begin
                    state<=WAIT_DONE;
                    if(op==8)begin sample_time<=int_pending?int_time:timestamp_now;sample_sync<=int_pending?int_sync:time_sync_valid;int_pending<=0;end
                end
                WAIT_DONE:if(done)begin
                    response<=read_data;state<=PROCESS;
                    if(error!=0)begin i2c_errors<=i2c_errors+1'b1;errors[1]<=1;if(error==2)errors[0]<=1;
                        online<=0;state<=BOOT;op<=0;elapsed_ms<=0;end
                end
                PROCESS:case(op)
                    0:begin op<=1;state<=BOOT;elapsed_ms<=0;end
                    1:begin
                        chip_id<=response[7:0];
                        if(response[7:0]==8'h60)begin op<=2;state<=ISSUE;end
                        else begin errors[3]<=1;online<=0;state<=BOOT;op<=0;elapsed_ms<=0;end
                    end
                    2:begin
                        if(fifo_level<=FIFO_DEPTH-8)begin
                        // Device-specific tag 0100 = 21 raw calibration bytes at 31..45.
                        record_data<=0;record_data[31:0]<=32'h00010001;
                        record_data[63:32]<={8'd21,`TLV_TYPE_BYTES,16'h0100};record_data[231:64]<=response[167:0];
                        record_length<=32;record_valid<=1;sample_time<=timestamp_now;sample_sync<=time_sync_valid;
                        state<=CAL_WAIT;
                        end
                    end
                    3,4,5:begin op<=op+1'b1;state<=ISSUE;end
                    6:begin op<=9;state<=ISSUE;end
                    9:begin
                        if(response[2:0]!=0)begin errors[6]<=1;online<=0;end else online<=1;
                        state<=POLL;elapsed_ms<=0;
                    end
                    7:begin
                        if((response[6:5]&pwr[1:0])==pwr[1:0])begin op<=8;state<=ISSUE;end
                        else if(elapsed_ms>interval_ms+((32'd5000<<odr)/1000)+200)begin
                            errors[0]<=1;online<=0;state<=BOOT;op<=0;elapsed_ms<=0;end
                        else begin op<=7;state<=ISSUE;end
                    end
                    8:begin
                        raw_pressure<=response[23:0];raw_temperature<=response[47:24];online<=1;
                        record_data<=0;record_data[31:0]<=pwr[1:0]==3?32'h00020001:32'h00010001;
                        record_data[63:32]<={8'd4,`TLV_TYPE_U32,(pwr[0]?16'h0101:16'h0102)};
                        record_data[95:64]<=pwr[0]?{8'd0,response[23:0]}:{8'd0,response[47:24]};
                        record_data[127:96]<={8'd4,`TLV_TYPE_U32,16'h0102};record_data[159:128]<={8'd0,response[47:24]};
                        record_length<=pwr[1:0]==3?20:12;record_valid<=1;state<=POLL;elapsed_ms<=0;
                    end
                    10:begin op<=7;state<=ISSUE;end
                    default:state<=OFF;
                endcase
                CAL_WAIT:begin
                    if(accepted)begin op<=3;state<=ISSUE;end
                    else if(drop_pulse)state<=PROCESS;
                end
                POLL:begin
                    if(!enabled)begin state<=OFF;online<=0;end
                    else if(pending)begin
                        osr<=osr_shadow;odr<=odr_shadow;iir<=iir_shadow;pwr<=pwr_shadow;pending<=0;
                        op<=0;state<=BOOT;elapsed_ms<=0;
                    end else if(online&&pwr[5:4]!=0&&pwr[1:0]!=0&&elapsed_ms>=interval_ms)begin
                        op<=pwr[5:4]==3?7:10;state<=ISSUE;end
                end
                default:state<=OFF;
            endcase
        end
    end
    always @* begin
        cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_ready && cfg_error)begin
            cfg_error_code=`SENSOR_CFG_RANGE;
            if(cfg_addr[1:0]!=0 || offset>8'h40)cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;
            else if(cfg_write)case(offset)
                4,12,20,24,28,32,36,56:;
                16:if(enabled && (merged==7'h76 || merged==7'h77))cfg_error_code=`SENSOR_CFG_BUSY;
                default:cfg_error_code=`SENSOR_CFG_READ_ONLY;
            endcase
        end
    end

endmodule
