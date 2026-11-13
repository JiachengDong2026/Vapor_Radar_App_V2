`timescale 1ns/1ps
// Independent bit-level device model; one instance per physical UART.
// TTL_HC2A=1 models CON11 HC2A; zero models CON19 AI8 only.
// HC2A faults: 1 silence, 2 checksum, 3 RH sentinel, 4 Fahrenheit unit,
// 5 wrong address, 6 overlong frame, 7 framing, 8 delayed 500 ms response,
// 9 negative temperature, 10 RH/T endpoints, 11 oversized integer, 12 alarm >255.
module hc2a_ai8_device_bfm #(
    parameter integer TTL_HC2A=0,ADDRESS=4,BAUD_HZ=19200
)(
    input wire rst_n,master_txd,master_de,
    input wire [3:0] hc2a_fault,
    output reg slave_txd=1,
    output integer hc2a_count=0,ai8_count=0,write_count=0,
    output reg [15:0] current_sp=500
);
    localparam integer BIT_NS=1000000000/BAUD_HZ;
    localparam [7:0] ADDRESS_TENS=8'h30+ADDRESS/10,ADDRESS_ONES=8'h30+ADDRESS%10;
    reg [7:0] request[0:15],reply[0:191];
    reg [15:0] crc,reg_addr,value;
    reg [31:0] checksum;
    reg [3:0] fault;
    integer i,length,body,poll_item;
    reg verify_pending;
    function [15:0] crc_byte;
        input [15:0] previous;
        input [7:0] data;
        integer b;reg [15:0] v;
        begin
            v=previous^data;
            for(b=0;b<8;b=b+1)v=v[0]?(v>>1)^16'ha001:v>>1;
            crc_byte=v;
        end
    endfunction
    function [15:0] poll_address;
        input integer item;
        begin case(item)
            0:poll_address=0;1:poll_address=16'h600;
            2:poll_address=16'h480;3:poll_address=16'h360;
            4:poll_address=16'h680;5:poll_address=16'h6c0;
            default:poll_address=16'h851;
        endcase end
    endfunction
    task receive_byte;
        output [7:0] data;
        integer b;
        begin
            @(negedge master_txd);
            if(!TTL_HC2A && !master_de)$fatal(1,"HC2A_AI8_TX_WITHOUT_DE");
            #(BIT_NS+BIT_NS/2);
            for(b=0;b<8;b=b+1)begin data[b]=master_txd;#BIT_NS;end
            if(master_txd!==1'b1)$fatal(1,"HC2A_AI8_TX_8N1_STOP");
        end
    endtask
    task send_byte;
        input [7:0] data;
        input bad_stop;
        integer b;
        begin
            if(!TTL_HC2A && master_de)$fatal(1,"HC2A_AI8_BUS_COLLISION");
            slave_txd=0;#BIT_NS;
            for(b=0;b<8;b=b+1)begin slave_txd=data[b];#BIT_NS;end
            slave_txd=!bad_stop;#BIT_NS;
            slave_txd=1;
            if(bad_stop)#BIT_NS;
        end
    endtask
    task append;
        input [1023:0] text;
        integer j;
        begin
            for(j=127;j>=0;j=j-1)if(text[j*8+:8]!=0)begin
                reply[body]=text[j*8+:8];body=body+1;
            end
        end
    endtask
    task hc2a_reply;
        integer j;
        begin
            hc2a_count=hc2a_count+1;fault=hc2a_fault;
            if(request[1]!=="F" || {request[4],request[5],request[6],request[7],request[8]}!=={32'h5244447d,8'h0d})
                $fatal(1,"HC2A_REQUEST_NOT_RDD");
            if({request[2],request[3]}!==16'h3939 &&
               {request[2],request[3]}!=={ADDRESS_TENS,ADDRESS_ONES})
                $fatal(1,"HC2A_REQUEST_ADDRESS %h%h",request[2],request[3]);
            if(TTL_HC2A) #(BIT_NS*3/2);
            else begin @(negedge master_de);#(BIT_NS*2);end
            if(fault==8)#500000000;
            if(fault!=1)begin
                body=0;checksum=0;
                append("{F04rdd 001;");
                reply[2]=ADDRESS_TENS;reply[3]=ADDRESS_ONES;
                if(fault==5)reply[3]="5";
                if(fault==3)append("---.--;");
                else if(fault==10)append("100.00;");
                else if(fault==11)append("4294967346.00;");
                else append(" 50.00;");
                append("%RH;000;=;");
                if(fault==9)append("-20.07;");
                else if(fault==10)append("-40.00;");
                else append(" 25.50;");
                if(fault==4)append("F;");
                else begin reply[body]=8'hb0;body=body+1;append("C;");end
                append("000;=;nc;---.--;");reply[body]=8'hb0;body=body+1;
                append("C;000; ;001;B2.8;0000000002;HC2A;");
                if(fault==12)append("256;");else append("000;");
                if(fault==6)begin
                    for(j=0;j<90;j=j+1)begin reply[body]="X";body=body+1;end
                end
                for(j=0;j<body;j=j+1)checksum=checksum+reply[j];
                reply[body]=(checksum&32'h3f)+32'h20;
                if(fault==2)reply[body]=reply[body]^1;
                body=body+1;reply[body]=8'h0d;body=body+1;
                for(j=0;j<body;j=j+1)send_byte(reply[j],fault==7 && j==8);
            end
        end
    endtask
    task ai8_reply;
        integer j;
        begin
            crc=16'hffff;
            for(j=0;j<length;j=j+1)crc=crc_byte(crc,request[j]);
            if(crc!==0||request[0]!==1||request[4]!==0||request[5]!==1)
                $fatal(1,"AI8_REQUEST_CRC_ADDRESS_QUANTITY");
            ai8_count=ai8_count+1;reg_addr={request[2],request[3]};reply[0]=1;
            if(request[1]==16)begin
                if(reg_addr!=0||request[6]!=2||poll_item!=0)$fatal(1,"AI8_ILLEGAL_SET_INTERLEAVE");
                current_sp={request[7],request[8]};write_count=write_count+1;verify_pending=1;
                reply[1]=16;reply[2]=0;reply[3]=0;reply[4]=0;reply[5]=1;body=6;
            end else begin
                if(request[1]!=3)$fatal(1,"AI8_ILLEGAL_FUNCTION");
                if(verify_pending)begin
                    if(reg_addr!=0)$fatal(1,"AI8_VERIFY_ADDRESS");verify_pending=0;
                end else begin
                    if(reg_addr!=poll_address(poll_item))$fatal(1,"AI8_POLL_ORDER");
                    if(poll_item==6)poll_item=0;else poll_item=poll_item+1;
                end
                case(reg_addr)
                    0:value=current_sp;16'h600:value=244;16'h480:value=450;
                    16'h360:value=12800;16'h680:value=0;16'h6c0:value=16'h0103;
                    16'h851:value=0;default:value=0;
                endcase
                reply[1]=3;reply[2]=2;reply[3]=value[15:8];reply[4]=value[7:0];body=5;
            end
            if(TTL_HC2A) #(BIT_NS*3/2);
            else begin @(negedge master_de);#(BIT_NS*2);end
            crc=16'hffff;
            for(j=0;j<body;j=j+1)crc=crc_byte(crc,reply[j]);
            reply[body]=crc[7:0];reply[body+1]=crc[15:8];
            for(j=0;j<body+2;j=j+1)send_byte(reply[j],0);
        end
    endtask
    initial forever begin
        slave_txd=1;hc2a_count=0;ai8_count=0;write_count=0;
        poll_item=0;verify_pending=0;current_sp=500;
        wait(rst_n);
        fork:active
            begin forever begin
                receive_byte(request[0]);
                if(TTL_HC2A)begin
                    if(request[0]!=8'h7b)$fatal(1,"NON_ASCII_ON_CON21");
                    for(i=1;i<9;i=i+1)receive_byte(request[i]);
                    hc2a_reply();
                end else begin
                    if(request[0]!=1)$fatal(1,"NON_MODBUS_ON_CON19");
                    for(i=1;i<7;i=i+1)receive_byte(request[i]);
                    length=request[1]==16?11:8;
                    for(i=7;i<length;i=i+1)receive_byte(request[i]);
                    ai8_reply();
                end
            end end
            begin @(negedge rst_n);disable active;end
        join
    end
endmodule
