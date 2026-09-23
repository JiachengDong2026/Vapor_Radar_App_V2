`default_nettype none
// Bounded byte ring retains rejected candidates. After bad length/version/CRC,
// advance by ONE byte so an embedded valid magic/frame remains recoverable.
module vlp_cmd_rx #(
    parameter integer BUFFER_BYTES=4096,
    parameter integer RX_TIMEOUT_TICKS=10000000
)(
    input wire sys_clk,rst_sys_n,
    input wire s_valid,
    output wire s_ready,
    input wire [7:0] s_data,
    output reg command_valid,
    input wire command_done,
    output reg [31:0] command_status,command_sequence,command_payload_bytes,
    output reg [15:0] command_source,command_id,
    input wire [31:0] payload_read_word,
    output reg [31:0] payload_read_data,
    output reg [31:0] protocol_error_count,crc_error_count,last_sequence,
    output wire [31:0] buffered_bytes
);
    function integer clog2;input integer n;integer t;begin
        t=n-1;for(clog2=0;t>0;clog2=clog2+1)t=t>>1;
    end endfunction
    localparam AW=clog2(BUFFER_BYTES);
    localparam SEARCH=0,HEADER=1,VALIDATE=2,BODY=3,CHECK=4,WAIT=5;
    reg [2:0] state;
    reg [7:0] mem [0:BUFFER_BYTES-1];
    reg [AW-1:0] base,write_ptr;
    reg [AW:0] used;
    reg [31:0] scan,total_length,header_control,crc,received_crc,timeout_count;
    wire [AW-1:0] scan_address=base+scan;
    wire [7:0] byte_in=mem[scan_address];
    wire input_fire=s_valid && s_ready;
    reg [31:0] consume;
    wire [AW-1:0] read_address0=base+40+(payload_read_word<<2);
    wire [AW-1:0] read_address1=read_address0+1'b1;
    wire [AW-1:0] read_address2=read_address0+2'd2;
    wire [AW-1:0] read_address3=read_address0+2'd3;
    wire waiting_byte=(state==HEADER || state==BODY) && scan>=used;
    wire timeout_hit=waiting_byte && used!=0 && timeout_count>=RX_TIMEOUT_TICKS-1 && !input_fire;
    function [31:0] crc_byte;
        input [31:0] c;input [7:0] b;reg [31:0] t;integer j;
        begin t=c^b;for(j=0;j<8;j=j+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1);crc_byte=t;end
    endfunction
    assign s_ready=used<BUFFER_BYTES && !command_valid;
    assign buffered_bytes=used;
    always @* begin
        consume=0;
        if(state==SEARCH && used!=0 && byte_in!=8'h56)consume=1;
        if(state==HEADER && scan<used && ((scan==1 && byte_in!=8'h4c) ||
            (scan==2 && byte_in!=8'h50) || (scan==3 && byte_in!=8'h31)))consume=1;
        if(command_valid && command_done)consume=command_status==0?total_length:1;
    end
    always @(posedge sys_clk)begin
        if(input_fire)mem[write_ptr]<=s_data;
        payload_read_data<={mem[read_address3],mem[read_address2],mem[read_address1],mem[read_address0]};
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            state<=SEARCH;base<=0;write_ptr<=0;used<=0;scan<=0;total_length<=0;
            header_control<=0;crc<=32'hffffffff;received_crc<=0;timeout_count<=0;
            command_valid<=0;command_status<=0;command_sequence<=0;command_source<=0;command_id<=0;
            command_payload_bytes<=0;protocol_error_count<=0;crc_error_count<=0;last_sequence<=0;
        end else begin
            used<=used+input_fire-consume;
            if(input_fire)write_ptr<=write_ptr+1'b1;
            if(consume!=0)base<=base+consume;
            if(input_fire || consume!=0 || !waiting_byte)timeout_count<=0;
            else if(timeout_count<RX_TIMEOUT_TICKS)timeout_count<=timeout_count+1'b1;
            case(state)
                SEARCH:begin
                    scan<=0;
                    if(used!=0 && byte_in==8'h56)begin
                        state<=HEADER;crc<=32'hffffffff;received_crc<=0;
                        header_control<=0;total_length<=0;command_payload_bytes<=0;
                        command_sequence<=0;command_source<=0;command_id<=0;
                    end
                end
                HEADER:if(scan<used)begin
                    if(consume!=0)begin state<=SEARCH;scan<=0;end
                    else begin
                        crc<=crc_byte(crc,byte_in);scan<=scan+1'b1;
                        if(scan>=4 && scan<8)header_control[(scan-4)*8 +: 8]<=byte_in;
                        if(scan>=8 && scan<12)total_length[(scan-8)*8 +: 8]<=byte_in;
                        if(scan>=12 && scan<16)command_sequence[(scan-12)*8 +: 8]<=byte_in;
                        if(scan>=16 && scan<18)command_source[(scan-16)*8 +: 8]<=byte_in;
                        if(scan>=18 && scan<20)command_id[(scan-18)*8 +: 8]<=byte_in;
                        if(scan>=36 && scan<40)command_payload_bytes[(scan-36)*8 +: 8]<=byte_in;
                        if(scan==39)state<=VALIDATE;
                    end
                end
                VALIDATE:begin
                    if(total_length<44 || total_length>BUFFER_BYTES || command_payload_bytes>BUFFER_BYTES-44 ||
                       total_length!=command_payload_bytes+44)begin
                        command_valid<=1;command_status<=2;state<=WAIT;protocol_error_count<=protocol_error_count+1'b1;
                    end else if(header_control!=32'h0a010001)begin
                        command_valid<=1;command_status<=12;state<=WAIT;protocol_error_count<=protocol_error_count+1'b1;
                    end else state<=BODY;
                end
                BODY:if(scan<used)begin
                    if(scan<total_length-4)crc<=crc_byte(crc,byte_in);
                    else received_crc[(scan-(total_length-4))*8 +: 8]<=byte_in;
                    scan<=scan+1'b1;
                    if(scan==total_length-1)state<=CHECK;
                end
                CHECK:begin
                    state<=WAIT;command_valid<=1;
                    if(received_crc!=~crc)begin
                        command_status<=3;crc_error_count<=crc_error_count+1'b1;protocol_error_count<=protocol_error_count+1'b1;
                    end else begin command_status<=0;last_sequence<=command_sequence;end
                end
                WAIT:if(command_valid && command_done)begin command_valid<=0;state<=SEARCH;scan<=0;end
            endcase
            if(timeout_hit)begin
                command_valid<=1;command_status<=9;state<=WAIT;
                protocol_error_count<=protocol_error_count+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
