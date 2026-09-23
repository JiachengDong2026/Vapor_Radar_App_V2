`include "sensor_cfg_codes.vh"
`include "project_defs.vh"
`include "error_codes.vh"
`default_nettype none
module ai8_modbus_rs485 #(
    parameter integer SYS_CLK_HZ=100000000,FIFO_DEPTH=256,SHARED_BUS=0,CHANNEL_COUNT=8
)(
    input wire sys_clk,rst_sys_n,input wire uart_rxd,output wire uart_txd,rs485_de,
    input wire [63:0] timestamp_now,input wire time_sync_valid,input wire [31:0] time_sync_seq,
    input wire cfg_valid,cfg_write,input wire [31:0] cfg_addr,cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg [31:0] cfg_rdata,output reg cfg_error,
    output wire m_valid,input wire m_ready,output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,m_last,output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,m_flags,
    output wire online,output reg [31:0] errors,output wire [31:0] drop_count,fifo_level,
    output reg [3:0] cfg_error_code,
    output wire bus_request,bus_busy,input wire bus_grant
);
    reg enabled,pending,submitted,result_valid;
    reg [31:0] baud,slave,format,channel,interval_ms,timeout_ms,retry_limit;
    reg [15:0] shadow_raw,pending_raw,last_requested,last_readback;
    reg [31:0] shadow_uc_cached;
    reg [15:0] pv,sp,sv,op,host;
    reg [7:0] alarm,control;
    reg sample_online;
    reg [3:0] result,transport_error;
    reg [7:0] result_exception;
    reg [31:0] crc_errors,timeout_count,frame_count,confirmed_count;
    wire hit=cfg_addr[31:8]==24'h000066;
    wire [7:0] ofs=cfg_addr[7:0];
    wire [31:0] mask={{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    wire [31:0] merged=(cfg_rdata & ~mask)|(cfg_wdata & mask);
    // Independent merge operands prevent raw->scale->cfg mux->divide chains.
    wire [31:0] uc_merged=(shadow_uc_cached & ~mask)|(cfg_wdata & mask);
    wire [31:0] raw_merged=({{16{shadow_raw[15]}},shadow_raw} & ~mask)|(cfg_wdata & mask);
    reg known,writable,config_busy;
    wire access=cfg_valid && cfg_ready;
    wire write_fire=access && cfg_write && !cfg_error;
    // CONTROL acceptance is local: arithmetic validation of an unrelated
    // shadow write must not enter the high-fanout reset/enable cone.
    wire ctrl_range_error=|(cfg_wdata & mask & 32'hfffffff0) ||
        (cfg_wstrb[0] && cfg_wdata[2] && !cfg_wdata[0]);
    wire ctrl_busy_error=cfg_wstrb[0] && cfg_wdata[2] && pending;
    wire ctrl_write_fire=cfg_valid && hit && cfg_write && ofs==8'h04 &&
        !ctrl_range_error && !ctrl_busy_error;
    wire soft_reset=ctrl_write_fire && cfg_wstrb[0] && cfg_wdata[1];
    wire clear_fifo=ctrl_write_fire && cfg_wstrb[0] && cfg_wdata[3];
    wire commit=ctrl_write_fire && cfg_wstrb[0] && cfg_wdata[2];
    wire local_rst_n=rst_sys_n && !soft_reset;
    assign cfg_ready=cfg_valid && hit;
    assign online=enabled && sample_online;
    wire pv_uc_valid=$signed(pv)>=-21474 && $signed(pv)<=21474;
    wire sp_uc_valid=$signed(sp)>=-21474 && $signed(sp)<=21474;
    wire signed [31:0] pv_uc=$signed(pv)*32'sd100000;
    wire signed [31:0] sp_uc=$signed(sp)*32'sd100000;
    wire [31:0] command_status={15'd0,result_valid,result_exception,transport_error,result};
    wire core_sample_valid,core_online,core_set_ready,core_rsp_valid,core_sample_sync;
    wire [15:0] core_pv,core_sp,core_sv,core_op,core_host,core_requested,core_readback;
    wire [7:0] core_alarm,core_control,core_exception,core_set_exception;
    wire [3:0] core_error,core_result,core_set_error;
    wire [63:0] core_ticks;
    wire [31:0] core_good,core_bad;
    reg record_valid;
    reg [2175:0] record_data;
    reg [8:0] record_length;
    reg [63:0] record_timestamp;
    reg [31:0] record_flags;
    wire accepted,drop_pulse,afull;
    reg [2175:0] next_record;
    integer cursor,tlvs;
    task put_tlv;
        input [15:0] tag; input [7:0] kind; input [31:0] value;
        begin
            next_record[cursor*8+:32]={8'd4,kind,tag};
            next_record[(cursor+4)*8+:32]=value;
            cursor=cursor+8; tlvs=tlvs+1;
        end
    endtask
    always @* begin
        cfg_rdata=0;known=1;writable=0;config_busy=0;
        case(ofs)
            0:cfg_rdata=32'h00460200;
            4:begin cfg_rdata={31'd0,enabled};writable=1;end
            8:begin
                cfg_rdata[0]=enabled;cfg_rdata[1]=online;cfg_rdata[2]=pending;
                cfg_rdata[3]=bus_busy || pending;cfg_rdata[4]=core_sample_valid;cfg_rdata[5]=afull;
                cfg_rdata[6]=errors[2];cfg_rdata[7]=|errors;cfg_rdata[8]=time_sync_valid;
                cfg_rdata[9]=result_valid;cfg_rdata[10]=pv_uc_valid;cfg_rdata[11]=sp_uc_valid;
            end
            12:begin cfg_rdata=errors;writable=1;end
            16:begin cfg_rdata=baud;writable=1;config_busy=enabled;end
            20:begin cfg_rdata=slave;writable=1;config_busy=enabled;end
            24:begin cfg_rdata=format;writable=1;config_busy=enabled;end
            28:begin cfg_rdata=channel;writable=1;config_busy=enabled;end
            32:begin cfg_rdata=shadow_uc_cached;writable=1;end
            36:cfg_rdata=pv_uc_valid ? pv_uc:0;
            40:cfg_rdata={host,control,alarm};
            44:begin cfg_rdata=interval_ms;writable=1;config_busy=enabled;end
            48:cfg_rdata=crc_errors;
            52:cfg_rdata=timeout_count;
            56:cfg_rdata=fifo_level;
            60:cfg_rdata=drop_count;
            64:cfg_rdata=sp_uc_valid ? sp_uc:0;
            68:cfg_rdata=frame_count;
            72:cfg_rdata=confirmed_count;
            76:cfg_rdata=command_status;
            80:begin cfg_rdata={{16{shadow_raw[15]}},shadow_raw};writable=1;end
            84:cfg_rdata={last_readback,last_requested};
            88:cfg_rdata={sp,pv};
            92:cfg_rdata={sv,op};
            96:begin cfg_rdata=timeout_ms;writable=1;config_busy=enabled;end
            100:begin cfg_rdata=retry_limit;writable=1;config_busy=enabled;end
            default:known=0;
        endcase
        cfg_error=0;cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_valid && hit)begin
            if(!known || |cfg_addr[1:0])begin cfg_error=1;cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;end
            else if(cfg_write && !writable)begin cfg_error=1;cfg_error_code=`SENSOR_CFG_READ_ONLY;end
            else if(cfg_write)begin
                case(ofs)
                    4:begin
                        if(ctrl_range_error)cfg_error=1;
                        if(!cfg_error && ctrl_busy_error)begin cfg_error=1;cfg_error_code=`SENSOR_CFG_BUSY;end
                    end
                    16:if(merged<4800 || merged>115200 || merged>SYS_CLK_HZ/16 || (SHARED_BUS && merged!=19200))cfg_error=1;
                    20:if(merged<1 || merged>80)cfg_error=1;
                    24:if(merged>3 || (SHARED_BUS && merged!=0))cfg_error=1;
                    28:if(merged<1 || merged>CHANNEL_COUNT || merged>96)cfg_error=1;
                    32:if($signed(uc_merged)<-32'sd999000000 || $signed(uc_merged)%100000!=0)cfg_error=1;
                    44:if(merged<1 || merged>3600000)cfg_error=1;
                    80:if($signed(raw_merged)<-9990 || $signed(raw_merged)>32000)cfg_error=1;
                    96:if(merged<1 || merged>65535)cfg_error=1;
                    100:if(merged>3)cfg_error=1;
                    default:;
                endcase
                if(config_busy && !cfg_error)begin cfg_error=1;cfg_error_code=`SENSOR_CFG_BUSY;end
                if(cfg_error && cfg_error_code==`SENSOR_CFG_OK)cfg_error_code=`SENSOR_CFG_RANGE;
            end
        end
    end
    ai8_poll_core #(.SYS_CLK_HZ(SYS_CLK_HZ),.SHARED_BUS(SHARED_BUS)) core (
        .clk(sys_clk),.rst_n(local_rst_n),.enable(enabled),.baud_hz(baud),.slave_addr(slave[7:0]),.channel(channel[7:0]),
        .parity_mode({1'b0,format[1]}),.stop_bits(format[0]?2'd2:2'd1),
        .poll_interval_ms(interval_ms),.timeout_ms(timeout_ms[15:0]),.retry_limit(retry_limit[1:0]),
        .uart_rxd(uart_rxd),.uart_txd(uart_txd),.rs485_de(rs485_de),
        .bus_request(bus_request),.bus_busy(bus_busy),.bus_grant(bus_grant),
        .sample_ready(1'b1),.sample_valid(core_sample_valid),.pv_raw(core_pv),.sp_raw(core_sp),.sv_raw(core_sv),.op_raw(core_op),
        .alarm(core_alarm),.control(core_control),.host_status(core_host),.online(core_online),
        .last_error(core_error),.exception_code(core_exception),.good_count(core_good),.error_count(core_bad),
        .sample_ticks(core_ticks),.now_ticks(timestamp_now),.time_sync_valid(time_sync_valid),.sample_time_sync(core_sample_sync),
        .set_valid(pending && !submitted),.set_ready(core_set_ready),
        .set_raw(pending_raw),.set_rsp_valid(core_rsp_valid),.set_rsp_ready(1'b1),.set_result(core_result),
        .set_error(core_set_error),.set_exception(core_set_exception),.set_requested(core_requested),.set_readback(core_readback)
    );
    always @* begin
        next_record=0;cursor=4;tlvs=0;
        put_tlv(`TLV_TAG_AI8_PV_RAW,`TLV_TYPE_I32,{{16{core_pv[15]}},core_pv});
        put_tlv(`TLV_TAG_AI8_SP_RAW,`TLV_TYPE_I32,{{16{core_sp[15]}},core_sp});
        put_tlv(`TLV_TAG_AI8_SV_RAW,`TLV_TYPE_I32,{{16{core_sv[15]}},core_sv});
        put_tlv(`TLV_TAG_AI8_OP_RAW,`TLV_TYPE_U32,{16'd0,core_op});
        put_tlv(`TLV_TAG_AI8_ALARM,`TLV_TYPE_U32,{24'd0,core_alarm});
        put_tlv(`TLV_TAG_AI8_CONTROL,`TLV_TYPE_U32,{24'd0,core_control});
        put_tlv(`TLV_TAG_AI8_HOST,`TLV_TYPE_U32,{16'd0,core_host});
        put_tlv(`TLV_TAG_AI8_SET_RESULT,`TLV_TYPE_U32,command_status);
        put_tlv(`TLV_TAG_DEVICE_STATUS,`TLV_TYPE_U32,{19'd0,core_exception,core_error,core_online});
        put_tlv(`TLV_TAG_DEVICE_ERROR,`TLV_TYPE_U32,{core_host,core_control,core_alarm});
        put_tlv(`TLV_TAG_SAMPLE_COUNTER,`TLV_TYPE_U32,core_good);
        if($signed(core_sp)>=-21474 && $signed(core_sp)<=21474)
            put_tlv(`TLV_TAG_TARGET_TEMP_UC,`TLV_TYPE_I32,$signed(core_sp)*32'sd100000);
        if($signed(core_pv)>=-21474 && $signed(core_pv)<=21474)
            put_tlv(`TLV_TAG_ACTUAL_TEMP_UC,`TLV_TYPE_I32,$signed(core_pv)*32'sd100000);
        next_record[15:0]=2;next_record[31:16]=tlvs;
    end
    sensor_record_fifo #(.SOURCE_ID(`SRC_AI8),.FIFO_DEPTH(FIFO_DEPTH)) records(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.clear_fifo(clear_fifo),.record_valid(record_valid),
        .record_data(record_data),.record_length(record_length),.record_msg_id(`MSG_SENSOR_TLV_RECORD),
        .record_timestamp(record_timestamp),.record_flags(record_flags),.accepted(accepted),.drop_pulse(drop_pulse),
        .drop_count(drop_count),.fifo_level(fifo_level),.fifo_almost_full(afull),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags));
    always @(posedge sys_clk)begin
        if(!local_rst_n)begin
            enabled<=0;pending<=0;submitted<=0;result_valid<=0;
            baud<=19200;slave<=1;format<=0;channel<=1;interval_ms<=1000;timeout_ms<=200;retry_limit<=1;
            shadow_raw<=250;shadow_uc_cached<=25000000;pending_raw<=0;last_requested<=0;last_readback<=0;
            pv<=0;sp<=0;sv<=0;op<=0;host<=0;alarm<=0;control<=0;sample_online<=0;
            result<=0;transport_error<=0;result_exception<=0;errors<=0;
            crc_errors<=0;timeout_count<=0;frame_count<=0;confirmed_count<=0;
            record_valid<=0;record_data<=0;record_length<=0;record_timestamp<=0;record_flags<=0;
        end else begin
            record_valid<=0;
            if(access && cfg_error)errors<=errors|`ERR_CONFIG_RANGE;
            if(ctrl_write_fire && cfg_wstrb[0])enabled<=cfg_wdata[0];
            if(write_fire)case(ofs)
                12:errors<=errors & ~(cfg_wdata & mask);
                16:baud<=merged;20:slave<=merged;24:format<=merged;28:channel<=merged;
                32:begin shadow_raw<=$signed(uc_merged)/100000;shadow_uc_cached<=uc_merged;end
                44:interval_ms<=merged;
                80:begin
                    shadow_raw<=raw_merged[15:0];
                    if($signed(raw_merged)>=-21474 && $signed(raw_merged)<=21474)
                        shadow_uc_cached<=$signed(raw_merged)*32'sd100000;
                    else shadow_uc_cached<=0;
                end
                96:timeout_ms<=merged;100:retry_limit<=merged;
                default:;
            endcase
            if(commit)begin pending<=1;submitted<=0;pending_raw<=shadow_raw;result_valid<=0;end
            if(pending && !submitted && core_set_ready)submitted<=1;
            if(core_rsp_valid)begin
                pending<=0;submitted<=0;result_valid<=1;result<=core_result;
                transport_error<=core_set_error;result_exception<=core_set_exception;
                last_requested<=core_requested;last_readback<=core_readback;
                if(core_result==0)confirmed_count<=confirmed_count+1'b1;
                else if(core_set_error==1)begin errors[0]<=1;timeout_count<=timeout_count+1'b1;end
                else if(core_set_error==2)begin errors[1]<=1;crc_errors<=crc_errors+1'b1;end
                else if(core_result==3 || core_set_error==4)errors[6]<=1;
                else errors[1]<=1;
            end
            if(core_sample_valid)begin
                pv<=core_pv;sp<=core_sp;sv<=core_sv;op<=core_op;host<=core_host;
                alarm<=core_alarm;control<=core_control;sample_online<=core_online;
                if(core_online)frame_count<=frame_count+1'b1;
                else if(core_error==1)begin errors[0]<=1;timeout_count<=timeout_count+1'b1;end
                else begin errors[1]<=1;if(core_error==2)crc_errors<=crc_errors+1'b1;end
                if(core_alarm!=0 || core_host[9:8]!=0)errors[6]<=1;
                record_data<=next_record;record_length<=cursor;record_timestamp<=core_ticks;record_valid<=1;
                record_flags<=32'd1|(core_sample_sync?32'd4:0)|
                    ((!core_online || core_alarm!=0 || core_host[9:8]!=0)?32'd16:0);
            end
            if(!enabled && !commit)begin
                sample_online<=0;
                if(pending)begin
                    pending<=0;submitted<=0;result_valid<=1;result<=5;transport_error<=6;
                    result_exception<=0;last_requested<=pending_raw;last_readback<=0;
                end
            end
            if(drop_pulse)errors[2]<=1;
        end
    end
endmodule
`default_nettype wire
