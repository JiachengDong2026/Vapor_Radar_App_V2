`include "sensor_cfg_codes.vh"
`include "project_defs.vh"
`include "error_codes.vh"
module epsilon_rs232 #(
    parameter integer SYS_CLK_HZ=100000000,FIFO_DEPTH=256,
    parameter integer PASSIVE_MS=2500,RESPONSE_MS=500,QUIET_MS=50,ONLINE_MS=2500,
    parameter integer RECOVERY_ENABLE=1
)(
    input wire sys_clk,rst_sys_n,uart_rxd,output wire uart_txd,
    input wire [63:0] timestamp_now,input wire time_sync_valid,input wire [31:0] time_sync_seq,
    input wire sync_event_pulse,
    output reg [63:0] gnss_time_tag,output reg gnss_time_tag_valid,
    input wire cfg_valid,cfg_write,input wire [31:0] cfg_addr,cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg [31:0] cfg_rdata,output reg cfg_error,
    output wire m_valid,input wire m_ready,output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,m_last,output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,m_flags,
    output reg online,output reg [31:0] errors,output wire [31:0] drop_count,fifo_level,
    output wire [31:0] debug_rx_bytes,debug_good_frames,debug_crc_errors,
    output wire [3:0] debug_probe_state,output wire [15:0] debug_attempts,
    output reg nav_valid,output reg [815:0] nav_payload,output reg [63:0] nav_timestamp,
    output reg [3:0] cfg_error_code
);
    reg enabled,soft_reset,clear_fifo,forward_enable,utc_initialized;
    reg [31:0] baud,mask_lo,mask_hi,good_frames,crc_errors,sync_events;
    reg [7:0] last_id,id,length,crc8_value,crc16_hi,crc16_lo;
    reg [15:0] crc16_value;
    reg [8:0] position;
    reg [31:0] gap_count;
    reg [31:0] offline_count;
    reg [31:0] rx_bytes;
    localparam integer ONLINE_TICKS=(SYS_CLK_HZ/1000)*ONLINE_MS;
    reg [2175:0] frame,record_data;
    reg [8:0] record_length;
    reg record_valid;
    reg [63:0] byte_time,frame_time;
    reg byte_sync,frame_sync;
    wire byte_valid,byte_start,framing_error,parity_error,rx_busy;
    wire [7:0] byte_data;
    wire selected=cfg_addr[31:8]==24'h000062;
    wire [7:0] offset=cfg_addr[7:0];
    wire access=cfg_valid&&selected;
    wire write_fire=access&&cfg_write&&!cfg_error;
    wire local_rst_n=rst_sys_n&&!soft_reset;
    wire accepted,drop_pulse,afull;
    reg [31:0] mask,merged;
    integer j;
    function [7:0] crc8_step;
        input [7:0] previous,data;
        reg [7:0] c;integer n;
        begin c=previous^data;for(n=0;n<8;n=n+1)c=c[0]?(c>>1)^8'h8c:c>>1;crc8_step=c;end
    endfunction
    function [15:0] crc16_step;
        input [15:0] previous;input [7:0] data;
        reg [15:0] c;integer n;
        begin c=previous^{data,8'd0};for(n=0;n<8;n=n+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc16_step=c;end
    endfunction
    wire filter_match=id>=8'h40&&id<=8'h7f&&((id<8'h60)?mask_lo[id-8'h40]:mask_hi[id-8'h60]);
    // Payload is little endian; FDILink CRC16 wire order is high byte first.
    wire [31:0] utc_seconds=(id==8'h50)?frame[(7+6)*8+:32]:frame[7*8+:32];
    wire [31:0] utc_us=(id==8'h50)?frame[(7+10)*8+:32]:frame[(7+4)*8+:32];
    wire utc_frame=(id==8'h50&&length==102&&frame[(7+2)*8+3])||
        (id==8'h51&&length==8&&utc_initialized)||(id==8'h59&&length==74&&frame[(7+72)*8+5]);
    wire utc_range=utc_seconds>=32'd946684800&&utc_us<1000000;
    wire recovery_busy;
    // Health is based on any CRC-correct FDILink frame, independent of forwarding.
    wire recovery_good_frame=enabled && byte_valid && !framing_error && !parity_error &&
        position>=7 && position==({1'b0,length}+9'd7) && byte_data==8'hfd &&
        crc16_value=={crc16_hi,crc16_lo};
    assign debug_rx_bytes=rx_bytes;
    assign debug_good_frames=good_frames;
    assign debug_crc_errors=crc_errors;
    generate if (RECOVERY_ENABLE != 0) begin : g_recovery
    epsilon_link_recovery #(.SYS_CLK_HZ(SYS_CLK_HZ),.PASSIVE_MS(PASSIVE_MS),
        .RESPONSE_MS(RESPONSE_MS),.QUIET_MS(QUIET_MS)) u_recovery(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(enabled),.baud_hz(baud),
        .rx_valid(byte_valid && !framing_error && !parity_error),.rx_data(byte_data),
        .good_frame(recovery_good_frame),.txd(uart_txd),.busy(recovery_busy),
        .debug_state(debug_probe_state),.attempts(debug_attempts));
    end else begin : g_passive
        // CON14 debug uses the physical TX line; the sensor is receive-only.
        assign uart_txd = 1'b1;
        assign recovery_busy = 1'b0;
        assign debug_probe_state = !enabled ? 4'd0 : online ? 4'd9 : 4'd1;
        assign debug_attempts = 16'd0;
    end endgenerate
    assign cfg_ready=access;
    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ))u_rx(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(enabled || recovery_busy),.baud_hz(baud),
        .data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),.rxd(uart_rxd),
        .byte_valid(byte_valid),.byte_ready(1'b1),.byte_data(byte_data),.byte_start_pulse(byte_start),
        .framing_error_pulse(framing_error),.parity_error_pulse(parity_error),.busy(rx_busy));
    sensor_record_fifo #(.SOURCE_ID(`SRC_EPSILON2),.FIFO_DEPTH(FIFO_DEPTH))u_records(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.clear_fifo(clear_fifo),
        .record_valid(record_valid),.record_data(record_data),.record_length(record_length),
        .record_msg_id(`MSG_GNSS_FDILINK_RAW),.record_timestamp(frame_time),.record_flags(32'd1|(frame_sync?32'd4:0)),
        .accepted(accepted),.drop_pulse(drop_pulse),.drop_count(drop_count),.fifo_level(fifo_level),.fifo_almost_full(afull),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),
        .m_source_id(m_source_id),.m_msg_id(m_msg_id),.m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags));
    always @*begin
        cfg_rdata=0;cfg_error=0;mask=0;
        for(j=0;j<4;j=j+1)mask[j*8+:8]={8{cfg_wstrb[j]}};
        case(offset)
            0:cfg_rdata={`SRC_EPSILON2,16'h0101};4:cfg_rdata={31'd0,enabled};
            8:cfg_rdata={23'd0,time_sync_valid,(|errors),errors[2],afull,online,(position!=0),1'b0,enabled,enabled};
            12:cfg_rdata=errors;16:cfg_rdata=baud;20:cfg_rdata=mask_lo;24:cfg_rdata=mask_hi;
            28:cfg_rdata=forward_enable;32:cfg_rdata=good_frames;36:cfg_rdata=crc_errors;
            40:cfg_rdata=sync_events;44:cfg_rdata=last_id;48:cfg_rdata=gnss_time_tag[31:0];
            52:cfg_rdata=gnss_time_tag[63:32];56:cfg_rdata=fifo_level;60:cfg_rdata=drop_count;
            default:cfg_error=1;
        endcase
        merged=(cfg_rdata&~mask)|(cfg_wdata&mask);
        if(cfg_addr[1:0]!=0)cfg_error=1;
        if(cfg_write)case(offset)
            4:if(merged>15)cfg_error=1;
            12,20,24:;
            16:if(enabled||recovery_busy||merged<9600||merged>SYS_CLK_HZ/16)cfg_error=1;
            28:if(merged>1)cfg_error=1;
            default:cfg_error=1;
        endcase
        if(!access)begin cfg_error=0;cfg_rdata=0;end
    end
    always @(posedge sys_clk)begin
        if(!rst_sys_n)begin soft_reset<=0;clear_fifo<=0;end
        else begin
            soft_reset<=write_fire&&offset==4&&cfg_wstrb[0]&&cfg_wdata[1];
            clear_fifo<=write_fire&&offset==4&&cfg_wstrb[0]&&cfg_wdata[3];
        end
    end
    always @(posedge sys_clk)begin
        if(!local_rst_n)begin
            enabled<=0;forward_enable<=1;utc_initialized<=0;baud<=921600;mask_lo<=32'hffffffff;mask_hi<=32'hffffffff;
            good_frames<=0;crc_errors<=0;rx_bytes<=0;sync_events<=0;last_id<=0;id<=0;length<=0;
            crc8_value<=0;crc16_value<=0;crc16_hi<=0;crc16_lo<=0;position<=0;gap_count<=0;offline_count<=0;
            frame<=0;record_data<=0;record_length<=0;record_valid<=0;byte_time<=0;frame_time<=0;
            byte_sync<=0;frame_sync<=0;online<=0;errors<=0;gnss_time_tag<=0;gnss_time_tag_valid<=0;
            nav_valid<=0;nav_payload<=0;nav_timestamp<=0;
        end else begin
            record_valid<=0;gnss_time_tag_valid<=0;nav_valid<=0;
            if(byte_valid) rx_bytes<=rx_bytes+1'b1;
            if(!enabled)offline_count<=0;
            else if(offline_count<ONLINE_TICKS)offline_count<=offline_count+1'b1;
            else begin online<=0;utc_initialized<=0;errors[0]<=1;end
            if(access&&cfg_write&&cfg_error)errors[4]<=1;
            if(write_fire)case(offset)
                4:enabled<=merged[0];12:errors<=errors&~(cfg_wdata&mask);16:baud<=merged;
                20:mask_lo<=merged;24:mask_hi<=merged;28:forward_enable<=merged[0];default:;
            endcase
            if(sync_event_pulse&&enabled)sync_events<=sync_events+1'b1;
            if(drop_pulse)errors[2]<=1;
            if(byte_start)begin byte_time<=timestamp_now;byte_sync<=time_sync_valid;end
            if(!enabled)begin position<=0;gap_count<=0;online<=0;utc_initialized<=0;end
            else if(framing_error||parity_error)begin position<=0;errors[1]<=1;end
            else if(byte_valid)begin
                gap_count<=0;
                if(position==0)begin
                    if(byte_data==8'hfc)begin
                        frame<=0;frame[7:0]<=8'hfc;position<=1;crc8_value<=crc8_step(0,8'hfc);
                        crc16_value<=0;frame_time<=byte_time;frame_sync<=byte_sync;
                    end
                end else begin
                    frame[position*8+:8]<=byte_data;
                    if(position<4)begin
                        crc8_value<=crc8_step(crc8_value,byte_data);position<=position+1'b1;
                        if(position==1)id<=byte_data;
                        if(position==2)begin length<=byte_data;if(byte_data==0)begin position<=0;errors[7]<=1;end end
                    end else if(position==4)begin
                        if(byte_data!=crc8_value)begin position<=0;crc_errors<=crc_errors+1'b1;errors[1]<=1;end
                        else position<=5;
                    end else if(position==5)begin crc16_hi<=byte_data;position<=6;end
                    else if(position==6)begin crc16_lo<=byte_data;position<=7;end
                    else if(position<length+7)begin crc16_value<=crc16_step(crc16_value,byte_data);position<=position+1'b1;end
                    else begin
                        position<=0;
                        if(byte_data!=8'hfd||crc16_value!={crc16_hi,crc16_lo})begin crc_errors<=crc_errors+1'b1;errors[1]<=1;end
                        else begin
                            good_frames<=good_frames+1'b1;last_id<=id;online<=1;offline_count<=0;
                            // Publish only a complete CRC-checked navigation payload.
                            // This tap is independent of raw forwarding and ID masks.
                            if(id==8'h50&&length==102)begin
                                nav_payload<=frame[7*8+:816];nav_timestamp<=frame_time;nav_valid<=1;
                            end
                            if((id==8'h50&&length==102)||(id==8'h53&&length==4))utc_initialized<=frame[(7+2)*8+3];
                            if(utc_frame&&utc_range)begin gnss_time_tag<=utc_seconds*64'd1000000+utc_us;gnss_time_tag_valid<=1;end
                            if(forward_enable&&filter_match)begin
                                record_data<=frame;record_data[position*8+:8]<=8'hfd;
                                record_length<={1'b0,length}+9'd8;record_valid<=1;
                            end
                        end
                    end
                end
            end else if(position!=0)begin
                if(gap_count>=SYS_CLK_HZ/100-1)begin position<=0;errors[0]<=1;online<=0;end
                else gap_count<=gap_count+1'b1;
            end
        end
    end
    always @* begin
        cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_ready && cfg_error)begin
            cfg_error_code=`SENSOR_CFG_RANGE;
            if(cfg_addr[1:0]!=0 || offset>8'h3c)cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;
            else if(cfg_write)case(offset)
                4,12,20,24,28:;
                16:if((enabled || recovery_busy) && merged>=9600 && merged<=SYS_CLK_HZ/16)cfg_error_code=`SENSOR_CFG_BUSY;
                default:cfg_error_code=`SENSOR_CFG_READ_ONLY;
            endcase
        end
    end

endmodule
