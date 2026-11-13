`include "sensor_cfg_codes.vh"
`include "register_map.vh"
`include "project_defs.vh"
`include "error_codes.vh"
`default_nettype none
module hc2a_roascii_uart #(
    parameter integer SYS_CLK_HZ=100000000,
    parameter integer FIFO_DEPTH=256,
    parameter integer DEFAULT_ADDRESS=99
)(
    input wire sys_clk,rst_sys_n,input wire uart_rxd,output wire uart_txd,
    input wire [63:0] timestamp_now,input wire time_sync_valid,input wire [31:0] time_sync_seq,
    input wire cfg_valid,cfg_write,input wire [31:0] cfg_addr,cfg_wdata,input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg [31:0] cfg_rdata,output reg cfg_error,
    output wire m_valid,input wire m_ready,output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,m_last,output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,output wire [31:0] m_cycle_id,m_flags,
    output reg online,output reg [31:0] errors,output wire [31:0] drop_count,fifo_level,
    output reg [3:0] cfg_error_code
);
    localparam [23:0] PAGE=24'h000061;
    localparam [7:0] OFF=0,IDLE=1,TX_START=2,SEND=4,TX_WAIT=5,
        RX_WAIT=6,QUIET=7,PARSE=8,EMIT=9,RETRY_QUIET=10;
    localparam integer RX_MAX=160;
    reg [3:0] state;
    reg enabled;
    reg [31:0] baud,address,interval_ms,measurement_mask;
    reg [31:0] ms_div,elapsed_ms,response_ms,quiet_ms;
    reg [3:0] retry_count;
    reg [3:0] tx_index;
    reg tx_finished;
    reg [7:0] rx_buffer[0:RX_MAX-1];
    reg [7:0] rx_count,rx_length;
    reg rx_overflow,rx_framing_error,rx_seen;
    reg [31:0] timeout_count,checksum_errors,format_errors,frame_count;
    // Read-only diagnostics; snapshot only complete CR-terminated UART input.
    reg [7:0] debug_buffer[0:RX_MAX-1];
    reg [31:0] debug_rx_total,debug_uart_errors,debug_snapshot_info,debug_failure;
    integer debug_i;
    reg [31:0] rh_bits,temp_bits,device_error;
    reg [63:0] sample_timestamp;
    reg sample_sync;
    reg record_valid;
    reg [2175:0] record_data;
    reg [8:0] record_length;
    reg [31:0] record_flags;
    reg [7:0] parse_index,field_index;
    reg [31:0] checksum_sum,parse_value;
    reg [7:0] parse_digits,parse_fraction_digits;
    reg parse_dot,parse_negative,parse_sign,parse_valid,parse_trailing;
    reg parse_data_bad,rh_field_valid,temp_field_valid;
    reg [31:0] unit_text;
    reg [3:0] unit_length;
    reg signed [31:0] humidity_x100,temperature_x100;
    reg humidity_alarm,temperature_alarm;
    reg [7:0] parsed_device_alarm;
    wire [31:0] byte_mask={{8{cfg_wstrb[3]}},{8{cfg_wstrb[2]}},{8{cfg_wstrb[1]}},{8{cfg_wstrb[0]}}};
    wire [31:0] merged_value=(cfg_rdata & ~byte_mask)|(cfg_wdata & byte_mask);
    wire [7:0] cfg_offset=cfg_addr[7:0];
    wire page_hit=cfg_addr[31:8]==PAGE;
    wire response_address_digits=(rx_buffer[2]>=8'h30 && rx_buffer[2]<=8'h39 &&
                                  rx_buffer[3]>=8'h30 && rx_buffer[3]<=8'h39);
    wire [7:0] response_address_value=(rx_buffer[2]-8'h30)*8'd10+(rx_buffer[3]-8'h30);
    wire response_address_match=(address==99) ?
        (response_address_digits && response_address_value<=64) :
        (response_address_digits && response_address_value==address);
    wire cfg_access=cfg_valid && cfg_ready;
    wire write_fire=cfg_access && cfg_write && !cfg_error;
    wire local_rst_n=rst_sys_n && !(write_fire && cfg_offset==8'h04 && cfg_wstrb[0] && cfg_wdata[1]);
    wire clear_fifo=write_fire && cfg_offset==8'h04 && cfg_wstrb[0] && cfg_wdata[3];
    wire ms_tick=ms_div==SYS_CLK_HZ/1000-1;
    wire [7:0] tx_byte;
    wire tx_byte_valid,tx_byte_ready,tx_done;
    wire rx_byte_valid,rx_start,rx_frame_error,rx_parity_error,rx_busy;
    wire [7:0] rx_byte;
    wire [7:0] address_tens=8'h30+(address/10);
    wire [7:0] address_ones=8'h30+(address%10);
    wire [7:0] checksum_expected={2'b00,checksum_sum[5:0]}+8'h20;
    wire numeric_target=(field_index==0)||(field_index==1)||(field_index==3)||(field_index==5)||(field_index==7)||(field_index==18);
    wire decimal_target=(field_index==1)||(field_index==5);
    wire alarm_target=(field_index==3)||(field_index==7)||(field_index==18);
    wire fifo_almost_full;
    wire drop_pulse;
    reg [2175:0] next_record;
    reg [8:0] next_record_length;
    integer cursor,tlvs;

    assign cfg_ready=cfg_valid && page_hit;
    assign tx_byte_valid=(state==SEND);
    assign tx_byte=(tx_index==0) ? 8'h7b :
                   (tx_index==1) ? 8'h46 :
                   (tx_index==2) ? address_tens :
                   (tx_index==3) ? address_ones :
                   (tx_index==4) ? 8'h52 :
                   (tx_index==5) ? 8'h44 :
                   (tx_index==6) ? 8'h44 :
                   (tx_index==7) ? 8'h7d : 8'h0d;

    function [31:0] decimal_x100;
        input [31:0] magnitude;
        input [7:0] fractional_digits;
        input has_dot;
        input is_negative;
        reg [63:0] scaled;
        begin
            if (!has_dot) scaled={32'd0,magnitude}*64'd100;
            else if (fractional_digits==0) scaled={32'd0,magnitude}*64'd100;
            else if (fractional_digits==1) scaled={32'd0,magnitude}*64'd10;
            else scaled={32'd0,magnitude};
            if (scaled>64'h7fffffff) decimal_x100=32'h80000000;
            else if (is_negative) decimal_x100=~scaled[31:0]+1'b1;
            else decimal_x100=scaled[31:0];
        end
    endfunction

    function [31:0] decimal_to_f32;
        input signed [31:0] value_x100;
        reg sign_bit;
        reg [31:0] magnitude,q16,norm;
        reg [5:0] msb;
        reg [7:0] exponent;
        integer j;
        begin
            sign_bit=value_x100[31];
            magnitude=sign_bit ? (~value_x100+1'b1) : value_x100;
            if (magnitude==0) decimal_to_f32=0;
            else begin
                q16=(magnitude*32'd65536+32'd50)/32'd100;
                msb=0;
                for(j=0;j<32;j=j+1)if(q16[j])msb=j;
                if(msb>23)norm=q16>>(msb-23);else norm=q16<<(23-msb);
                exponent=msb+8'd111;
                decimal_to_f32={sign_bit,exponent,norm[22:0]};
            end
        end
    endfunction

    always @* begin
        cfg_rdata=0;
        cfg_error=0;
        case(cfg_offset)
            8'h00:cfg_rdata=`HC2A_ID_VERSION;
            8'h04:begin cfg_rdata={31'd0,enabled};end
            8'h08:begin
                cfg_rdata[0]=enabled;
                cfg_rdata[1]=online;
                cfg_rdata[2]=state==TX_START || state==SEND || state==TX_WAIT ||
                              state==RX_WAIT || state==QUIET || state==PARSE || state==RETRY_QUIET;
                cfg_rdata[3]=state!=OFF && state!=IDLE;
                cfg_rdata[4]=online;
                cfg_rdata[5]=fifo_almost_full;
                cfg_rdata[6]=errors[2];
                cfg_rdata[7]=|errors;
                cfg_rdata[8]=time_sync_valid;
            end
            8'h0c:cfg_rdata=errors;
            8'h10:cfg_rdata=baud;
            8'h14:cfg_rdata=address;
            8'h18:cfg_rdata=0;
            8'h1c:cfg_rdata=interval_ms;
            8'h20:cfg_rdata=measurement_mask;
            8'h24:cfg_rdata=rh_bits;
            8'h28:cfg_rdata=temp_bits;
            8'h2c:cfg_rdata=checksum_errors;
            8'h30:cfg_rdata=timeout_count;
            8'h34:cfg_rdata={24'd0,device_error[7:0]};
            8'h38:cfg_rdata=fifo_level;
            8'h3c:cfg_rdata=drop_count;
            8'h40:cfg_rdata={22'd0,temperature_alarm,humidity_alarm,parsed_device_alarm};
            8'h44:cfg_rdata=frame_count;
            8'h48:cfg_rdata=format_errors;
            `REG_HC2A_DEBUG_SIGNATURE:cfg_rdata=`HC2A_DEBUG_SIGNATURE;
            `REG_HC2A_DEBUG_RX_TOTAL:cfg_rdata=debug_rx_total;
            `REG_HC2A_DEBUG_UART_ERRORS:cfg_rdata=debug_uart_errors;
            `REG_HC2A_DEBUG_SNAPSHOT:cfg_rdata=debug_snapshot_info;
            `REG_HC2A_DEBUG_FAILURE:cfg_rdata=debug_failure;
            8'h60:cfg_rdata={debug_buffer[3],debug_buffer[2],debug_buffer[1],debug_buffer[0]};
            8'h64:cfg_rdata={debug_buffer[7],debug_buffer[6],debug_buffer[5],debug_buffer[4]};
            8'h68:cfg_rdata={debug_buffer[11],debug_buffer[10],debug_buffer[9],debug_buffer[8]};
            8'h6c:cfg_rdata={debug_buffer[15],debug_buffer[14],debug_buffer[13],debug_buffer[12]};
            8'h70:cfg_rdata={debug_buffer[19],debug_buffer[18],debug_buffer[17],debug_buffer[16]};
            8'h74:cfg_rdata={debug_buffer[23],debug_buffer[22],debug_buffer[21],debug_buffer[20]};
            8'h78:cfg_rdata={debug_buffer[27],debug_buffer[26],debug_buffer[25],debug_buffer[24]};
            8'h7c:cfg_rdata={debug_buffer[31],debug_buffer[30],debug_buffer[29],debug_buffer[28]};
            8'h80:cfg_rdata={debug_buffer[35],debug_buffer[34],debug_buffer[33],debug_buffer[32]};
            8'h84:cfg_rdata={debug_buffer[39],debug_buffer[38],debug_buffer[37],debug_buffer[36]};
            8'h88:cfg_rdata={debug_buffer[43],debug_buffer[42],debug_buffer[41],debug_buffer[40]};
            8'h8c:cfg_rdata={debug_buffer[47],debug_buffer[46],debug_buffer[45],debug_buffer[44]};
            8'h90:cfg_rdata={debug_buffer[51],debug_buffer[50],debug_buffer[49],debug_buffer[48]};
            8'h94:cfg_rdata={debug_buffer[55],debug_buffer[54],debug_buffer[53],debug_buffer[52]};
            8'h98:cfg_rdata={debug_buffer[59],debug_buffer[58],debug_buffer[57],debug_buffer[56]};
            8'h9c:cfg_rdata={debug_buffer[63],debug_buffer[62],debug_buffer[61],debug_buffer[60]};
            8'ha0:cfg_rdata={debug_buffer[67],debug_buffer[66],debug_buffer[65],debug_buffer[64]};
            8'ha4:cfg_rdata={debug_buffer[71],debug_buffer[70],debug_buffer[69],debug_buffer[68]};
            8'ha8:cfg_rdata={debug_buffer[75],debug_buffer[74],debug_buffer[73],debug_buffer[72]};
            8'hac:cfg_rdata={debug_buffer[79],debug_buffer[78],debug_buffer[77],debug_buffer[76]};
            8'hb0:cfg_rdata={debug_buffer[83],debug_buffer[82],debug_buffer[81],debug_buffer[80]};
            8'hb4:cfg_rdata={debug_buffer[87],debug_buffer[86],debug_buffer[85],debug_buffer[84]};
            8'hb8:cfg_rdata={debug_buffer[91],debug_buffer[90],debug_buffer[89],debug_buffer[88]};
            8'hbc:cfg_rdata={debug_buffer[95],debug_buffer[94],debug_buffer[93],debug_buffer[92]};
            8'hc0:cfg_rdata={debug_buffer[99],debug_buffer[98],debug_buffer[97],debug_buffer[96]};
            8'hc4:cfg_rdata={debug_buffer[103],debug_buffer[102],debug_buffer[101],debug_buffer[100]};
            8'hc8:cfg_rdata={debug_buffer[107],debug_buffer[106],debug_buffer[105],debug_buffer[104]};
            8'hcc:cfg_rdata={debug_buffer[111],debug_buffer[110],debug_buffer[109],debug_buffer[108]};
            8'hd0:cfg_rdata={debug_buffer[115],debug_buffer[114],debug_buffer[113],debug_buffer[112]};
            8'hd4:cfg_rdata={debug_buffer[119],debug_buffer[118],debug_buffer[117],debug_buffer[116]};
            8'hd8:cfg_rdata={debug_buffer[123],debug_buffer[122],debug_buffer[121],debug_buffer[120]};
            8'hdc:cfg_rdata={debug_buffer[127],debug_buffer[126],debug_buffer[125],debug_buffer[124]};
            8'he0:cfg_rdata={debug_buffer[131],debug_buffer[130],debug_buffer[129],debug_buffer[128]};
            8'he4:cfg_rdata={debug_buffer[135],debug_buffer[134],debug_buffer[133],debug_buffer[132]};
            8'he8:cfg_rdata={debug_buffer[139],debug_buffer[138],debug_buffer[137],debug_buffer[136]};
            8'hec:cfg_rdata={debug_buffer[143],debug_buffer[142],debug_buffer[141],debug_buffer[140]};
            8'hf0:cfg_rdata={debug_buffer[147],debug_buffer[146],debug_buffer[145],debug_buffer[144]};
            8'hf4:cfg_rdata={debug_buffer[151],debug_buffer[150],debug_buffer[149],debug_buffer[148]};
            8'hf8:cfg_rdata={debug_buffer[155],debug_buffer[154],debug_buffer[153],debug_buffer[152]};
            8'hfc:cfg_rdata={debug_buffer[159],debug_buffer[158],debug_buffer[157],debug_buffer[156]};
            default:begin end
        endcase
        if(cfg_valid && page_hit)begin
            case(cfg_offset)
                8'h00,8'h08,8'h24,8'h28,8'h2c,8'h30,8'h34,8'h38,8'h3c,8'h40,8'h44,8'h48:
                    if(cfg_write)cfg_error=1;
                8'h04:if(cfg_write && (|(cfg_wdata & byte_mask & 32'hfffffff4) ||
                    (cfg_wstrb[0] && cfg_wdata[2])))cfg_error=1;
                8'h0c:begin end
                8'h10:if(cfg_write && (enabled || merged_value<1200 || merged_value>115200 ||
                    merged_value>SYS_CLK_HZ/16))cfg_error=1;
                8'h14:if(cfg_write && (enabled || (merged_value>64 && merged_value!=99)))cfg_error=1;
                8'h18:if(cfg_write && (enabled || merged_value!=0))cfg_error=1;
                8'h1c:if(cfg_write && (enabled || merged_value<100 || merged_value>3600000))cfg_error=1;
                8'h20:if(cfg_write && (enabled || merged_value==0 || merged_value>3))cfg_error=1;
                default:if(cfg_offset<8'h4c || cfg_offset[1:0]!=0 || cfg_write)cfg_error=1;
            endcase
        end
    end

    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) tx(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(enabled),.baud_hz(baud),
        .data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),
        .byte_valid(tx_byte_valid),.byte_ready(tx_byte_ready),.byte_data(tx_byte),
        .txd(uart_txd),.busy(),.frame_done_pulse(tx_done));
    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) rx(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(enabled && state==RX_WAIT),
        .baud_hz(baud),.data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),.rxd(uart_rxd),
        .byte_valid(rx_byte_valid),.byte_ready(1'b1),.byte_data(rx_byte),.byte_start_pulse(rx_start),
        .framing_error_pulse(rx_frame_error),.parity_error_pulse(rx_parity_error),.busy(rx_busy));
    always @* begin
        next_record=0;cursor=4;tlvs=0;
        next_record[15:0]=16'd1;
        if(measurement_mask[0])begin
            next_record[cursor*8+:32]={8'd4,`TLV_TYPE_F32_BITS,`TLV_TAG_HMP_RH_F32};
            next_record[(cursor+4)*8+:32]=rh_bits;cursor=cursor+8;tlvs=tlvs+1;
        end
        if(measurement_mask[1])begin
            next_record[cursor*8+:32]={8'd4,`TLV_TYPE_F32_BITS,`TLV_TAG_HMP_TEMP_F32};
            next_record[(cursor+4)*8+:32]=temp_bits;cursor=cursor+8;tlvs=tlvs+1;
        end
        next_record[cursor*8+:32]={8'd4,`TLV_TYPE_U32,`TLV_TAG_DEVICE_ERROR};
        next_record[(cursor+4)*8+:32]=device_error;cursor=cursor+8;tlvs=tlvs+1;
        next_record[31:16]=tlvs;next_record_length=cursor;
    end

    sensor_record_fifo #(.SOURCE_ID(`SRC_HMP),.FIFO_DEPTH(FIFO_DEPTH)) records(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.clear_fifo(clear_fifo),
        .record_valid(record_valid),.record_data(record_data),.record_length(record_length),
        .record_msg_id(`MSG_SENSOR_TLV_RECORD),.record_timestamp(sample_timestamp),.record_flags(record_flags),
        .accepted(),.drop_pulse(drop_pulse),.drop_count(drop_count),.fifo_level(fifo_level),
        .fifo_almost_full(fifo_almost_full),.m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),
        .m_keep(m_keep),.m_sof(m_sof),.m_last(m_last),.m_source_id(m_source_id),.m_msg_id(m_msg_id),
        .m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags));

    task fail_attempt;
        input [1:0] reason;
        begin
            if(reason==0)debug_failure<=32'h00000001;
            else if(reason==1)debug_failure<=32'h00000002;
            else if(rx_length<16 || rx_overflow || rx_framing_error || rx_buffer[0]!=8'h7b ||
                    rx_buffer[1]!=8'h46 || !response_address_match ||
                    !((rx_buffer[4]==8'h72 || rx_buffer[4]==8'h52) &&
                      (rx_buffer[5]==8'h64 || rx_buffer[5]==8'h44) &&
                      (rx_buffer[6]==8'h64 || rx_buffer[6]==8'h44)))begin
                debug_failure<=(rx_length<16 ? 32'h4 : 0) |
                    (rx_overflow ? 32'h8 : 0) | (rx_framing_error ? 32'h10 : 0) |
                    (rx_buffer[0]!=8'h7b ? 32'h20 : 0) | (rx_buffer[1]!=8'h46 ? 32'h40 : 0) |
                    (!response_address_match ? 32'h80 : 0) |
                    (!((rx_buffer[4]==8'h72 || rx_buffer[4]==8'h52) &&
                       (rx_buffer[5]==8'h64 || rx_buffer[5]==8'h44) &&
                       (rx_buffer[6]==8'h64 || rx_buffer[6]==8'h44)) ? 32'h100 : 0);
            end else begin
                debug_failure<=(field_index!=19 ? 32'h200 : 0) |
                    (!rh_field_valid ? 32'h400 : 0) | (!temp_field_valid ? 32'h800 : 0) |
                    (parse_data_bad ? 32'h1000 : 0) |
                    ((humidity_x100<0 || humidity_x100>10000) ? 32'h2000 : 0) |
                    ((temperature_x100< -32'sd10000 || temperature_x100>32'sd60000) ? 32'h4000 : 0);
            end
            case(reason)
                2'd0:begin timeout_count<=timeout_count+1'b1;errors[0]<=1'b1;end
                2'd1:begin checksum_errors<=checksum_errors+1'b1;errors[1]<=1'b1;end
                default:begin format_errors<=format_errors+1'b1;errors[7]<=1'b1;end
            endcase
            if(retry_count==0)begin retry_count<=1;quiet_ms<=0;state<=RETRY_QUIET;end
            else begin state<=IDLE;elapsed_ms<=0;online<=0;end
        end
    endtask

    always @(posedge sys_clk) begin
        if(!local_rst_n)begin
            state<=OFF;enabled<=0;baud<=19200;address<=DEFAULT_ADDRESS;interval_ms<=1000;measurement_mask<=3;
            ms_div<=0;elapsed_ms<=0;response_ms<=0;quiet_ms<=0;retry_count<=0;tx_index<=0;tx_finished<=0;
            rx_count<=0;rx_length<=0;rx_overflow<=0;rx_framing_error<=0;rx_seen<=0;
            timeout_count<=0;checksum_errors<=0;format_errors<=0;frame_count<=0;
            debug_rx_total<=0;debug_uart_errors<=0;debug_snapshot_info<=0;debug_failure<=0;
            for(debug_i=0;debug_i<RX_MAX;debug_i=debug_i+1)debug_buffer[debug_i]<=0;
            rh_bits<=0;temp_bits<=0;device_error<=0;parsed_device_alarm<=0;
            sample_timestamp<=0;sample_sync<=0;record_valid<=0;record_data<=0;record_length<=0;record_flags<=0;
            parse_index<=0;field_index<=0;checksum_sum<=0;parse_value<=0;parse_digits<=0;parse_fraction_digits<=0;
            parse_dot<=0;parse_negative<=0;parse_sign<=0;parse_valid<=1;parse_trailing<=0;parse_data_bad<=0;
            unit_text<=0;unit_length<=0;
            rh_field_valid<=0;temp_field_valid<=0;humidity_x100<=0;temperature_x100<=0;
            humidity_alarm<=0;temperature_alarm<=0;parsed_device_alarm<=0;online<=0;errors<=0;
        end else begin
            record_valid<=0;
            if(rx_byte_valid)debug_rx_total<=debug_rx_total+1'b1;
            if(rx_frame_error || rx_parity_error)debug_uart_errors<=debug_uart_errors+1'b1;
            if(ms_tick)begin ms_div<=0;if(elapsed_ms<3600000)elapsed_ms<=elapsed_ms+1'b1;end
            else ms_div<=ms_div+1'b1;
            if(cfg_access && cfg_error)errors<=errors|`ERR_CONFIG_RANGE;
            if(write_fire)case(cfg_offset)
                8'h04:if(cfg_wstrb[0])enabled<=cfg_wdata[0];
                8'h0c:errors<=errors & ~(cfg_wdata & byte_mask);
                8'h10:baud<=merged_value;
                8'h14:address<=merged_value;
                8'h1c:interval_ms<=merged_value;
                8'h20:measurement_mask<=merged_value;
                default:begin end
            endcase
            if(!enabled)begin state<=OFF;online<=0;elapsed_ms<=0;end
            else case(state)
                OFF:begin state<=IDLE;elapsed_ms<=0;end
                IDLE:if(elapsed_ms>=interval_ms)begin
                    state<=TX_START;retry_count<=0;rx_count<=0;rx_length<=0;rx_overflow<=0;
                    rx_framing_error<=0;rx_seen<=0;tx_index<=0;tx_finished<=0;
                end
                TX_START:begin state<=SEND;tx_index<=0;end
                SEND:if(tx_byte_valid && tx_byte_ready)begin
                    if(tx_index==8)begin state<=TX_WAIT;tx_finished<=0;end
                    else tx_index<=tx_index+1'b1;
                end
                TX_WAIT:begin
                    if(tx_done)tx_finished<=1;
                    if(tx_finished)begin
                        state<=RX_WAIT;response_ms<=0;rx_count<=0;rx_length<=0;rx_seen<=0;
                    end
                end
                RX_WAIT:begin
                    if(ms_tick && response_ms<1000)response_ms<=response_ms+1'b1;
                    if(rx_start && !rx_seen)begin sample_timestamp<=timestamp_now;sample_sync<=time_sync_valid;rx_seen<=1;end
                    if(rx_frame_error || rx_parity_error)rx_framing_error<=1;
                    if(rx_byte_valid)begin
                        if(rx_byte==8'h0d)begin rx_length<=rx_count;quiet_ms<=0;state<=QUIET;end
                        else if(rx_count<RX_MAX-1)begin rx_buffer[rx_count]<=rx_byte;rx_count<=rx_count+1'b1;end
                        else rx_overflow<=1;
                    end else if(ms_tick && response_ms>=599)fail_attempt(2'd0);
                end
                QUIET:if(ms_tick)begin
                    if(quiet_ms>=1)begin
                        debug_snapshot_info<={1'b1,21'd0,rx_overflow,rx_framing_error,rx_length};
                        for(debug_i=0;debug_i<RX_MAX;debug_i=debug_i+1)begin
                            if(debug_i<rx_length)debug_buffer[debug_i]<=rx_buffer[debug_i];
                            else debug_buffer[debug_i]<=0;
                        end
                        // Header bytes are checked separately but also contribute to the checksum.
                        state<=PARSE;parse_index<=7;field_index<=0;
                        checksum_sum<=32'd0+rx_buffer[0]+rx_buffer[1]+rx_buffer[2]+rx_buffer[3]+
                                      rx_buffer[4]+rx_buffer[5]+rx_buffer[6];parse_value<=0;
                        parse_digits<=0;parse_fraction_digits<=0;parse_dot<=0;parse_negative<=0;parse_sign<=0;
                        unit_text<=0;unit_length<=0;
                        parse_valid<=1;parse_trailing<=0;parse_data_bad<=0;rh_field_valid<=0;temp_field_valid<=0;
                        humidity_x100<=0;temperature_x100<=0;humidity_alarm<=0;temperature_alarm<=0;parsed_device_alarm<=0;
                    end else quiet_ms<=quiet_ms+1'b1;
                end
                RETRY_QUIET:if(ms_tick)begin
                    if(quiet_ms>=1)begin state<=TX_START;rx_count<=0;rx_length<=0;rx_overflow<=0;rx_framing_error<=0;rx_seen<=0;end
                    else quiet_ms<=quiet_ms+1'b1;
                end
                PARSE:begin
                    if(rx_length<16 || rx_overflow || rx_framing_error || rx_buffer[0]!=8'h7b ||
                       rx_buffer[1]!=8'h46 || !response_address_match ||
                       !((rx_buffer[4]==8'h72 || rx_buffer[4]==8'h52) &&
                         (rx_buffer[5]==8'h64 || rx_buffer[5]==8'h44) &&
                         (rx_buffer[6]==8'h64 || rx_buffer[6]==8'h44)))begin
                        fail_attempt(2'd2);
                    end else if(parse_index<rx_length-1)begin
                        checksum_sum<=checksum_sum+rx_buffer[parse_index];
                        if(rx_buffer[parse_index]==8'h3b)begin
                            if(numeric_target)begin
                                if(!parse_valid || parse_digits==0 || parse_digits>7 || parse_fraction_digits>2 ||
                                   (parse_dot && parse_fraction_digits==0) ||
                                   (!decimal_target && (parse_dot || parse_sign)) ||
                                   (alarm_target && field_index!=18 && parse_value>1) ||
                                   (field_index==18 && parse_value>255))parse_data_bad<=1;
                                else if(field_index==0)begin
                                    if(parse_value!=1)parse_data_bad<=1;
                                end else if(field_index==1)begin
                                    humidity_x100<=decimal_x100(parse_value,parse_fraction_digits,parse_dot,parse_negative);
                                    rh_field_valid<=1;
                                end else if(field_index==3)begin
                                    if(parse_value!=0)humidity_alarm<=1;
                                end else if(field_index==5)begin
                                    temperature_x100<=decimal_x100(parse_value,parse_fraction_digits,parse_dot,parse_negative);
                                    temp_field_valid<=1;
                                end else if(field_index==7)begin
                                    if(parse_value!=0)temperature_alarm<=1;
                                end else if(field_index==18)parsed_device_alarm<=parse_value[7:0];
                            end
                            // HC2A V1.2-1 returns %rh; older HC2 examples use %RH.
                            if(field_index==2 && unit_text!=32'h00255248 && unit_text!=32'h00257268)parse_data_bad<=1;
                            if(field_index==6 && unit_text!=32'h43 && unit_text!=32'hb043 &&
                               unit_text!=32'hc2b043)parse_data_bad<=1;
                            field_index<=field_index+1'b1;parse_value<=0;parse_digits<=0;parse_fraction_digits<=0;
                            unit_text<=0;unit_length<=0;
                            parse_dot<=0;parse_negative<=0;parse_sign<=0;parse_valid<=1;parse_trailing<=0;
                        end else if(field_index==2 || field_index==6)begin
                            if(rx_buffer[parse_index]!=8'h20)begin
                                if(unit_length>=4)parse_data_bad<=1;
                                unit_text<={unit_text[23:0],rx_buffer[parse_index]};
                                unit_length<=unit_length+1'b1;
                            end
                        end else if(numeric_target)begin
                            if(rx_buffer[parse_index]>=8'h30 && rx_buffer[parse_index]<=8'h39)begin
                                if(parse_trailing)parse_valid<=0;
                                if(parse_digits>=7)parse_valid<=0;
                                parse_value<=parse_value*10+(rx_buffer[parse_index]-8'h30);
                                parse_digits<=parse_digits+1'b1;
                                if(parse_dot)parse_fraction_digits<=parse_fraction_digits+1'b1;
                            end else if(rx_buffer[parse_index]==8'h2e && decimal_target && !parse_dot && !parse_trailing)begin
                                parse_dot<=1;
                            end else if(rx_buffer[parse_index]==8'h2d && parse_digits==0 && !parse_dot && !parse_sign)begin
                                parse_negative<=1;parse_sign<=1;
                            end else if(rx_buffer[parse_index]==8'h2b && parse_digits==0 && !parse_dot && !parse_sign)begin
                                parse_sign<=1;
                            end else if(rx_buffer[parse_index]==8'h20 && parse_digits==0 && !parse_dot && !parse_sign)begin
                            end else if(rx_buffer[parse_index]==8'h20 && parse_digits!=0)begin
                                parse_trailing<=1;
                            end else parse_valid<=0;
                        end
                        parse_index<=parse_index+1'b1;
                    end else if(rx_buffer[rx_length-1]!==checksum_expected || field_index!=19 ||
                                !rh_field_valid || !temp_field_valid || parse_data_bad ||
                                humidity_x100<0 || humidity_x100>10000 ||
                                temperature_x100< -32'sd10000 || temperature_x100>32'sd60000)begin
                        if(rx_buffer[rx_length-1]!==checksum_expected)fail_attempt(2'd1);
                        else fail_attempt(2'd2);
                    end else begin
                        rh_bits<=decimal_to_f32(humidity_x100);
                        temp_bits<=decimal_to_f32(temperature_x100);
                        if(address==99)address<=response_address_value;
                        device_error<={24'd0,parsed_device_alarm};
                        online<=1;state<=EMIT;
                        if(parsed_device_alarm!=0 || humidity_alarm || temperature_alarm)errors[6]<=1;
                    end
                end
                EMIT:begin
                    record_data<=next_record;record_length<=next_record_length;
                    record_valid<=1;record_flags<=32'd1|(sample_sync?32'd4:0)|((device_error!=0 || humidity_alarm || temperature_alarm)?32'd16:0);
                    frame_count<=frame_count+1'b1;state<=IDLE;elapsed_ms<=0;retry_count<=0;
                end
                default:state<=OFF;
            endcase
            if(drop_pulse)errors[2]<=1;
        end
    end

    always @* begin
        cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_ready && cfg_error)begin
            cfg_error_code=`SENSOR_CFG_RANGE;
            if(cfg_offset[1:0]!=0)cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;
            else if(cfg_write && (cfg_offset==0 || cfg_offset==8 || cfg_offset==36 || cfg_offset==40 ||
                cfg_offset==44 || cfg_offset==48 || cfg_offset==52 || cfg_offset==56 || cfg_offset==60 ||
                cfg_offset==64 || cfg_offset==68 || cfg_offset==72 || cfg_offset>=76))cfg_error_code=`SENSOR_CFG_READ_ONLY;
            else if(cfg_write && enabled && (
                (cfg_offset==16 && merged_value>=1200 && merged_value<=115200 &&
                    merged_value<=SYS_CLK_HZ/16) ||
                (cfg_offset==20 && (merged_value<=64 || merged_value==99)) ||
                (cfg_offset==24 && merged_value==0) ||
                (cfg_offset==28 && merged_value>=100 && merged_value<=3600000) ||
                (cfg_offset==32 && merged_value!=0 && merged_value<=3)))cfg_error_code=`SENSOR_CFG_BUSY;
        end
    end
endmodule
`default_nettype wire
