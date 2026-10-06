`timescale 1ns/1ps
// One readable diagnostic line per accepted beat. UART has no host flow control.
module msg_stream_hex_uart #(
    parameter integer SYS_CLK_HZ=25000000,BAUD_HZ=115200
)(
    input wire sys_clk,rst_sys_n,
    input wire s_valid,output wire s_ready,
    input wire [31:0] s_data,s_flags,input wire [3:0] s_keep,
    input wire s_sof,s_last,input wire [15:0] s_source_id,s_msg_id,
    input wire [63:0] s_timestamp,output wire txd
);
    reg active;
    reg [6:0] index;
    reg [31:0] data,flags;reg [3:0] keep;reg sof,last;
    reg [15:0] source_id,msg_id;reg [63:0] timestamp;
    wire tx_ready,busy,done;reg [7:0] character;
    function [7:0] hex;input [3:0] nibble;begin hex=nibble<10?8'd48+nibble:8'd55+nibble;end endfunction
    assign s_ready=!active;
    always @*begin
        character=" ";
        case(index)
            0:character="S";1:character="R";2:character="C";3:character="=";
            9:character="M";10:character="S";11:character="G";12:character="=";
            18:character="T";19:character="=";
            37:character="D";38:character="=";
            48:character="F";49:character="=";
            59:character="K";60:character="=";61:character=hex(keep);
            63:character="S";64:character="=";65:character=sof?"1":"0";
            67:character="L";68:character="=";69:character=last?"1":"0";
            70:character=13;71:character=10;
            default:begin
                if(index>=4&&index<=7)character=hex(source_id>>((7-index)*4));
                else if(index>=13&&index<=16)character=hex(msg_id>>((16-index)*4));
                else if(index>=20&&index<=35)character=hex(timestamp>>((35-index)*4));
                else if(index>=39&&index<=46)character=hex(data>>((46-index)*4));
                else if(index>=50&&index<=57)character=hex(flags>>((57-index)*4));
            end
        endcase
    end
    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ))u_tx(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.enable(1'b1),.baud_hz(BAUD_HZ),
        .data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),.byte_valid(active),.byte_ready(tx_ready),
        .byte_data(character),.txd(txd),.busy(busy),.frame_done_pulse(done));
    always @(posedge sys_clk)begin
        if(!rst_sys_n)begin
            active<=0;index<=0;data<=0;flags<=0;keep<=0;sof<=0;last<=0;source_id<=0;msg_id<=0;timestamp<=0;
        end else begin
            if(s_valid&&s_ready)begin
                active<=1;index<=0;data<=s_data;flags<=s_flags;keep<=s_keep;
                sof<=s_sof;last<=s_last;source_id<=s_source_id;msg_id<=s_msg_id;timestamp<=s_timestamp;
            end
            if(active&&tx_ready)begin
                if(index==71)begin active<=0;index<=0;end else index<=index+1'b1;
            end
        end
    end
endmodule
