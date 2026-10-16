`default_nettype none
// VLP READ/WRITE_REG mailbox. Staging, validation and physical TX are distinct:
// a cfg ACK never means that the receiver applied an EPSILON parameter.
module epsilon_command_mailbox #(
    parameter integer SYS_CLK_HZ=100000000, MAX_TX_BYTES=1029, MAX_RX_BYTES=2048
)(
    input wire clk,rst_n,enable,blocked,
    input wire [31:0] baud_hz,
    input wire cfg_valid,cfg_write,
    input wire [31:0] cfg_addr,cfg_wdata,
    input wire [3:0] cfg_wstrb,
    output wire cfg_ready,output reg cfg_error,
    output reg [31:0] cfg_rdata,output reg [3:0] cfg_error_code,
    input wire rx_valid,input wire [7:0] rx_data,
    output wire txd,correction_txd,output wire busy,output wire reserve_uart
);
    localparam IDLE=0,CHECK=1,SEND=2,REPLY=3,FDI_CRC=4;
    reg [2:0] state;
    reg [31:0] length,kind,loaded,timeout_ms,rx_index;
    reg [31:0] index,rx_length,timer,quiet_timer,bytes_sent,completed,failed;
    reg [7:0] result;
    reg result_valid,tx_pending,reply_started,rx_overflow;
    reg [23:0] crc;
    reg [31:0] target,correction_baud,rtcm_bytes,fragment_start;
    reg [7:0] fragment_length,tx_sequence;
    reg [8:0] wire_index;
    reg [15:0] fragment_crc;
    reg [7:0] send_byte;
    (* ram_style="block" *) reg [31:0] tx_words[0:(MAX_TX_BYTES+3)/4-1];
    reg [7:0] rx_bytes[0:MAX_RX_BYTES-1];
    wire hit=cfg_valid && cfg_addr[31:8]==24'h62 && cfg_addr[7:0]>=8'h40;
    wire [7:0] offset=cfg_addr[7:0];
    wire tx_ready,tx_done,tx_busy,uart_line;
    wire [7:0] tx_byte=tx_words[index>>2] >> (8*index[1:0]);
    wire start=hit && cfg_write && !cfg_error && offset==8'h40 && cfg_wdata==1;
    assign cfg_ready=hit;
    assign busy=state!=IDLE;
    // Also inhibit the automatic probe on the exact START edge.
    assign reserve_uart=busy || start;
    assign txd=target==0 ? uart_line : 1'b1;
    assign correction_txd=target==1 ? uart_line : 1'b1;
    wire fdilink=kind==1 && target==0;
    wire send_last=fdilink ? wire_index==fragment_length+7 : index==length-1;
    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) uart(
        .sys_clk(clk),.rst_sys_n(rst_n),.enable(1'b1),.baud_hz(target==0 ? baud_hz : correction_baud),
        .data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),
        .byte_valid(state==SEND && !tx_pending),.byte_ready(tx_ready),
        .byte_data(send_byte),.txd(uart_line),.busy(tx_busy),.frame_done_pulse(tx_done));
    function [7:0] crc8;
        input [7:0] previous,value;reg [7:0] v;integer b;
        begin v=previous^value;for(b=0;b<8;b=b+1)v=v[0]?(v>>1)^8'h8c:v>>1;crc8=v;end
    endfunction
    function [15:0] crc16;
        input [15:0] previous;input [7:0] value;reg [15:0] v;integer b;
        begin v=previous^{value,8'd0};for(b=0;b<8;b=b+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc16=v;end
    endfunction
    wire [31:0] payload_offset=fragment_start+wire_index-7;
    always @* begin
        send_byte=tx_byte;
        if(fdilink)case(wire_index)
            0:send_byte=8'hfc;
            1:send_byte=8'h73;
            2:send_byte=fragment_length;
            3:send_byte=tx_sequence;
            4:send_byte=crc8(crc8(crc8(crc8(0,8'hfc),8'h73),fragment_length),tx_sequence);
            5:send_byte=fragment_crc[15:8];
            6:send_byte=fragment_crc[7:0];
            default:begin
                if(wire_index==fragment_length+7)send_byte=8'hfd;
                else if(wire_index<fragment_length+7)
                    send_byte=tx_words[payload_offset>>2]>>(8*payload_offset[1:0]);
                else send_byte=0;
            end
        endcase
    end
    function [23:0] crc24q;
        input [23:0] previous;input [7:0] value;
        reg [23:0] v;integer b;
        begin
            v=previous^{value,16'd0};
            for(b=0;b<8;b=b+1)v=v[23]?(v<<1)^24'h864cfb:v<<1;
            crc24q=v;
        end
    endfunction
    always @* begin
        cfg_rdata=0;cfg_error=0;cfg_error_code=0;
        case(offset)
            8'h40:cfg_rdata=0;
            8'h44:cfg_rdata=length;
            8'h48:cfg_rdata=kind;
            8'h4c:cfg_rdata={14'd0,result_valid,busy,8'd0,result};
            8'h50:cfg_rdata=bytes_sent;
            8'h54:cfg_rdata=completed;
            8'h58:cfg_rdata=failed;
            8'h5c:cfg_rdata=rx_length;
            8'h60:cfg_rdata=rx_index;
            8'h64:begin
                if(rx_index<rx_length)cfg_rdata[7:0]=rx_bytes[rx_index];
                if(rx_index+1<rx_length)cfg_rdata[15:8]=rx_bytes[rx_index+1];
                if(rx_index+2<rx_length)cfg_rdata[23:16]=rx_bytes[rx_index+2];
                if(rx_index+3<rx_length)cfg_rdata[31:24]=rx_bytes[rx_index+3];
            end
            8'h68:cfg_rdata=0;
            8'h6c:cfg_rdata=loaded;
            8'h70:cfg_rdata=timeout_ms;
            8'h74:cfg_rdata=target;
            8'h78:cfg_rdata=correction_baud;
            8'h7c:cfg_rdata=rtcm_bytes;
            default:begin cfg_error=1;cfg_error_code=5;end
        endcase
        if(hit && |cfg_addr[1:0])begin cfg_error=1;cfg_error_code=5;end
        if(hit && cfg_write && !cfg_error)begin
            case(offset)
                8'h40:begin
                    if(cfg_wstrb!=15 || cfg_wdata!=1 || length==0 || loaded!=(length+3)/4)
                        begin cfg_error=1;cfg_error_code=7;end
                    else if(!enable || blocked || busy)begin cfg_error=1;cfg_error_code=8;end
                    else if(kind==0 && target!=0)begin cfg_error=1;cfg_error_code=7;end
                end
                8'h44:if(cfg_wstrb!=15 || cfg_wdata==0 || cfg_wdata>MAX_TX_BYTES)
                    begin cfg_error=1;cfg_error_code=7;end
                8'h48:if(cfg_wstrb!=15 || cfg_wdata>1)begin cfg_error=1;cfg_error_code=7;end
                8'h60:if(cfg_wstrb!=15 || cfg_wdata>=MAX_RX_BYTES || |cfg_wdata[1:0])
                    begin cfg_error=1;cfg_error_code=7;end
                8'h68:if(cfg_wstrb!=15 || length==0 || loaded>=(length+3)/4)
                    begin cfg_error=1;cfg_error_code=7;end
                8'h70:if(cfg_wstrb!=15 || cfg_wdata<100 || cfg_wdata>10000)
                    begin cfg_error=1;cfg_error_code=7;end
                8'h74:if(cfg_wstrb!=15 || cfg_wdata>1)begin cfg_error=1;cfg_error_code=7;end
                8'h78:if(cfg_wstrb!=15 || cfg_wdata<9600 || cfg_wdata>SYS_CLK_HZ/16)
                    begin cfg_error=1;cfg_error_code=7;end
                default:begin cfg_error=1;cfg_error_code=6;end
            endcase
            if(busy && !cfg_error)begin cfg_error=1;cfg_error_code=8;end
        end
        if(!hit)begin cfg_error=0;cfg_error_code=0;cfg_rdata=0;end
    end
    task finish;
        input [7:0] code;
        begin
            state<=IDLE;result<=code;result_valid<=1;loaded<=0;
            if(code==0)completed<=completed+1'b1;else failed<=failed+1'b1;
        end
    endtask
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;length<=0;kind<=0;loaded<=0;timeout_ms<=2000;rx_index<=0;
            index<=0;rx_length<=0;timer<=0;quiet_timer<=0;bytes_sent<=0;completed<=0;failed<=0;
            result<=0;result_valid<=0;tx_pending<=0;reply_started<=0;rx_overflow<=0;crc<=0;
            target<=0;correction_baud<=115200;rtcm_bytes<=0;fragment_start<=0;
            fragment_length<=0;tx_sequence<=0;wire_index<=0;fragment_crc<=0;
        end else begin
            if(hit && cfg_write && !cfg_error)case(offset)
                8'h44:begin length<=cfg_wdata;loaded<=0;end
                8'h48:kind<=cfg_wdata;
                8'h60:rx_index<=cfg_wdata;
                8'h68:begin tx_words[loaded]<=cfg_wdata;loaded<=loaded+1'b1;end
                8'h70:timeout_ms<=cfg_wdata;
                8'h74:target<=cfg_wdata;
                8'h78:correction_baud<=cfg_wdata;
                default:;
            endcase
            if(start)begin
                state<=CHECK;index<=0;crc<=0;result_valid<=0;result<=0;
                rx_length<=0;rx_index<=0;timer<=0;quiet_timer<=0;
                reply_started<=0;rx_overflow<=0;
            end
            // Never truncate a transmitted byte on disable. Complete this
            // staged frame, then report cancellation; nothing is retried.
            case(state)
                CHECK:begin
                    if(!enable)finish(4);
                    else if(kind==0)begin
                        // ASCII commands must be a complete MAIN command line.
                        if(tx_words[0][7:0]!="#" || length<3)finish(7);
                        else if(index==length-1)begin
                            if(tx_byte!=10)finish(7);else begin state<=SEND;index<=0;end
                        end else index<=index+1'b1;
                    end else begin
                        crc<=crc24q(crc,tx_byte);
                        if(index==0 && tx_byte!=8'hd3)finish(7);
                        else if(index==1 && |tx_byte[7:2])finish(7);
                        else if(index==2 && ({22'd0,tx_words[0][9:8],tx_byte}+6!=length))finish(7);
                        else if(index==length-1)begin
                            if(length<6 || crc24q(crc,tx_byte)!=0)finish(3);
                            else begin
                                index<=0;
                                if(target==0)begin
                                    state<=FDI_CRC;fragment_start<=0;fragment_length<=length>255 ? 255 : length;
                                    fragment_crc<=0;wire_index<=0;
                                end else state<=SEND;
                            end
                        end else index<=index+1'b1;
                    end
                end
                SEND:begin
                    if(tx_ready && !tx_pending)tx_pending<=1;
                    if(tx_done && tx_pending)begin
                        tx_pending<=0;bytes_sent<=bytes_sent+1'b1;
                        if(fdilink && send_last)tx_sequence<=tx_sequence+1'b1;
                        if(fdilink && send_last && fragment_start+fragment_length<length)begin
                            fragment_start<=fragment_start+fragment_length;index<=fragment_start+fragment_length;
                            fragment_length<=length-fragment_start-fragment_length>255 ? 255 : length-fragment_start-fragment_length;
                            fragment_crc<=0;wire_index<=0;state<=FDI_CRC;
                        end else if(send_last)begin
                            if(kind==1)rtcm_bytes<=rtcm_bytes+length;
                            if(!enable)finish(4);
                            else if(kind==1)finish(0);
                            else begin state<=REPLY;timer<=0;quiet_timer<=0;end
                        end else if(fdilink)wire_index<=wire_index+1'b1;
                        else index<=index+1'b1;
                    end
                end
                FDI_CRC:begin
                    fragment_crc<=crc16(fragment_crc,tx_byte);
                    if(index==fragment_start+fragment_length-1)begin state<=SEND;wire_index<=0;end
                    else index<=index+1'b1;
                end
                REPLY:begin
                    if(!enable)finish(4);
                    else if(timer>=(SYS_CLK_HZ/1000)*timeout_ms-1)finish(1);
                    else if(reply_started && quiet_timer>=SYS_CLK_HZ/20)finish(rx_overflow?8'd2:8'd0);
                    else begin
                        timer<=timer+1'b1;
                        if(rx_valid && (reply_started || rx_data=="#" || rx_data=="*"))begin
                            reply_started<=1;quiet_timer<=0;
                            if(rx_length<MAX_RX_BYTES)begin rx_bytes[rx_length]<=rx_data;rx_length<=rx_length+1'b1;end
                            else rx_overflow<=1;
                        end else quiet_timer<=quiet_timer+1'b1;
                    end
                end
                default:;
            endcase
        end
    end
endmodule
`default_nettype wire
