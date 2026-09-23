`include "sensor_cfg_codes.vh"
`include "project_defs.vh"
`include "error_codes.vh"
module sht45_driver #(
    parameter integer SYS_CLK_HZ=100000000,FIFO_DEPTH=256
)(
    input wire sys_clk,rst_sys_n,
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
    localparam OFF=0,BOOT=1,RESET_CMD=2,RESET_ACK=3,RESET_DELAY=4,SERIAL_CMD=5,
        SERIAL_ACK=6,SERIAL_DELAY=7,SERIAL_READ=8,SERIAL_WAIT=9,SERIAL_CHECK=10,
        POLL=11,MEAS_CMD=12,MEAS_ACK=13,CONVERT=14,MEAS_READ=15,MEAS_WAIT=16,MEAS_CHECK=17;
    reg [4:0] state;
    reg enabled,soft_reset,clear_fifo;
    reg [6:0] address;
    reg [31:0] interval_ms,repeatability,heater,elapsed_ms,divider,crc_errors,i2c_errors;
    reg [31:0] serial;
    reg [15:0] raw_temp,raw_rh;
    reg [47:0] response;
    reg [63:0] sample_time;
    reg sample_sync;
    reg record_valid;
    reg [2175:0] record_data;
    wire accepted,drop_pulse,afull;
    wire selected=cfg_addr[31:8]==24'h000064;
    wire [7:0] offset=cfg_addr[7:0];
    wire access=cfg_valid&&selected;
    wire write_fire=access&&cfg_write&&!cfg_error;
    wire ms_tick=divider>=SYS_CLK_HZ/1000-1;
    wire local_rst_n=rst_sys_n&&!soft_reset;
    reg [31:0] merged,mask;
    integer j;
    wire [15:0] first_word={response[7:0],response[15:8]};
    wire [15:0] second_word={response[31:24],response[39:32]};
    function [7:0] crc8;
        input [15:0] data;
        integer n;
        reg [7:0] c;
        begin
            c=8'hff;
            for(n=15;n>=0;n=n-1) c=(c[7]^data[n])?{c[6:0],1'b0}^8'h31:{c[6:0],1'b0};
            crc8=c;
        end
    endfunction
    wire crc_ok=crc8(first_word)==response[23:16]&&crc8(second_word)==response[47:40];
    wire [63:0] temperature_scaled=first_word*64'd175000;
    wire [63:0] humidity_scaled=second_word*64'd125000;
    wire signed [31:0] temperature_mc=$signed(temperature_scaled/65535)-32'sd45000;
    wire signed [31:0] humidity_uncropped=$signed(humidity_scaled/65535)-32'sd6000;
    wire [31:0] humidity=humidity_uncropped<0?0:humidity_uncropped>100000?100000:humidity_uncropped;
    wire [31:0] conversion_ms=heater==0?(repeatability==0?9:repeatability==1?5:2):
        (heater[0]?1110:120);
    reg [7:0] measure_command;
    always @* begin
        case(heater)
            1:measure_command=8'h39;2:measure_command=8'h32;
            3:measure_command=8'h2f;4:measure_command=8'h24;
            5:measure_command=8'h1e;6:measure_command=8'h15;
            default:measure_command=repeatability==0?8'hfd:repeatability==1?8'hf6:8'he0;
        endcase
    end
    assign cfg_ready=access;
    assign req_addr=address;
    assign req_valid=state==RESET_CMD||state==SERIAL_CMD||state==SERIAL_READ||state==MEAS_CMD||state==MEAS_READ;
    always @* begin
        req_write_len=1;req_read_len=0;req_write_data=0;
        case(state)
            RESET_CMD:req_write_data[7:0]=8'h94;
            SERIAL_CMD:req_write_data[7:0]=8'h89;
            MEAS_CMD:req_write_data[7:0]=measure_command;
            default:begin req_write_len=0;req_read_len=6;end
        endcase
    end
    always @* begin
        cfg_rdata=0;cfg_error=0;mask=0;
        for(j=0;j<4;j=j+1) mask[j*8+:8]={8{cfg_wstrb[j]}};
        case(offset)
            0:cfg_rdata={`SRC_SHT45,16'h0101};4:cfg_rdata={31'd0,enabled};
            8:cfg_rdata={23'd0,time_sync_valid,(|errors),errors[2],afull,online,(state!=OFF&&state!=POLL),1'b0,online,enabled};
            12:cfg_rdata=errors;16:cfg_rdata=address;20:cfg_rdata=interval_ms;
            24:cfg_rdata=repeatability;28:cfg_rdata=heater;32:cfg_rdata=raw_temp;36:cfg_rdata=raw_rh;
            40:cfg_rdata=crc_errors;44:cfg_rdata=i2c_errors;48:cfg_rdata=serial;52:cfg_rdata=0;
            56:cfg_rdata=fifo_level;60:cfg_rdata=drop_count;
            default:cfg_error=1;
        endcase
        merged=(cfg_rdata&~mask)|(cfg_wdata&mask);
        if(cfg_addr[1:0]!=0) cfg_error=1;
        if(cfg_write) case(offset)
            4:if(merged>15) cfg_error=1;
            12:;
            16:cfg_error=1;
            20:if(enabled||merged==0||merged>3600000 || (heater!=0&&merged<(heater[0]?12000:1300))) cfg_error=1;
            24:if(enabled||merged>2) cfg_error=1;
            28:if(enabled||merged>6||(merged!=0&&interval_ms<(merged[0]?12000:1300))) cfg_error=1;
            default:cfg_error=1;
        endcase
        if(!access)begin cfg_error=0;cfg_rdata=0;end
    end
    always @(posedge sys_clk) begin
        if(!rst_sys_n) begin soft_reset<=0;clear_fifo<=0;end
        else begin
            soft_reset<=write_fire&&offset==4&&cfg_wstrb[0]&&cfg_wdata[1];
            clear_fifo<=write_fire&&offset==4&&cfg_wstrb[0]&&cfg_wdata[3];
        end
    end
    sensor_record_fifo #(.SOURCE_ID(`SRC_SHT45),.FIFO_DEPTH(FIFO_DEPTH)) u_records(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.clear_fifo(clear_fifo),
        .record_valid(record_valid),.record_data(record_data),.record_length(9'd28),
        .record_msg_id(`MSG_SENSOR_TLV_RECORD),.record_timestamp(sample_time),
        .record_flags(32'd1|(sample_sync?32'd4:0)|(heater!=0?32'd16:0)),
        .accepted(accepted),.drop_pulse(drop_pulse),.drop_count(drop_count),.fifo_level(fifo_level),.fifo_almost_full(afull),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags));
    always @(posedge sys_clk) begin
        if(!local_rst_n) begin
            state<=OFF;enabled<=0;address<=7'h44;interval_ms<=1000;repeatability<=0;heater<=0;
            elapsed_ms<=0;divider<=0;crc_errors<=0;i2c_errors<=0;serial<=0;raw_temp<=0;raw_rh<=0;
            response<=0;sample_time<=0;sample_sync<=0;record_valid<=0;record_data<=0;online<=0;errors<=0;
        end else begin
            record_valid<=0;
            if(ms_tick) begin divider<=0;if(elapsed_ms<3600000)elapsed_ms<=elapsed_ms+1'b1;end
            else divider<=divider+1'b1;
            if(access&&cfg_write&&cfg_error) errors<=errors|`ERR_CONFIG_RANGE;
            if(write_fire) case(offset)
                4:enabled<=merged[0];12:errors<=errors&~(cfg_wdata&mask);
                16:address<=merged[6:0];20:interval_ms<=merged;24:repeatability<=merged;28:heater<=merged;
                default:;
            endcase
            if(drop_pulse)errors[2]<=1;
            if(!enabled) begin state<=OFF;elapsed_ms<=0;online<=0;end
            else case(state)
                OFF:begin state<=BOOT;elapsed_ms<=0;end
                BOOT:if(elapsed_ms>=2)state<=RESET_CMD;
                RESET_CMD:if(req_ready)state<=RESET_ACK;
                RESET_ACK:if(done)begin state<=RESET_DELAY;elapsed_ms<=0;end
                RESET_DELAY:if(elapsed_ms>=2)state<=SERIAL_CMD;
                SERIAL_CMD:if(req_ready)state<=SERIAL_ACK;
                SERIAL_ACK:if(done)begin state<=SERIAL_DELAY;elapsed_ms<=0;end
                SERIAL_DELAY:if(elapsed_ms>=2)state<=SERIAL_READ;
                SERIAL_READ:if(req_ready)state<=SERIAL_WAIT;
                SERIAL_WAIT:if(done)begin response<=read_data[47:0];state<=SERIAL_CHECK;end
                SERIAL_CHECK:begin
                    if(crc_ok)begin serial<={first_word,second_word};online<=1;end
                    else begin crc_errors<=crc_errors+1'b1;errors[1]<=1;end
                    state<=POLL;elapsed_ms<=interval_ms;
                end
                POLL:if(elapsed_ms>=interval_ms)state<=MEAS_CMD;
                MEAS_CMD:if(req_ready)begin state<=MEAS_ACK;sample_time<=timestamp_now;sample_sync<=time_sync_valid;end
                MEAS_ACK:if(done)begin state<=CONVERT;elapsed_ms<=0;divider<=0;end
                CONVERT:if(elapsed_ms>=conversion_ms)state<=MEAS_READ;
                MEAS_READ:if(req_ready)state<=MEAS_WAIT;
                MEAS_WAIT:if(done)begin response<=read_data[47:0];state<=MEAS_CHECK;end
                MEAS_CHECK:begin
                    if(crc_ok)begin
                        raw_temp<=first_word;raw_rh<=second_word;online<=1;record_valid<=1;
                        record_data<=0;
                        record_data[31:0]<=32'h00030001;
                        record_data[63:32]<={8'd4,`TLV_TYPE_I32,`TLV_TAG_TEMPERATURE_MC};
                        record_data[95:64]<=temperature_mc;
                        record_data[127:96]<={8'd4,`TLV_TYPE_U32,`TLV_TAG_HUMIDITY_MILLI_PCT};
                        record_data[159:128]<=humidity;
                        record_data[191:160]<={8'd4,`TLV_TYPE_U32,`TLV_TAG_DEVICE_STATUS};
                        record_data[223:192]<=heater;
                    end else begin crc_errors<=crc_errors+1'b1;errors[1]<=1;end
                    state<=POLL;elapsed_ms<=0;
                end
                default:state<=OFF;
            endcase
            if(done&&error!=0) begin
                i2c_errors<=i2c_errors+1'b1;errors[1]<=1;online<=0;
                if(error==2)errors[0]<=1;
                state<=BOOT;elapsed_ms<=0;
            end
        end
    end
    always @* begin
        cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_ready && cfg_error)begin
            cfg_error_code=`SENSOR_CFG_RANGE;
            if(cfg_addr[1:0]!=0 || offset>8'h3c)cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;
            else if(cfg_write)case(offset)
                4,12:;
                20:if(enabled && merged!=0 && merged<=3600000 &&
                    (heater==0 || merged>=(heater[0]?12000:1300)))cfg_error_code=`SENSOR_CFG_BUSY;
                24:if(enabled && merged<=2)cfg_error_code=`SENSOR_CFG_BUSY;
                28:if(enabled && merged<=6 && (merged==0 || interval_ms>=(merged[0]?12000:1300)))
                    cfg_error_code=`SENSOR_CFG_BUSY;
                default:cfg_error_code=`SENSOR_CFG_READ_ONLY;
            endcase
        end
    end

endmodule
