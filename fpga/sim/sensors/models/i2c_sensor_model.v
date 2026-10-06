`timescale 1ns/1ps
// Pin-level simulation device. Independent SCL edge receiver/transmitter.
module i2c_sensor_model #(
    parameter [6:0] ADDRESS=7'h44,
    parameter integer IS_BMP=0,
    parameter integer NS_PER_LOGICAL_MS=10000
)(
    input wire scl,inout wire sda,input wire rst_n,
    input wire inject_nack,inject_bad_crc,
    output reg [31:0] transactions,measurements,
    output reg [7:0] last_command
);
    localparam ADDRESS_RX=0,WRITE_RX=1,ACK=2,READ_TX=3,READ_ACK=4,IGNORE=5;
    integer state,next_state,bit_index,read_index,write_index;
    reg drive_low;
    reg [7:0] shift,tx_byte,reg_pointer;
    reg ack_value;
    reg [7:0] registers[0:255];
    integer k;
    time command_time;
    real minimum_ms;
    assign sda=drive_low?1'b0:1'bz;
    function [7:0] crc;
        input [15:0] d;
        reg [7:0] c;integer n;
        begin c=8'hff;for(n=15;n>=0;n=n-1)c=(c[7]^d[n])?(c<<1)^8'h31:c<<1;crc=c;end
    endfunction
    function [7:0] response_byte;
        input integer index;
        reg [15:0] w0,w1;
        begin
            if(IS_BMP)response_byte=registers[(reg_pointer+index)&255];
            else begin
                w0=last_command==8'h89 ?16'hbeef:16'h8000;
                w1=last_command==8'h89 ?16'h1234:16'h8000;
                case(index)
                    0:response_byte=w0[15:8];1:response_byte=w0[7:0];2:response_byte=crc(w0)^inject_bad_crc;
                    3:response_byte=w1[15:8];4:response_byte=w1[7:0];default:response_byte=crc(w1);
                endcase
            end
        end
    endfunction
    initial begin
        state=IGNORE;next_state=IGNORE;bit_index=7;drive_low=0;shift=0;tx_byte=0;
        reg_pointer=0;transactions=0;measurements=0;last_command=0;write_index=0;read_index=0;ack_value=0;command_time=0;
        for(k=0;k<256;k=k+1)registers[k]=0;
        registers[0]=8'h60;registers[3]=8'h60;
        registers[4]=8'h56;registers[5]=8'h34;registers[6]=8'h12;
        registers[7]=8'hef;registers[8]=8'hcd;registers[9]=8'hab;
        for(k=49;k<=69;k=k+1)registers[k]=k;
    end
    always @(negedge sda)if(scl===1'b1&&rst_n)begin
        state=ADDRESS_RX;bit_index=7;shift=0;write_index=0;read_index=0;drive_low=0;
    end
    always @(posedge sda)if(scl===1'b1&&rst_n)begin state=IGNORE;drive_low=0;end
    always @(posedge scl)if(rst_n)begin
        case(state)
            ADDRESS_RX,WRITE_RX:begin
                shift[bit_index]=sda;
                if(bit_index==0)begin
                    if(state==ADDRESS_RX)begin
                        ack_value=shift[7:1]==ADDRESS&&!inject_nack;
                        if(ack_value)begin
                            if(shift[0]&&!IS_BMP)begin
                                case(last_command)
                                    8'hfd:minimum_ms=8.3;8'hf6:minimum_ms=4.5;8'he0:minimum_ms=1.6;
                                    8'h39,8'h2f,8'h1e:minimum_ms=1108.3;
                                    8'h32,8'h24,8'h15:minimum_ms=118.3;
                                    default:minimum_ms=0;
                                endcase
                                if($time-command_time<minimum_ms*NS_PER_LOGICAL_MS)
                                    $fatal(1,"SHT read before conversion completed command=%h elapsed=%t",last_command,$time-command_time);
                            end
                            transactions=transactions+1;
                            next_state=shift[0]?READ_TX:WRITE_RX;
                            tx_byte=response_byte(0);
                            if(shift[0]&&IS_BMP&&reg_pointer==4)measurements=measurements+1;
                        end else next_state=IGNORE;
                    end else begin
                        ack_value=!inject_nack;next_state=WRITE_RX;
                        if(IS_BMP)begin
                            if(write_index==0)reg_pointer=shift;
                            else begin registers[reg_pointer]=shift;reg_pointer=reg_pointer+1'b1;end
                        end else begin
                            last_command=shift;
                            command_time=$time;
                            if(shift!=8'h89&&shift!=8'h94)measurements=measurements+1;
                        end
                        write_index=write_index+1;
                    end
                    state=ACK;bit_index=7;
                end else bit_index=bit_index-1;
            end
            ACK:begin state=next_state;bit_index=7;end
            READ_TX:begin
                if(bit_index==0)begin state=READ_ACK;bit_index=7;end
                else bit_index=bit_index-1;
            end
            READ_ACK:begin
                if(sda)state=IGNORE;
                else begin read_index=read_index+1;tx_byte=response_byte(read_index);state=READ_TX;bit_index=7;end
            end
            default:;
        endcase
    end
    always @(negedge scl)begin
        if(!rst_n)drive_low=0;
        else case(state)
            ACK:drive_low=ack_value;
            READ_TX:drive_low=!tx_byte[bit_index];
            default:drive_low=0;
        endcase
    end
endmodule
