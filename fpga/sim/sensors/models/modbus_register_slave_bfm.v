`timescale 1ns/1ps
// Independent pin-level register device for extension tests. Bytes on the wire
// are decoded here, without instantiating the DUT UART or Modbus engine.
module modbus_register_slave_bfm #(
    parameter integer BAUD=100000,ADDR=1,DEVICE_KIND=0
)(
    input wire rst_n,master_txd,master_de,lock_writes,
    input wire [15:0] exception_address,
    output reg rxd=1,output integer requests=0,writes=0
);
    localparam integer BIT_NS=1000000000/BAUD;
    reg [15:0] memory[0:12287];
    reg [7:0] request[0:40],reply[0:40];
    reg [15:0] crc,address,quantity;
    integer i,k,n,body;
    function [15:0] update_crc;
        input [15:0] previous;input [7:0] value;
        reg [15:0] v;integer b;
        begin v=previous^value;for(b=0;b<8;b=b+1)v=v[0]?(v>>1)^16'ha001:v>>1;update_crc=v;end
    endfunction
    task receive_byte;
        output [7:0] value;integer b;
        begin
            @(negedge master_txd);if(!master_de)$fatal(1,"MODEL unowned TX");
            #(BIT_NS+BIT_NS/2);
            for(b=0;b<8;b=b+1)begin value[b]=master_txd;#BIT_NS;end
            if(master_txd!==1)$fatal(1,"MODEL stop bit");#(BIT_NS/4);
        end
    endtask
    task send_byte;
        input [7:0] value;integer b;
        begin
            if(master_de)$fatal(1,"MODEL bus collision");
            rxd=0;#BIT_NS;for(b=0;b<8;b=b+1)begin rxd=value[b];#BIT_NS;end
            rxd=1;#BIT_NS;
        end
    endtask
    initial begin
        for(i=0;i<12288;i=i+1)memory[i]=0;
        if(DEVICE_KIND==0)for(i=0;i<8;i=i+1)begin
            memory[i]=100+i;memory['h600+i]=200+i;memory['h480+i]=300+i;memory['h360+i]=400+i;
        end
        else begin memory['h1000]='h26;memory['h1001]='h25a0;memory['h1002]='h26;memory['h1003]='h25a0;end
        wait(rst_n);
        forever begin
            receive_byte(request[0]);receive_byte(request[1]);
            for(k=2;k<6;k=k+1)receive_byte(request[k]);
            quantity={request[4],request[5]};
            if(quantity==0 || quantity>16)$fatal(1,"MODEL quantity");
            n=request[1]==16 ? 9+quantity*2 : 8;
            for(k=6;k<n;k=k+1)receive_byte(request[k]);
            crc=16'hffff;for(k=0;k<n;k=k+1)crc=update_crc(crc,request[k]);
            if(crc!=0 || request[0]!=ADDR || (request[1]!=3 && request[1]!=16))$fatal(1,"MODEL request CRC/address/function");
            address={request[2],request[3]};requests=requests+1;reply[0]=ADDR;
            if(address+quantity>12288)$fatal(1,"MODEL register range");
            if(address==exception_address)begin reply[1]=request[1]|8'h80;reply[2]=2;body=3;end
            else if(request[1]==16)begin
                writes=writes+1;
                if(request[6]!=quantity*2)$fatal(1,"MODEL byte count");
                if(!lock_writes)for(k=0;k<quantity;k=k+1)memory[address+k]={request[7+k*2],request[8+k*2]};
                reply[1]=16;reply[2]=request[2];reply[3]=request[3];reply[4]=request[4];reply[5]=request[5];body=6;
            end else begin
                reply[1]=3;reply[2]=quantity*2;body=3+quantity*2;
                for(k=0;k<quantity;k=k+1)begin reply[3+k*2]=memory[address+k][15:8];reply[4+k*2]=memory[address+k][7:0];end
            end
            wait(!master_de);#(BIT_NS*4);
            crc=16'hffff;for(k=0;k<body;k=k+1)crc=update_crc(crc,reply[k]);
            reply[body]=crc[7:0];reply[body+1]=crc[15:8];
            for(k=0;k<body+2;k=k+1)send_byte(reply[k]);
        end
    end
endmodule
