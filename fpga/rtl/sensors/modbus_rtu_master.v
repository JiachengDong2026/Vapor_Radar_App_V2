`default_nettype none
module modbus_rtu_master #(
    parameter integer SYS_CLK_HZ=100000000, SHARED_BUS=0
)(
    input wire sys_clk,input wire rst_sys_n,input wire enable,
    input wire [31:0] baud_hz,input wire [1:0] parity_mode,input wire [1:0] stop_bits,
    input wire req_valid,output wire req_ready,input wire [7:0] req_slave,input wire [7:0] req_function,
    input wire [15:0] req_address,input wire [4:0] req_quantity,input wire [255:0] req_write_data,
    input wire [15:0] timeout_ms,input wire [1:0] retry_limit,
    input wire [63:0] timestamp_now,input wire time_sync_valid,
    output reg done,output reg [3:0] error,output reg [7:0] exception_code,
    output reg [255:0] read_data,output reg [63:0] response_timestamp,output reg response_time_sync,
    output reg attempt_error_pulse,output reg [3:0] attempt_error,
    input wire uart_rxd,output wire uart_txd,output wire rs485_de,output wire busy,
    output wire bus_request,input wire bus_grant
);
    localparam IDLE=0,BUILD=1,QUIET=2,DE_GUARD=3,SEND=4,LAST_STOP=5,TURN=6,RECEIVE=7,CHECK=8;
    reg [3:0] state;
    reg [7:0] slave,func;
    reg [15:0] address,timeout;
    reg [4:0] quantity;
    reg [255:0] payload;
    reg [31:0] baud;
    reg [1:0] parity,stops,retries,max_retries;
    reg [5:0] tx_len,tx_index,build_index,rx_count;
    reg [319:0] response;
    reg [15:0] tx_crc,rx_crc;
    reg [31:0] half_acc,ms_div;
    reg [15:0] elapsed_ms;
    reg [7:0] quiet_halfbits;
    // The fixed high-baud timers start after the remaining half stop bit.
    // Use 64-bit constant arithmetic so ordinary FPGA clocks do not overflow.
    localparam [31:0] HIGH_FRAME_CYCLES = (64'd1750*SYS_CLK_HZ+999999)/1000000;
    localparam [31:0] HIGH_BYTE_CYCLES = (64'd750*SYS_CLK_HZ+999999)/1000000;
    reg [31:0] quiet_cycles;
    reg rx_bad,rx_seen;
    wire [32:0] half_sum={1'b0,half_acc}+{baud,1'b0};
    wire half_tick=half_sum>=SYS_CLK_HZ;
    wire [7:0] char_bits=8'd9+(parity!=0 ? 8'd1:8'd0)+{6'd0,stops};
    // uart_rx reports a byte at the center of the last stop bit. Add one
    // half-bit so the required 3.5 characters begin after the complete stop.
    wire [7:0] quiet_target=char_bits*7+1;
    wire frame_quiet=baud>19200 ? quiet_cycles>=HIGH_FRAME_CYCLES : quiet_halfbits>=quiet_target;
    wire byte_gap_exceeded=baud>19200 ? quiet_cycles>HIGH_BYTE_CYCLES : quiet_halfbits>char_bits*3+1;
    wire ms_tick=ms_div==SYS_CLK_HZ/1000-1;
    wire tx_ready,tx_busy,tx_done,rx_valid,rx_start,rx_frame_error,rx_parity_error,rx_busy;
    wire [7:0] rx_byte;
    wire de_grant,rx_enable;
    wire tx_request=state==DE_GUARD || state==SEND || state==LAST_STOP;
    wire tx_valid=state==SEND && de_grant;
    reg [7:0] tx_byte;
    assign req_ready=enable && state==IDLE && (!SHARED_BUS || bus_grant);
    assign bus_request=enable && (req_valid || state!=IDLE);
    assign busy=state!=IDLE;
    function [15:0] crc_update;
        input [15:0] c;input [7:0] b;reg [15:0] v;integer i;
        begin v=c^{8'd0,b};for(i=0;i<8;i=i+1)v=v[0]?(v>>1)^16'ha001:v>>1;crc_update=v;end
    endfunction
    function [7:0] request_byte;
        input [5:0] index;
        begin case(index)
            0:request_byte=slave;1:request_byte=func;2:request_byte=address[15:8];3:request_byte=address[7:0];
            4:request_byte=0;5:request_byte={3'd0,quantity};6:request_byte={2'd0,quantity,1'b0};
            default:request_byte=payload[(index-7)*8+:8];
        endcase end
    endfunction
    always @*begin
        if(tx_index==tx_len)tx_byte=tx_crc[7:0];
        else if(tx_index==tx_len+1)tx_byte=tx_crc[15:8];
        else tx_byte=request_byte(tx_index);
    end
    rs485_halfduplex_ctrl #(.GUARD_TICKS(SYS_CLK_HZ/1000000+1)) direction(
        .clk(sys_clk),.rst_n(rst_sys_n && enable),.tx_request(tx_request),.uart_busy(tx_busy),
        .de(rs485_de),.tx_grant(de_grant),.rx_enable(rx_enable));
    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) tx(.sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.enable(enable),
        .baud_hz(baud),.data_bits(4'd8),.parity_mode(parity),.stop_bits(stops),
        .byte_valid(tx_valid),.byte_ready(tx_ready),.byte_data(tx_byte),.txd(uart_txd),.busy(tx_busy),.frame_done_pulse(tx_done));
    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) rx(.sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.enable(enable && rx_enable),
        .baud_hz(baud),.data_bits(4'd8),.parity_mode(parity),.stop_bits(stops),.rxd(uart_rxd),
        .byte_valid(rx_valid),.byte_ready(1'b1),.byte_data(rx_byte),.byte_start_pulse(rx_start),
        .framing_error_pulse(rx_frame_error),.parity_error_pulse(rx_parity_error),.busy(rx_busy));
    task finish_attempt;
        input [3:0] why;
        begin
            if(why!=0)begin attempt_error_pulse<=1;attempt_error<=why;end
            if(why!=0 && why!=4 && retries<max_retries)begin
                retries<=retries+1'b1;state<=QUIET;quiet_halfbits<=0;quiet_cycles<=0;half_acc<=0;elapsed_ms<=0;
            end else begin error<=why;done<=1;state<=IDLE;end
        end
    endtask
    integer k;
    always @(posedge sys_clk)begin
        if(!rst_sys_n || !enable)begin
            state<=IDLE;slave<=1;func<=3;address<=0;timeout<=200;quantity<=1;payload<=0;
            baud<=19200;parity<=0;stops<=1;retries<=0;max_retries<=0;
            tx_len<=0;tx_index<=0;build_index<=0;rx_count<=0;response<=0;tx_crc<=16'hffff;rx_crc<=16'hffff;
            half_acc<=0;ms_div<=0;elapsed_ms<=0;quiet_halfbits<=0;quiet_cycles<=0;rx_bad<=0;rx_seen<=0;
            done<=0;error<=0;exception_code<=0;read_data<=0;response_timestamp<=0;response_time_sync<=0;
            attempt_error_pulse<=0;attempt_error<=0;
        end else begin
            done<=0;attempt_error_pulse<=0;
            if(ms_tick)begin ms_div<=0;if(elapsed_ms!=65535)elapsed_ms<=elapsed_ms+1'b1;end else ms_div<=ms_div+1'b1;
            if(rx_busy || rx_start || rx_valid || tx_busy)begin quiet_halfbits<=0;half_acc<=0;end
            else if(half_tick)begin half_acc<=half_sum-SYS_CLK_HZ;if(quiet_halfbits<quiet_target)quiet_halfbits<=quiet_halfbits+1'b1;end
            else half_acc<=half_sum[31:0];
            if(rx_busy || rx_start || rx_valid || tx_busy || quiet_halfbits==0)quiet_cycles<=0;
            else if(quiet_cycles<HIGH_FRAME_CYCLES)quiet_cycles<=quiet_cycles+1'b1;
            case(state)
                IDLE:if(req_valid && req_ready)begin
                    error<=0;exception_code<=0;read_data<=0;slave<=req_slave;func<=req_function;address<=req_address;
                    quantity<=req_quantity;payload<=req_write_data;baud<=baud_hz;parity<=parity_mode;stops<=stop_bits;
                    timeout<=timeout_ms;max_retries<=retry_limit;retries<=0;tx_crc<=16'hffff;build_index<=0;
                    tx_len<=req_function==8'h03 ? 6 : 7+{req_quantity,1'b0};
                    quiet_halfbits<=0;quiet_cycles<=0;half_acc<=0;elapsed_ms<=0;ms_div<=0;
                    if(req_slave==0 || req_slave>247 || (req_function!=3 && req_function!=16) ||
                       req_quantity==0 || req_quantity>16 || baud_hz<1200 || baud_hz>115200 || baud_hz>SYS_CLK_HZ/16 ||
                       parity_mode>2 || stop_bits==0 || stop_bits>2 || timeout_ms==0)
                        begin error<=6;done<=1;end
                    else state<=BUILD;
                end
                BUILD:begin
                    tx_crc<=crc_update(tx_crc,request_byte(build_index));
                    if(build_index==tx_len-1)state<=QUIET;else build_index<=build_index+1'b1;
                end
                QUIET:if(frame_quiet)begin state<=DE_GUARD;tx_index<=0;end
                    else if(elapsed_ms>=timeout)finish_attempt(1);
                DE_GUARD:if(de_grant)state<=SEND;
                SEND:if(tx_valid && tx_ready)begin
                    if(tx_index==tx_len+1)state<=LAST_STOP;else tx_index<=tx_index+1'b1;
                end
                LAST_STOP:if(tx_done)state<=TURN;
                TURN:if(!rs485_de)begin
                    state<=RECEIVE;rx_count<=0;response<=0;rx_crc<=16'hffff;rx_bad<=0;rx_seen<=0;
                    elapsed_ms<=0;ms_div<=0;quiet_halfbits<=0;quiet_cycles<=0;half_acc<=0;
                end
                RECEIVE:begin
                    if(rx_start && !rx_seen)begin response_timestamp<=timestamp_now;response_time_sync<=time_sync_valid;rx_seen<=1;end
                    if(rx_start && rx_count!=0 && byte_gap_exceeded)rx_bad<=1;
                    if(rx_frame_error || rx_parity_error)rx_bad<=1;
                    if(rx_valid)begin
                        if(rx_count<40)begin response[rx_count*8+:8]<=rx_byte;rx_count<=rx_count+1'b1;end else rx_bad<=1;
                        rx_crc<=crc_update(rx_crc,rx_byte);
                    end
                    if(rx_count!=0 && !rx_busy && frame_quiet)state<=CHECK;
                    else if(elapsed_ms>=timeout)finish_attempt(1);
                end
                CHECK:begin
                    if(rx_bad)finish_attempt(5);
                    else if(rx_crc!=0)finish_attempt(2);
                    else if(response[7:0]!=slave)finish_attempt(3);
                    else if(response[15:8]==(func|8'h80) && rx_count==5)begin exception_code<=response[23:16];finish_attempt(4);end
                    else if(response[15:8]!=func)finish_attempt(3);
                    else if(func==3)begin
                        if(rx_count!=5+{quantity,1'b0} || response[23:16]!={2'd0,quantity,1'b0})finish_attempt(3);
                        else begin read_data<=response[279:24];finish_attempt(0);end
                    end else if(rx_count!=8 || {response[23:16],response[31:24]}!=address ||
                                {response[39:32],response[47:40]}!={11'd0,quantity})finish_attempt(3);
                    else finish_attempt(0);
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
