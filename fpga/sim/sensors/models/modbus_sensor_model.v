`timescale 1ns/1ps
module modbus_sensor_model #(
    parameter integer SYS_CLK_HZ=100000000,DEVICE_KIND=0,
    parameter integer BAUD_HZ=DEVICE_KIND==0 ? 19200 : 38400,
    parameter real CLOCK_PERIOD_NS=10.0
)(
    input wire clk,input wire rst_n,input wire request_txd,input wire rs485_de,
    output wire response_rxd,input wire [3:0] inject_mode,
    input wire [31:0] native_temperature,input wire [15:0] device_error,
    output reg [31:0] request_count=0,output reg [31:0] write_count=0,
    output reg [31:0] last_written=0,output reg response_start_pulse=0,
    output reg [31:0] channel2_requests=0
);
    localparam real BIT_NS=CLOCK_PERIOD_NS*SYS_CLK_HZ/BAUD_HZ;
    localparam integer STOPS=DEVICE_KIND==0 ? 2 : 1;
    reg line=1;
    assign response_rxd=DEVICE_KIND==0 && rs485_de ? request_txd : line;
    reg [7:0] request[0:40],reply[0:40];
    integer count,need,n,len,quantity;
    reg [15:0] crc,addr;
    reg [31:0] target=2500000,value;
    reg [3:0] mode;
    realtime reply_stop_end=0;
    function [15:0] update;
        input [15:0] c;input [7:0] b;reg [15:0] v;integer i;
        begin v=c^b;for(i=0;i<8;i=i+1)v=v[0]?(v>>1)^16'ha001:v>>1;update=v;end
    endfunction
    task receive_byte;
        output [7:0] b;integer bitnum;
        begin
            @(negedge request_txd);
            if(count==0 && reply_stop_end!=0 && $realtime-reply_stop_end<BIT_NS*(9+STOPS)*3.5)
                $fatal(1,"MODEL_RTU_INTERFRAME_GAP");
            if(DEVICE_KIND==0 && !rs485_de)$fatal(1,"MODEL_DE_NOT_ASSERTED");
            #(BIT_NS*1.5);
            for(bitnum=0;bitnum<8;bitnum=bitnum+1)begin b[bitnum]=request_txd;#(BIT_NS);end
            if(!request_txd)$fatal(1,"MODEL_REQUEST_STOP");
            #(BIT_NS*(STOPS-0.5));
            if(DEVICE_KIND==0 && !rs485_de)$fatal(1,"MODEL_DE_EARLY_RELEASE");
        end
    endtask
    task send_byte;
        input [7:0] b;input bad_stop;integer bitnum;
        begin
            line=0;#(BIT_NS);
            for(bitnum=0;bitnum<8;bitnum=bitnum+1)begin line=b[bitnum];#(BIT_NS);end
            line=bad_stop ? 0 : 1;#(BIT_NS*STOPS);line=1;reply_stop_end=$realtime;#(BIT_NS*0.1);
        end
    endtask
    initial begin
        wait(rst_n);
        forever begin
            count=0;need=8;
            while(count<need)begin
                receive_byte(request[count]);count=count+1;
                if(count==7 && request[1]==16)need=9+request[6];
                if(need>41)$fatal(1,"MODEL_REQUEST_LENGTH");
            end
            crc=16'hffff;for(n=0;n<count;n=n+1)crc=update(crc,request[n]);
            if(crc!=0)$fatal(1,"MODEL_REQUEST_CRC");
            if(request[0]!=(DEVICE_KIND==0 ? 240 : 1))$fatal(1,"MODEL_REQUEST_SLAVE");
            addr={request[2],request[3]};quantity={request[4],request[5]};
            if(addr[15:12]==2)channel2_requests=channel2_requests+1;
            request_count=request_count+1;mode=inject_mode;
            len=0;reply[0]=request[0];reply[1]=request[1];
            if(request[1]==16)begin
                if(quantity!=2 || request[6]!=4)$fatal(1,"MODEL_WRITE_QUANTITY");
                if(DEVICE_KIND==0)begin
                    if(addr!=16'h0300)$fatal(1,"HMP_PRESSURE_ADDRESS");
                    if(mode!=5)last_written={request[9],request[10],request[7],request[8]};
                end else begin
                    if(addr!=16'h1000 && addr!=16'h2000)$fatal(1,"RD_TARGET_ADDRESS");
                    if(mode!=5)begin last_written={request[7],request[8],request[9],request[10]};target=last_written;end
                end
                if(mode!=5)write_count=write_count+1;
                for(n=2;n<6;n=n+1)reply[n]=request[n];len=6;
            end else if(request[1]==3)begin
                reply[2]=quantity*2;len=3+quantity*2;
                for(n=3;n<len;n=n+1)reply[n]=0;
                if(DEVICE_KIND==0)begin
                    if(addr!=0 || quantity!=4)$fatal(1,"HMP_READ_ADDRESS");
                    value=mode==10 ? 32'h7fc00000 : 32'h42480000;
                    reply[3]=value[15:8];reply[4]=value[7:0];reply[5]=value[31:24];reply[6]=value[23:16];
                    value=32'h41cc0000;
                    reply[7]=value[15:8];reply[8]=value[7:0];reply[9]=value[31:24];reply[10]=value[23:16];
                end else if(addr==16'h0007)begin
                    if(quantity!=1)$fatal(1,"RD_ERROR_QUANTITY");reply[3]=device_error[15:8];reply[4]=device_error[7:0];
                end else begin
                    if((addr!=16'h1000 && addr!=16'h1002 && addr!=16'h2000 && addr!=16'h2002) || quantity!=2)$fatal(1,"RD_READ_ADDRESS");
                    value=addr[11:0]==0 ? target : native_temperature;
                    reply[3]=value[31:24];reply[4]=value[23:16];reply[5]=value[15:8];reply[6]=value[7:0];
                end
            end else $fatal(1,"MODEL_REQUEST_FUNCTION");
            if(mode==2)reply[0]=request[0]+1;
            if(mode==3)reply[1]=4;
            if(mode==4)len=len-1;
            if(mode==5)begin reply[1]=request[1]|8'h80;reply[2]=2;len=3;end
            if(mode==8 && request[1]==16)reply[3]=reply[3]+1;
            crc=16'hffff;for(n=0;n<len;n=n+1)crc=update(crc,reply[n]);
            reply[len]=crc[7:0];reply[len+1]=crc[15:8];len=len+2;
            if(mode==1)reply[len-1]=reply[len-1]^1;
            #(BIT_NS*(9+STOPS)*3.7);
            if(mode!=6)begin
                if(DEVICE_KIND==0 && rs485_de)$fatal(1,"MODEL_DE_TURNAROUND");
                response_start_pulse=1;
                for(n=0;n<len;n=n+1)begin
                    send_byte(reply[n],mode==7 && n==0);response_start_pulse=0;
                    if(mode==9 && n==2)#(BIT_NS*(9+STOPS)*2.0);
                end
            end
        end
    end
endmodule
