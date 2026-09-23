`timescale 1ns/1ps
// Independent bit-level AI-8 model. Fault mode: 0 normal, 1 locked writes,
// 2 write silence, 3 write CRC, 4 write exception, 5 verify silence,
// 6 verify CRC, 7 verify exception. RETRY_LIMIT matches the test master.
module ai8_hmp_bus_bfm #(
    parameter integer BAUD_HZ=19200, SLAVE_ADDR=1, CHANNEL=1,
    parameter integer PARITY_MODE=0, STOP_BITS=1, RETRY_LIMIT=1,
    parameter [15:0] INITIAL_SP=500, PV=244, SV=450, OP=12800,
    parameter [15:0] ALARM_WORD=16'h15a2, CONTROL_WORD=16'h0103, HOST_STATUS=16'h0301
)(
    input wire rst_n, input wire master_txd, input wire master_de,
    input wire [3:0] fault_mode, hmp_fault, output reg slave_txd=1,
    output integer request_count=0, output integer write_count=0,
    output integer verify_count=0, output integer hmp_count=0, hmp_write_count=0,
    output reg [31:0] pressure_bits=0, output reg [15:0] current_sp=INITIAL_SP
);
    localparam integer BIT_NS=1000000000/BAUD_HZ;
    reg [7:0] request[0:12], reply[0:12];
    reg [15:0] crc, address, value;
    reg verify_pending, is_verify, silent, corrupt;
    integer i, length, body, verify_attempt, poll_item;
    function [15:0] crc_byte;
        input [15:0] previous; input [7:0] data;
        reg [15:0] v; integer b;
        begin v=previous^data;
            for(b=0;b<8;b=b+1) v=(v&1)?(v>>1)^16'ha001:v>>1;
            crc_byte=v;
        end
    endfunction
    function [15:0] poll_address;
        input integer item;
        begin case(item)
            0:poll_address=CHANNEL-1; 1:poll_address=16'h600+CHANNEL-1;
            2:poll_address=16'h480+CHANNEL-1; 3:poll_address=16'h360+CHANNEL-1;
            4:poll_address=16'h680+(CHANNEL-1)/2; 5:poll_address=16'h6c0+(CHANNEL-1)/2;
            default:poll_address=16'h851;
        endcase end
    endfunction
    task receive_byte;
        output [7:0] data; integer b;
        begin
            @(negedge master_txd);
            if(!master_de) $fatal(1,"set BFM TX without DE");
            #(BIT_NS+BIT_NS/2);
            for(b=0;b<8;b=b+1) begin data[b]=master_txd; #BIT_NS; end
            if(PARITY_MODE) begin
                if(master_txd!==^data) $fatal(1,"set BFM parity"); #BIT_NS;
            end
            for(b=0;b<STOP_BITS;b=b+1) begin
                if(master_txd!==1) $fatal(1,"set BFM stop");
                if(b<STOP_BITS-1) #BIT_NS;
            end
            #(BIT_NS/4);
        end
    endtask
    task send_byte;
        input [7:0] data; integer b;
        begin
            if(master_de) $fatal(1,"set BFM bus collision");
            slave_txd=0; #BIT_NS;
            for(b=0;b<8;b=b+1) begin slave_txd=data[b]; #BIT_NS; end
            if(PARITY_MODE) begin slave_txd=^data; #BIT_NS; end
            slave_txd=1; #(BIT_NS*STOP_BITS);
        end
    endtask
    initial forever begin
        slave_txd=1; current_sp=INITIAL_SP; request_count=0; write_count=0; verify_count=0;
        verify_pending=0; verify_attempt=0; poll_item=0; hmp_count=0; hmp_write_count=0; pressure_bits=0;
        wait(rst_n);
        fork : active
            begin forever begin
                for(i=0;i<6;i=i+1) receive_byte(request[i]);
                if(request[1]==16) begin receive_byte(request[6]); length=9+request[6]; end
                else length=8;
                for(i=request[1]==16 ? 7:6;i<length;i=i+1) receive_byte(request[i]);
                crc=16'hffff;
                for(i=0;i<length;i=i+1) crc=crc_byte(crc,request[i]);
                if(crc!==0 || (request[0]!==SLAVE_ADDR && request[0]!==240) ||
                    (request[1]!==3 && request[1]!==16) || request[4]!==0)
                    $fatal(1,"set BFM invalid request/CRC/function/quantity");
                request_count=request_count+1; address={request[2],request[3]};
                silent=0; corrupt=0; is_verify=0; reply[0]=SLAVE_ADDR;
                if(request[0]==240) begin
                    hmp_count=hmp_count+1; reply[0]=240;
                    if(request[1]==16)begin
                        if(address!==16'h300 || request[5]!==2 || request[6]!==4) $fatal(1,"HMP illegal write");
                        hmp_write_count=hmp_write_count+1;
                        pressure_bits={request[9],request[10],request[7],request[8]};
                        reply[1]=16; reply[2]=3;reply[3]=0;reply[4]=0;reply[5]=2;body=6;
                    end else begin
                        if(address!==0 || request[5]!==4) $fatal(1,"HMP illegal read");
                        reply[1]=3;reply[2]=8;reply[3]=0;reply[4]=0;reply[5]=8'h42;reply[6]=8'h48;
                        reply[7]=0;reply[8]=0;reply[9]=8'h41;reply[10]=8'hcc;body=11;
                    end
                    if(hmp_fault==1)silent=1;
                    if(hmp_fault==2)corrupt=1;
                    if(hmp_fault==3)begin reply[1]=request[1]|8'h80;reply[2]=2;body=3;end
                end else if(request[1]==16) begin
                    if(request[5]!==1) $fatal(1,"AI8 write quantity");
                    if(address!==CHANNEL-1 || request[6]!==2 || poll_item!=0)
                        $fatal(1,"set BFM illegal write address/length or poll interleaving");
                    write_count=write_count+1;
                    if(fault_mode!=1 && fault_mode!=2 && fault_mode!=4) current_sp={request[7],request[8]};
                    reply[1]=16; reply[2]=request[2]; reply[3]=request[3]; reply[4]=0; reply[5]=1; body=6;
                    if(fault_mode==2) silent=1;
                    if(fault_mode==3) corrupt=1;
                    if(fault_mode==4) begin reply[1]=8'h90; reply[2]=3; body=3; end
                    if(fault_mode!=2 && fault_mode!=3 && fault_mode!=4) begin
                        verify_pending=1; verify_attempt=0;
                    end
                end else begin
                    if(request[5]!==1) $fatal(1,"AI8 read quantity");
                    is_verify=verify_pending;
                    if(is_verify) begin
                        if(address!==CHANNEL-1) $fatal(1,"set BFM verify wrong address");
                        verify_count=verify_count+1;
                        if(fault_mode==5 || fault_mode==6) begin
                            if(verify_attempt>=RETRY_LIMIT) verify_pending=0;
                            else verify_attempt=verify_attempt+1;
                        end else verify_pending=0;
                    end else begin
                        if(address!==poll_address(poll_item)) $fatal(1,"set BFM poll order");
                        if(poll_item==6) poll_item=0; else poll_item=poll_item+1;
                    end
                    if(address==CHANNEL-1) value=current_sp;
                    else if(address==16'h600+CHANNEL-1) value=PV;
                    else if(address==16'h480+CHANNEL-1) value=SV;
                    else if(address==16'h360+CHANNEL-1) value=OP;
                    else if(address==16'h680+(CHANNEL-1)/2) value=ALARM_WORD;
                    else if(address==16'h6c0+(CHANNEL-1)/2) value=CONTROL_WORD;
                    else if(address==16'h851) value=HOST_STATUS;
                    else $fatal(1,"set BFM unsupported address");
                    reply[1]=3; reply[2]=2; reply[3]=value[15:8]; reply[4]=value[7:0]; body=5;
                    if(is_verify && fault_mode==5) silent=1;
                    if(is_verify && fault_mode==6) corrupt=1;
                    if(is_verify && fault_mode==7) begin reply[1]=8'h83; reply[2]=2; body=3; end
                end
                @(negedge master_de); #(BIT_NS*2);
                crc=16'hffff;
                for(i=0;i<body;i=i+1) crc=crc_byte(crc,reply[i]);
                if(corrupt) crc=crc^1;
                reply[body]=crc[7:0]; reply[body+1]=crc[15:8];
                if(!silent) for(i=0;i<body+2;i=i+1) send_byte(reply[i]);
            end end
            begin @(negedge rst_n); disable active; end
        join
    end
endmodule
