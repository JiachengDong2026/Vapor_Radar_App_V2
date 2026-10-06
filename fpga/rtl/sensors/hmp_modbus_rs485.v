`include "sensor_cfg_codes.vh"
`include "project_defs.vh"
`include "error_codes.vh"
`default_nettype none
module hmp_modbus_rs485 #(
    parameter integer SYS_CLK_HZ=100000000,FIFO_DEPTH=256,SHARED_BUS=0
)(
    input wire sys_clk,rst_sys_n,input wire uart_rxd,output wire uart_txd,rs485_de,
    input wire [63:0] timestamp_now,input wire time_sync_valid,input wire [31:0] time_sync_seq,
    input wire cfg_valid,cfg_write,input wire [31:0] cfg_addr,cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output wire [31:0] cfg_rdata,output wire cfg_error,
    output wire m_valid,input wire m_ready,output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,m_last,output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,m_flags,
    output wire online,output wire [31:0] errors,drop_count,fifo_level,
    output wire [3:0] cfg_error_code,
    output wire bus_request,bus_busy,input wire bus_grant
);
    modbus_sensor_driver #(.SYS_CLK_HZ(SYS_CLK_HZ),.FIFO_DEPTH(FIFO_DEPTH),.DEVICE_KIND(0),.SHARED_BUS(SHARED_BUS)) core(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.uart_rxd(uart_rxd),.uart_txd(uart_txd),.rs485_de(rs485_de),
        .timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),.time_sync_seq(time_sync_seq),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready),.cfg_rdata(cfg_rdata),.cfg_error(cfg_error),.cfg_error_code(cfg_error_code),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags),
        .online(online),.errors(errors),.drop_count(drop_count),.fifo_level(fifo_level),.bus_request(bus_request),.bus_busy(bus_busy),.bus_grant(bus_grant));
endmodule

