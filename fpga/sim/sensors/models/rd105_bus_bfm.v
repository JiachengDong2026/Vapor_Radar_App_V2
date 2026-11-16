`timescale 1ns/1ps
// Independent serial model; no DUT transport/CRC helper is reused.
module rd105_bus_bfm #(parameter real BIT_NS=520.833333)(
    input wire rst_n,master_txd,master_de,
    input wire [3:0] fault,
    output reg slave_txd=1,
    output integer rd_count=0,rd_writes=0,ch1_count=0,ch2_count=0,hmp_count=0,ai8_count=0
);
    reg [15:0] memory[0:65535];
    reg [7:0] req[0:41],reply[0:40];
    reg [15:0] crc,address,word_value;
    reg [3:0] mode;
    integer i,j,n,length,body,quantity;
    realtime last_stop=0;
    function [15:0] update;
        input [15:0] previous;input [7:0] data;integer b;reg [15:0] v;
        begin v=previous^data;for(b=0;b<8;b=b+1)v=v[0]?(v>>1)^16'ha001:v>>1;update=v;end
    endfunction
    task receive_byte;
        output [7:0] data;integer b;
        begin
            @(negedge master_txd);
            if(!master_de)$fatal(1,"TX without DE");
            if(i==0 && last_stop && $realtime-last_stop<BIT_NS*35)$fatal(1,"RTU silence violated");
            #(BIT_NS*1.5);
            for(b=0;b<8;b=b+1)begin data[b]=master_txd;#BIT_NS;end
            if(!master_txd || !master_de)$fatal(1,"stop/DE truncated");
            #(BIT_NS*0.25);
        end
    endtask
    task send_byte;
        input [7:0] data;integer b;
        begin
            if(master_de)$fatal(1,"response collision");
            slave_txd=0;#BIT_NS;
            for(b=0;b<8;b=b+1)begin slave_txd=data[b];#BIT_NS;end
            slave_txd=1;#BIT_NS;last_stop=$realtime;
        end
    endtask
    initial begin
        for(j=0;j<65536;j=j+1)memory[j]=0;
        memory['h1000]='h0026;memory['h1001]='h25a0;
        memory['h1002]='h0026;memory['h1003]='h25a0;
        memory['h2000]='hffec;memory['h2001]='hed30; // -12.5 C
        memory['h2002]='hfff0;memory['h2003]='hbdc0; // -10 C
        memory['h1103]='hffff;memory['h1104]='hffff;memory['h1105]='hffff;memory['h1106]='h63c0; // -40000 duty=-2%
        memory['h2105]=0;memory['h2106]=20000; // +1%
        wait(rst_n);
        forever begin
            for(i=0;i<6;i=i+1)receive_byte(req[i]);
            length=8;
            if(req[1]==16)begin receive_byte(req[6]);length=9+req[6];end
            for(i=req[1]==16?7:6;i<length;i=i+1)receive_byte(req[i]);
            crc=16'hffff;for(n=0;n<length;n=n+1)crc=update(crc,req[n]);
            if(crc!=0)$fatal(1,"request CRC");
            address={req[2],req[3]};quantity={req[4],req[5]};mode=fault;
            if(quantity<1 || quantity>16)$fatal(1,"quantity");
            reply[0]=req[0];reply[1]=req[1];body=0;
            if(req[0]==2)begin
                rd_count=rd_count+1;
                if(address[15:12]==1)ch1_count=ch1_count+1;
                if(address[15:12]==2)ch2_count=ch2_count+1;
                if(req[1]==16)begin
                    rd_writes=rd_writes+1;
                    if(address<=9 && address+quantity>0)$fatal(1,"dangerous general write");
                    if(mode!=5 && mode!=4)for(n=0;n<quantity;n=n+1)memory[address+n]={req[7+2*n],req[8+2*n]};
                    for(n=2;n<6;n=n+1)reply[n]=req[n];body=6;
                end else begin
                    reply[2]=quantity*2;body=3+quantity*2;
                    for(n=0;n<quantity;n=n+1)begin reply[3+2*n]=memory[address+n][15:8];reply[4+2*n]=memory[address+n][7:0];end
                end
                if(mode==2)reply[0]=3;
                if(mode==4)begin reply[1]=req[1]|8'h80;reply[2]=2;body=3;end
            end else if(req[0]==240)begin
                hmp_count=hmp_count+1;
                if(req[1]!=3 || address!=0 || quantity!=4)$fatal(1,"HMP unexpected request");
                reply[2]=8;reply[3]=0;reply[4]=0;reply[5]='h42;reply[6]='h48;
                reply[7]=0;reply[8]=0;reply[9]='h41;reply[10]='hcc;body=11;
            end else if(req[0]==1)begin
                ai8_count=ai8_count+1;
                if(req[1]!=3 || quantity!=1)$fatal(1,"AI8 unexpected request");
                word_value=address=='h600 ? 244 : address==0 ? 500 : 0;
                reply[2]=2;reply[3]=word_value[15:8];reply[4]=word_value[7:0];body=5;
            end else $fatal(1,"unexpected station");
            @(negedge master_de);#(BIT_NS*2);
            crc=16'hffff;for(n=0;n<body;n=n+1)crc=update(crc,reply[n]);
            if(req[0]==2 && mode==1)crc=crc^1;
            reply[body]=crc[7:0];reply[body+1]=crc[15:8];
            if(req[0]!=2 || mode!=3)for(j=0;j<body+2;j=j+1)send_byte(reply[j]);
        end
    end
endmodule