// Shared byte-transaction driver. DEVICE_KIND is constant and removes the other
// sensor's logic at synthesis. Byte zero occupies the low byte of payload buses.
module modbus_sensor_driver #(
    parameter integer SYS_CLK_HZ=100000000,FIFO_DEPTH=256,SHARED_BUS=0,DEVICE_KIND=0
)(
    input wire sys_clk,rst_sys_n,input wire uart_rxd,output wire uart_txd,rs485_de,
    input wire [63:0] timestamp_now,input wire time_sync_valid,input wire [31:0] time_sync_seq,
    input wire cfg_valid,cfg_write,input wire [31:0] cfg_addr,cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg [31:0] cfg_rdata,output reg cfg_error,
    output wire m_valid,input wire m_ready,output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,m_last,output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,m_flags,
    output reg online,output reg [31:0] errors,output wire [31:0] drop_count,fifo_level,
    output reg [3:0] cfg_error_code,
    output wire bus_request,bus_busy,input wire bus_grant
);
    localparam HMP=DEVICE_KIND==0;
    localparam [23:0] PAGE=HMP ? 24'h000061 : 24'h000066;
    localparam [15:0] SOURCE_ID=HMP ? `SRC_HMP : `SRC_RD105;
    localparam OFF=0,IDLE=1,WRITE_REQ=2,WRITE_WAIT=3,TARGET_REQ=4,TARGET_WAIT=5,
        MEAS_REQ=6,MEAS_WAIT=7,ERROR_REQ=8,ERROR_WAIT=9,EMIT=10;
    reg [3:0] state;
    reg enabled,pending;
    reg [31:0] baud,slave,serial_format,channel,interval_ms,meas_mask,shadow_value,pending_value,active_value;
    reg [31:0] rh_bits,temp_bits,actual_uc,device_error,crc_errors,timeout_count,frame_count,write_count;
    reg [31:0] ms_div,elapsed_ms;
    reg [31:0] native_write;
    reg actual_valid;
    reg [63:0] sample_timestamp;
    reg sample_sync;
    wire hit=cfg_addr[31:8]==PAGE;
    wire [7:0] ofs=cfg_addr[7:0];
    wire [31:0] mask={{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    wire [31:0] merged=(cfg_rdata & ~mask)|(cfg_wdata & mask);
    reg known,writable;
    assign cfg_ready=cfg_valid && hit;
    wire access=cfg_valid && cfg_ready;
    wire write_fire=access && cfg_write && !cfg_error;
    wire soft_reset=write_fire && ofs==4 && cfg_wstrb[0] && cfg_wdata[1];
    wire clear_fifo=write_fire && ofs==4 && cfg_wstrb[0] && cfg_wdata[3];
    wire commit=write_fire && ofs==4 && cfg_wstrb[0] && cfg_wdata[2];
    wire local_rst_n=rst_sys_n && !soft_reset;
    wire ms_tick=ms_div==SYS_CLK_HZ/1000-1;
    wire req_valid=state==WRITE_REQ || state==TARGET_REQ || state==MEAS_REQ || state==ERROR_REQ;
    wire req_ready,done,busy;
    wire [3:0] mb_error,attempt_error;
    wire attempt_error_pulse;
    wire [7:0] exception_code;
    wire [255:0] read_data;
    reg [255:0] write_data;
    wire [63:0] response_timestamp;
    wire response_sync;
    wire [7:0] req_function=state==WRITE_REQ ? 8'h10 : 8'h03;
    wire [15:0] req_address=HMP ? (state==WRITE_REQ ? 16'h0300 : 16'h0000) :
        (state==ERROR_REQ ? 16'h0007 : {channel[3:0],12'd0}+(state==MEAS_REQ ? 16'd2 : 16'd0));
    wire [4:0] req_quantity=HMP ? (state==WRITE_REQ ? 5'd2 : 5'd4) : (state==ERROR_REQ ? 5'd1 : 5'd2);
    wire [1:0] parity=HMP ? serial_format[2:1] : 2'd0;
    wire [1:0] stops=HMP ? (serial_format[0] ? 2'd2 : 2'd1) : 2'd1;
    wire [31:0] hmp_rh={read_data[23:16],read_data[31:24],read_data[7:0],read_data[15:8]};
    wire [31:0] hmp_temp={read_data[55:48],read_data[63:56],read_data[39:32],read_data[47:40]};
    wire signed [31:0] native_read=$signed({read_data[7:0],read_data[15:8],read_data[23:16],read_data[31:24]});
    wire native_valid=native_read!=32'sd999999999 && native_read>=-32'sd40000000 && native_read<=32'sd100000000;
    wire signed [35:0] uc_product=native_read*36'sd10;
    reg record_valid;
    reg [2175:0] record_data,next_record;
    reg [8:0] record_length,next_length;
    reg [31:0] record_flags;
    wire accepted,drop_pulse,afull;
    integer cursor,tlvs;
    always @*begin
        write_data=0;
        if(HMP)write_data[31:0]={pending_value[23:16],pending_value[31:24],pending_value[7:0],pending_value[15:8]};
        else write_data[31:0]={native_write[7:0],native_write[15:8],native_write[23:16],native_write[31:24]};
    end
    always @*begin
        cfg_rdata=0;known=1;writable=0;
        case(ofs)
            0:cfg_rdata={SOURCE_ID,16'h0103};
            4:begin cfg_rdata={31'd0,enabled};writable=1;end
            8:begin
                cfg_rdata[0]=enabled;cfg_rdata[1]=online;cfg_rdata[2]=pending;
                cfg_rdata[3]=state!=OFF && state!=IDLE;cfg_rdata[4]=online;cfg_rdata[5]=afull;
                cfg_rdata[6]=errors[2];cfg_rdata[7]=|errors;cfg_rdata[8]=time_sync_valid;
            end
            12:begin cfg_rdata=errors;writable=1;end
            16:begin cfg_rdata=baud;writable=1;end
            20:begin cfg_rdata=slave;writable=1;end
            24:begin cfg_rdata=HMP ? serial_format : 0;writable=1;end
            28:begin cfg_rdata=HMP ? interval_ms : channel;writable=1;end
            32:begin cfg_rdata=HMP ? meas_mask : shadow_value;writable=1;end
            36:cfg_rdata=HMP ? rh_bits : actual_uc;
            40:cfg_rdata=HMP ? temp_bits : device_error;
            44:begin cfg_rdata=HMP ? crc_errors : interval_ms;writable=!HMP;end
            48:cfg_rdata=HMP ? timeout_count : crc_errors;
            52:begin cfg_rdata=HMP ? shadow_value : timeout_count;writable=HMP;end
            56:cfg_rdata=fifo_level;
            60:cfg_rdata=drop_count;
            64:cfg_rdata=active_value;
            68:cfg_rdata=frame_count;
            72:cfg_rdata=write_count;
            default:known=0;
        endcase
        cfg_error=0;
        if(cfg_valid && hit)begin
            cfg_error=!known || |cfg_addr[1:0] || (cfg_write && !writable);
            if(cfg_write)case(ofs)
                4:begin
                    if(|(cfg_wdata & mask & 32'hfffffff0))cfg_error=1;
                    if(cfg_wstrb[0] && cfg_wdata[2] && pending)cfg_error=1;
                end
                16:if((SHARED_BUS && merged!=19200) || enabled || merged<1200 || merged>115200 || merged>SYS_CLK_HZ/16)cfg_error=1;
                20:if(enabled || merged==0 || merged>247)cfg_error=1;
                24:if((SHARED_BUS && merged!=0) || enabled || (HMP ? merged>5 : merged!=0))cfg_error=1;
                28:if(enabled || (HMP ? merged==0 || merged>3600000 : merged==0 || merged>2))cfg_error=1;
                32:if(HMP)begin if(enabled || merged==0 || merged>3)cfg_error=1;end
                    else if($signed(merged)<-32'sd400000000 || $signed(merged)>32'sd1000000000 || $signed(merged)%10!=0)cfg_error=1;
                44:if(!HMP && (enabled || merged==0 || merged>3600000))cfg_error=1;
                52:if(HMP && (merged[31] || merged[30:23]==255 || merged[30:0]==0))cfg_error=1;
                default:begin end
            endcase
        end
    end
    modbus_rtu_master #(.SYS_CLK_HZ(SYS_CLK_HZ),.SHARED_BUS(SHARED_BUS)) transport(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(enabled),.baud_hz(baud),.parity_mode(parity),.stop_bits(stops),
        .req_valid(req_valid),.req_ready(req_ready),.req_slave(slave[7:0]),.req_function(req_function),
        .req_address(req_address),.req_quantity(req_quantity),.req_write_data(write_data),.timeout_ms(16'd200),.retry_limit(2'd1),
        .timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),.done(done),.error(mb_error),.exception_code(exception_code),
        .read_data(read_data),.response_timestamp(response_timestamp),.response_time_sync(response_sync),
        .attempt_error_pulse(attempt_error_pulse),.attempt_error(attempt_error),
        .uart_rxd(uart_rxd),.uart_txd(uart_txd),.rs485_de(rs485_de),.busy(busy),.bus_request(bus_request),.bus_grant(bus_grant));
    assign bus_busy=busy;
    always @*begin
        next_record=0;cursor=4;tlvs=0;
        if(HMP)begin
            if(meas_mask[0])begin
                next_record[cursor*8+:32]={8'd4,`TLV_TYPE_F32_BITS,`TLV_TAG_HMP_RH_F32};
                next_record[(cursor+4)*8+:32]=rh_bits;cursor=cursor+8;tlvs=tlvs+1;
            end
            if(meas_mask[1])begin
                next_record[cursor*8+:32]={8'd4,`TLV_TYPE_F32_BITS,`TLV_TAG_HMP_TEMP_F32};
                next_record[(cursor+4)*8+:32]=temp_bits;cursor=cursor+8;tlvs=tlvs+1;
            end
        end else begin
            next_record[cursor*8+:32]={8'd4,`TLV_TYPE_I32,`TLV_TAG_TARGET_TEMP_UC};
            next_record[(cursor+4)*8+:32]=active_value;cursor=cursor+8;tlvs=tlvs+1;
            if(actual_valid)begin
                next_record[cursor*8+:32]={8'd4,`TLV_TYPE_I32,`TLV_TAG_ACTUAL_TEMP_UC};
                next_record[(cursor+4)*8+:32]=actual_uc;cursor=cursor+8;tlvs=tlvs+1;
            end
        end
        next_record[cursor*8+:32]={8'd4,`TLV_TYPE_U32,`TLV_TAG_DEVICE_ERROR};
        next_record[(cursor+4)*8+:32]=device_error;cursor=cursor+8;tlvs=tlvs+1;
        next_record[15:0]=1;next_record[31:16]=tlvs;next_length=cursor;
    end
    sensor_record_fifo #(.SOURCE_ID(SOURCE_ID),.FIFO_DEPTH(FIFO_DEPTH)) records(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.clear_fifo(clear_fifo),.record_valid(record_valid),
        .record_data(record_data),.record_length(record_length),.record_msg_id(`MSG_SENSOR_TLV_RECORD),
        .record_timestamp(sample_timestamp),.record_flags(record_flags),.accepted(accepted),.drop_pulse(drop_pulse),
        .drop_count(drop_count),.fifo_level(fifo_level),.fifo_almost_full(afull),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags));
    always @(posedge sys_clk)begin
        if(!local_rst_n)begin
            state<=OFF;enabled<=0;pending<=0;baud<=HMP ? 19200 : 38400;slave<=HMP ? 240 : 1;
            serial_format<=HMP && !SHARED_BUS ? 1 : 0;channel<=1;interval_ms<=1000;meas_mask<=3;
            shadow_value<=HMP ? 32'h447d5000 : 32'd25000000;pending_value<=0;active_value<=0;
            rh_bits<=0;temp_bits<=0;actual_uc<=0;actual_valid<=0;device_error<=0;
            crc_errors<=0;timeout_count<=0;frame_count<=0;write_count<=0;ms_div<=0;elapsed_ms<=0;native_write<=0;
            sample_timestamp<=0;sample_sync<=0;record_valid<=0;record_data<=0;record_length<=0;record_flags<=0;
            online<=0;errors<=0;
        end else begin
            record_valid<=0;
            if(ms_tick)begin ms_div<=0;if(elapsed_ms<3600000)elapsed_ms<=elapsed_ms+1'b1;end else ms_div<=ms_div+1'b1;
            if(access && cfg_error)errors<=errors|`ERR_CONFIG_RANGE;
            if(write_fire)case(ofs)
                4:if(cfg_wstrb[0])enabled<=cfg_wdata[0];
                12:errors<=errors & ~(cfg_wdata & mask);
                16:baud<=merged;20:slave<=merged;24:if(HMP)serial_format<=merged;
                28:if(HMP)interval_ms<=merged;else channel<=merged;
                32:if(HMP)meas_mask<=merged;else shadow_value<=merged;
                44:if(!HMP)interval_ms<=merged;
                52:if(HMP)shadow_value<=merged;
                default:begin end
            endcase
            if(commit)begin pending<=1;pending_value<=shadow_value;native_write<=$signed(shadow_value)/10;end
            if(!enabled)begin state<=OFF;online<=0;elapsed_ms<=0;end
            else case(state)
                OFF:begin state<=IDLE;elapsed_ms<=interval_ms;end
                IDLE:if(pending)state<=WRITE_REQ;
                    else if(elapsed_ms>=interval_ms)state<=HMP ? MEAS_REQ : TARGET_REQ;
                WRITE_REQ:if(req_ready)state<=WRITE_WAIT;
                WRITE_WAIT:if(done)begin
                    pending<=0;
                    if(mb_error==0)begin active_value<=pending_value;write_count<=write_count+1'b1;online<=1;end
                    state<=IDLE;elapsed_ms<=interval_ms;
                end
                TARGET_REQ:if(req_ready)state<=TARGET_WAIT;
                TARGET_WAIT:if(done)begin
                    if(mb_error==0 && native_valid)begin active_value<=uc_product[31:0];state<=MEAS_REQ;end
                    else begin state<=IDLE;elapsed_ms<=0;if(mb_error==0)errors[7]<=1;end
                end
                MEAS_REQ:if(req_ready)state<=MEAS_WAIT;
                MEAS_WAIT:if(done)begin
                    if(mb_error==0)begin
                        sample_timestamp<=response_timestamp;sample_sync<=response_sync;online<=1;
                        if(HMP)begin
                            rh_bits<=hmp_rh;temp_bits<=hmp_temp;
                            device_error<=((meas_mask[0] && hmp_rh[30:23]==255)||(meas_mask[1] && hmp_temp[30:23]==255)) ? 1 : 0;
                            if((meas_mask[0] && hmp_rh[30:23]==255)||(meas_mask[1] && hmp_temp[30:23]==255))errors[6]<=1;
                            state<=EMIT;
                        end else begin
                            actual_valid<=native_valid;if(native_valid)actual_uc<=uc_product[31:0];else errors[7]<=1;
                            state<=ERROR_REQ;
                        end
                    end else begin state<=IDLE;elapsed_ms<=0;end
                end
                ERROR_REQ:if(req_ready)state<=ERROR_WAIT;
                ERROR_WAIT:if(done)begin
                    if(mb_error==0)begin
                        device_error<={16'd0,read_data[7:0],read_data[15:8]};
                        if(|read_data[15:0])errors[6]<=1;
                        state<=EMIT;
                    end else begin state<=IDLE;elapsed_ms<=0;end
                end
                EMIT:begin
                    record_data<=next_record;record_length<=next_length;record_valid<=1;
                    record_flags<=32'd1|(sample_sync ? 32'd4 : 0)|((device_error!=0 || (!HMP && !actual_valid)) ? 32'd16 : 0);
                    frame_count<=frame_count+1'b1;state<=IDLE;elapsed_ms<=0;
                end
                default:state<=OFF;
            endcase
            if(attempt_error_pulse)begin
                if(attempt_error==1)begin timeout_count<=timeout_count+1'b1;errors[0]<=1;end
                else begin errors[1]<=1;if(attempt_error==2)crc_errors<=crc_errors+1'b1;end
            end
            if(done && mb_error!=0)begin online<=0;if(mb_error==4)errors[6]<=1;end
            if(drop_pulse)errors[2]<=1;
        end
    end
    always @*begin
        cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_ready && cfg_error)begin
            cfg_error_code=`SENSOR_CFG_RANGE;
            if(!known || cfg_addr[1:0]!=0)cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;
            else if(cfg_write && !writable)cfg_error_code=`SENSOR_CFG_READ_ONLY;
            else if(cfg_write)case(ofs)
                4:if(!(cfg_wdata & mask & 32'hfffffff0) && cfg_wstrb[0] && cfg_wdata[2] && pending)
                    cfg_error_code=`SENSOR_CFG_BUSY;
                16:if(enabled && merged>=1200 && merged<=115200 && merged<=SYS_CLK_HZ/16 && (!SHARED_BUS || merged==19200))
                    cfg_error_code=`SENSOR_CFG_BUSY;
                20:if(enabled && merged!=0 && merged<=247)cfg_error_code=`SENSOR_CFG_BUSY;
                24:if(enabled && (HMP ? merged<=5 : merged==0) && (!SHARED_BUS || merged==0))cfg_error_code=`SENSOR_CFG_BUSY;
                28:if(enabled && (HMP ? merged!=0 && merged<=3600000 : merged!=0 && merged<=2))
                    cfg_error_code=`SENSOR_CFG_BUSY;
                32:if(HMP && enabled && merged!=0 && merged<=3)cfg_error_code=`SENSOR_CFG_BUSY;
                44:if(!HMP && enabled && merged!=0 && merged<=3600000)cfg_error_code=`SENSOR_CFG_BUSY;
                default:;
            endcase
        end
    end

endmodule
`default_nettype wire
