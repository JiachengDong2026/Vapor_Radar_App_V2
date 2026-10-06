`default_nettype none
// Actions are completion handshakes: action_valid stays high until ready.
// The register decoder serializes command writers; the other cfg master may poll.
module action_controller #(
    parameter integer CFG_TIMEOUT=2048,
    parameter integer ACTION_TIMEOUT=200000000,
    parameter integer STOP_DRAIN_TICKS=2048
)(
    input wire sys_clk,rst_sys_n,
    input wire action_valid,
    output wire action_ready,
    output reg [31:0] action_status,
    input wire [15:0] action_code,action_source,
    input wire [127:0] action_args,
    output wire cfg_valid,cfg_write,
    output wire [31:0] cfg_addr,cfg_wdata,
    output wire [3:0] cfg_wstrb,
    input wire cfg_ready,cfg_error,
    input wire [31:0] cfg_rdata,
    input wire [1:0] channel_datapath_idle,
    input wire sensor_datapath_idle,
    output reg [1:0] stop_flush,
    output wire acquisition_running,
    output wire busy,
    input wire [3:0] cfg_error_code
);
    localparam IDLE=0,CHECK=1,EXECUTE=2,COMPLETE=3;
    localparam NOP=0,RMW=1,WRITE=2,POLL=3,ASSERT_BITS=4,DELAY=5,DRAIN=6,
               FINISH=7,SAVE_ENABLE=8,ASSERT_NONZERO=9,SAVE_ACK=10,CHECK_ACK=11,FLUSH=12;
    localparam [63:0] CHANNEL_MASK=64'h0003000300030000;
    localparam [63:0] ACQ_MASK=CHANNEL_MASK|64'h7f;
    localparam [63:0] MODULE_MASK=CHANNEL_MASK|64'hff;
    reg [1:0] state;
    reg [15:0] code,source;
    reg [127:0] args;
    reg [63:0] selected;
    reg [7:0] pc;
    reg rmw_write;
    reg [31:0] rmw_data,wait_count,action_ticks,delay_count,ack_expected;
    reg [1:0] saved_enable,running_channels;
    reg [6:0] running_sensors;
    reg [3:0] op;
    reg [31:0] address,value,mask;
    reg [31:0] validation_error;
    reg [63:0] normalized_mask,legal_mask;
    reg [15:0] item_source;
    reg selected_item;
    reg [3:0] item,step;
    wire broad_source=source==16'h1 || source==16'hffff;
    wire [1:0] channels={selected[17]|selected[33]|selected[49],selected[16]|selected[32]|selected[48]};
    wire sensors_selected=|selected[6:0];
    wire bus_operation=op==RMW || op==WRITE || op==POLL || op==ASSERT_BITS ||
                       op==SAVE_ENABLE || op==ASSERT_NONZERO || op==SAVE_ACK || op==CHECK_ACK;
    wire write_operation=op==WRITE || (op==RMW && rmw_write);
    assign action_ready=state==COMPLETE;
    assign busy=state!=IDLE && state!=COMPLETE;
    assign cfg_valid=state==EXECUTE && action_valid && bus_operation && action_ticks<ACTION_TIMEOUT-1;
    assign cfg_write=write_operation;
    assign cfg_addr=address;
    assign cfg_wdata=op==RMW?rmw_data:value;
    assign cfg_wstrb=4'hf;
    assign acquisition_running=(|running_channels)||(|running_sensors);
    function source_in_modules;
        input [15:0] s;
        begin case(s)
            16'h10,16'h11,16'h20,16'h21,16'h30,16'h31,
            16'h40,16'h41,16'h42,16'h43,16'h44,16'h45,16'h46,16'h47:source_in_modules=1;
            default:source_in_modules=0;
        endcase end
    endfunction
    function [15:0] source_at;
        input [3:0] n;
        begin case(n)
            0,2:source_at=16'h10;
            1,3:source_at=16'h11;
            4:source_at=16'h20;5:source_at=16'h21;
            6:source_at=16'h30;7:source_at=16'h31;
            default:source_at=16'h40+n-8;
        endcase end
    endfunction
    function [31:0] page_at;
        input [3:0] n;
        begin case(n)
            0:page_at=32'h2000;1:page_at=32'h2100;
            2:page_at=32'h3000;3:page_at=32'h3100;
            4:page_at=32'h4000;5:page_at=32'h4100;
            6:page_at=32'h5000;7:page_at=32'h5100;
            default:page_at=32'h6000+(n-8)*256;
        endcase end
    endfunction
    // Unspecified action values and reserved bits fail before any cfg access.
    always @*begin
        validation_error=0;normalized_mask=args[63:0];legal_mask=MODULE_MASK;
        if(code==5)legal_mask=ACQ_MASK;
        if(code==6 || code==7)legal_mask=ACQ_MASK;
        case(code)
            5,6,7,8,9:begin
                if(source==2 && (code==8 || code==9))begin
                    legal_mask=64'h4;
                    if(args[63:0]==64'hffffffffffffffff)normalized_mask=legal_mask;
                    if(|(normalized_mask&~legal_mask))validation_error=7;
                end else if(!broad_source && !source_in_modules(source))validation_error=4;
                else begin
                    if(args[63:0]==64'hffffffffffffffff && broad_source)normalized_mask=legal_mask;
                    if(|(normalized_mask&~legal_mask))validation_error=7;
                    if(!broad_source && |(normalized_mask&~(64'd1<<source[5:0])))validation_error=4;
                end
                if((code==6 || code==7) && args[127:64]!=0)validation_error=13;
            end
            10:begin
                if(!broad_source && source!=16'h50)validation_error=4;
                if(|(args[127:64]&~64'h0000000300000000))validation_error=7;
            end
            11:begin
                if(source<16'h40 || source>16'h46)validation_error=4;
                case(args[31:0])
                    1:if(args[63:32]>1)validation_error=7;
                    2,3,4:if(args[63:32]!=0)validation_error=7;
                    5:begin end
                    16:if(source!=16'h41)validation_error=4;
                    17:if(source!=16'h46)validation_error=4;
                    32:begin if(source!=16'h45)validation_error=4;if(args[63:32]>2)validation_error=7;end
                    33:begin if(source!=16'h45)validation_error=4;if(args[63:32]<1 || args[63:32]>4)validation_error=7;end
                    default:validation_error=13;
                endcase
            end
            12:begin
                if(source!=16'h47 && !broad_source)validation_error=4;
                case(args[31:0])
                    1:begin end
                    2,3:if(args[63:32]!=0)validation_error=7;
                    4:if(args[63:32]>1)validation_error=7;
                    default:validation_error=13;
                endcase
            end
            13:begin
                if(source!=2 && !broad_source)validation_error=4;
                case(args[31:0])
                    1,3:if(args[63:32]>1)validation_error=7;
                    2:if(args[63:32]!=0)validation_error=7;
                    4:if(args[63:32]==0 || args[63:32]>3600000)validation_error=7;
                    5:begin end
                    default:validation_error=13;
                endcase
            end
            default:validation_error=1;
        endcase
    end
    // Finite PC decode avoids integer divide/remainder hardware. Only pc advances;
    // cfg operands remain stable
    // during bus backpressure. No asynchronously-reset instruction RAM is used.
    always @*begin
        op=NOP;address=0;value=0;mask=0;item=0;step=0;item_source=0;selected_item=0;
        case(code)
            5:begin
                if(pc<20)begin
                    case(pc)
                        8'd0:begin item=4'd0;step=4'd0;end
                        8'd1:begin item=4'd0;step=4'd1;end
                        8'd2:begin item=4'd0;step=4'd2;end
                        8'd3:begin item=4'd0;step=4'd3;end
                        8'd4:begin item=4'd0;step=4'd4;end
                        8'd5:begin item=4'd0;step=4'd5;end
                        8'd6:begin item=4'd0;step=4'd6;end
                        8'd7:begin item=4'd0;step=4'd7;end
                        8'd8:begin item=4'd0;step=4'd8;end
                        8'd9:begin item=4'd0;step=4'd9;end
                        8'd10:begin item=4'd1;step=4'd0;end
                        8'd11:begin item=4'd1;step=4'd1;end
                        8'd12:begin item=4'd1;step=4'd2;end
                        8'd13:begin item=4'd1;step=4'd3;end
                        8'd14:begin item=4'd1;step=4'd4;end
                        8'd15:begin item=4'd1;step=4'd5;end
                        8'd16:begin item=4'd1;step=4'd6;end
                        8'd17:begin item=4'd1;step=4'd7;end
                        8'd18:begin item=4'd1;step=4'd8;end
                        8'd19:begin item=4'd1;step=4'd9;end
                        default:begin item=0;step=0;end
                    endcase
                    if(selected[16+item])case(step)
                        0:begin op=SAVE_ENABLE;address=32'h2004+item*256;end
                        1:begin op=RMW;address=32'h2004+item*256;mask=1;end
                        2:begin op=DELAY;value=16;end
                        3:begin op=POLL;address=32'h3008+item*256;mask=14;value=2;end
                        4:begin op=RMW;address=32'h3004+item*256;mask=4;value=4;end
                        5:begin op=POLL;address=32'h3008+item*256;mask=14;value=2;end
                        6:begin op=RMW;address=32'h2004+item*256;mask=4;value=4;end
                        // WMS ready also requires enabled DAC transport. A
                        // disabled pre-start commit completes on pending clear.
                        7:begin op=POLL;address=32'h2008+item*256;mask=4;value=0;end
                        8:begin op=RMW;address=32'h2004+item*256;mask=1;value=saved_enable[item];end
                        default:begin end
                    endcase
                end else if(pc<28)begin
                    item=(pc-20)/2+4;step=(pc-20)%2;item_source=source_at(item);
                    if(selected[item_source[5:0]])begin
                        address=page_at(item)+(step==0?4:8);
                        op=step==0?RMW:POLL;mask=4;value=step==0?4:0;
                    end
                end else if(pc<63)begin
                    case(pc)
                        8'd28:begin item=4'd0;step=4'd0;end
                        8'd29:begin item=4'd0;step=4'd1;end
                        8'd30:begin item=4'd0;step=4'd2;end
                        8'd31:begin item=4'd0;step=4'd3;end
                        8'd32:begin item=4'd0;step=4'd4;end
                        8'd33:begin item=4'd1;step=4'd0;end
                        8'd34:begin item=4'd1;step=4'd1;end
                        8'd35:begin item=4'd1;step=4'd2;end
                        8'd36:begin item=4'd1;step=4'd3;end
                        8'd37:begin item=4'd1;step=4'd4;end
                        8'd38:begin item=4'd2;step=4'd0;end
                        8'd39:begin item=4'd2;step=4'd1;end
                        8'd40:begin item=4'd2;step=4'd2;end
                        8'd41:begin item=4'd2;step=4'd3;end
                        8'd42:begin item=4'd2;step=4'd4;end
                        8'd43:begin item=4'd3;step=4'd0;end
                        8'd44:begin item=4'd3;step=4'd1;end
                        8'd45:begin item=4'd3;step=4'd2;end
                        8'd46:begin item=4'd3;step=4'd3;end
                        8'd47:begin item=4'd3;step=4'd4;end
                        8'd48:begin item=4'd4;step=4'd0;end
                        8'd49:begin item=4'd4;step=4'd1;end
                        8'd50:begin item=4'd4;step=4'd2;end
                        8'd51:begin item=4'd4;step=4'd3;end
                        8'd52:begin item=4'd4;step=4'd4;end
                        8'd53:begin item=4'd5;step=4'd0;end
                        8'd54:begin item=4'd5;step=4'd1;end
                        8'd55:begin item=4'd5;step=4'd2;end
                        8'd56:begin item=4'd5;step=4'd3;end
                        8'd57:begin item=4'd5;step=4'd4;end
                        8'd58:begin item=4'd6;step=4'd0;end
                        8'd59:begin item=4'd6;step=4'd1;end
                        8'd60:begin item=4'd6;step=4'd2;end
                        8'd61:begin item=4'd6;step=4'd3;end
                        8'd62:begin item=4'd6;step=4'd4;end
                        default:begin item=0;step=0;end
                    endcase
                    if(selected[item])begin
                        address=32'h6000+item*256;
                        case(step)
                            0:begin op=POLL;address=address+8;mask=4;value=0;end
                            1:if(item==1 || item==6)begin op=SAVE_ACK;address=address+32'h48;end
                            2:begin op=RMW;address=address+4;mask=4;value=4;end
                            3:begin op=POLL;address=address+8;mask=4;value=0;end
                            4:if(item==1 || item==6)begin op=CHECK_ACK;address=address+32'h48;end
                        endcase
                    end
                end else op=FINISH;
            end
            6:begin
                if(pc<8)begin
                    item=pc/4;step=pc%4;
                    if(channels[item])case(step)
                        0:begin op=ASSERT_BITS;address=32'h4008+item*256;mask=6;value=2;end
                        1:begin op=ASSERT_BITS;address=32'h5008+item*256;mask=6;value=2;end
                        2:begin op=ASSERT_BITS;address=32'h3008+item*256;mask=14;value=2;end
                        3:begin op=ASSERT_NONZERO;address=32'h202c+item*256;end
                    endcase
                end else if(pc==8)begin if(|channels || sensors_selected)begin op=RMW;address=4;mask=1;value=1;end end
                else if(pc<17)begin
                    item=(pc-9)%2;step=(pc-9)/2;
                    if(channels[item])begin op=RMW;mask=1;value=1;
                        case(step)0:address=32'h4004;1:address=32'h5004;2:address=32'h3004;default:address=32'h2004;endcase
                        address=address+item*256;
                    end
                end else if(pc<24)begin
                    item=pc-17;if(selected[item])begin op=RMW;address=32'h6004+item*256;mask=1;value=1;end
                end else op=FINISH;
            end
            7:begin
                if(pc<8)begin
                    item=pc%2;step=pc/2;
                    if(channels[item])begin op=RMW;mask=1;
                        case(step)0:address=32'h2004;1:address=32'h4004;2:address=32'h5004;default:address=32'h3004;endcase
                        address=address+item*256;
                    end
                end else if(pc<15)begin
                    item=pc-8;if(selected[item])begin op=RMW;address=32'h6004+item*256;mask=1;end
                end else case(pc)
                    15:op=FLUSH;
                    16:begin op=DELAY;value=STOP_DRAIN_TICKS;end
                    17:op=DRAIN;
                    default:op=FINISH;
                endcase
            end
            8,9:begin
                if(source==2)begin
                    if(pc==0 && selected[2])begin
                        op=code==8?RMW:WRITE;address=code==8?32'h1004:32'h100c;mask=3;value=code==8?2:32'hffffffff;
                    end else op=FINISH;
                end else if(pc<16)begin
                    item=pc;item_source=source_at(item);
                    if(selected[item_source[5:0]])begin
                        op=code==8?RMW:WRITE;address=page_at(item)+(code==8?4:12);mask=3;value=code==8?2:32'hffffffff;
                    end
                end else if(pc==16 && code==9 && broad_source)begin op=WRITE;address=12;value=32'hffffffff;end
                else op=FINISH;
            end
            10:begin
                op=WRITE;
                case(pc)
                    0:begin address=32'h2c;value=args[31:0];end
                    1:begin address=32'h30;value=args[63:32];end
                    2:begin address=32'h34;value=args[95:64];end
                    3:begin address=32'h50;value=args[127:96];end
                    4:begin address=32'h403c;value=args[96];end
                    5:begin address=32'h413c;value=args[97];end
                    default:op=FINISH;
                endcase
            end
            11:begin
                address=32'h6000+(source-16'h40)*256;
                case(args[31:0])
                    1,3,4,5:begin
                        if(pc==0)begin
                            op=args[31:0]==5?WRITE:RMW;
                            address=address+(args[31:0]==5?12:4);
                            case(args[31:0])
                                1:begin mask=1;value=args[63:32];end
                                3:begin mask=8;value=8;end
                                4:begin mask=3;value=2;end
                                5:value=args[63:32];
                            endcase
                        end else op=FINISH;
                    end
                    2,16,17:begin
                        case(pc)
                            0:begin op=POLL;address=address+8;mask=4;value=0;end
                            1:if(args[31:0]!=2)begin op=WRITE;address=address+(source==16'h41 ? 32'h34 : 32'h20);value=args[63:32];end
                            2:if(source==16'h41 || source==16'h46)begin op=SAVE_ACK;address=address+32'h48;end
                            3:begin op=RMW;address=address+4;mask=4;value=4;end
                            4:begin op=POLL;address=address+8;mask=4;value=0;end
                            5:if(source==16'h41 || source==16'h46)begin op=CHECK_ACK;address=address+32'h48;end
                            default:op=FINISH;
                        endcase
                    end
                    32,33:begin
                        if(pc==0)begin op=WRITE;address=address+(args[31:0]==32?20:24);value=args[63:32];end
                        else if(pc==1 && args[31:0]==32)begin op=POLL;address=address+8;mask=2;value=2;end
                        else op=FINISH;
                    end
                    default:op=FINISH;
                endcase
            end
            12:begin
                case(args[31:0])
                    1:case(pc)
                        0:begin op=ASSERT_BITS;address=32'h6708;mask=10;value=2;end
                        1:begin op=WRITE;address=32'h6710;value=args[63:32];end
                        2:begin op=RMW;address=4;mask=1;value=1;end
                        3:begin op=RMW;address=32'h6704;mask=1;value=1;end
                        4:begin op=WRITE;address=32'h672c;value=1;end
                        default:op=FINISH;
                    endcase
                    2:case(pc)
                        0:begin op=WRITE;address=32'h672c;value=2;end
                        1:begin op=POLL;address=32'h6708;mask=8;value=0;end
                        default:op=FINISH;
                    endcase
                    3:case(pc)
                        0:begin op=ASSERT_BITS;address=32'h6708;mask=8;value=0;end
                        1:begin op=WRITE;address=32'h672c;value=3;end
                        default:op=FINISH;
                    endcase
                    4:if(pc==0)begin op=RMW;address=32'h6704;mask=1;value=args[63:32];end else op=FINISH;
                    default:op=FINISH;
                endcase
            end
            13:begin
                if(pc==0)begin
                    case(args[31:0])
                        1:begin op=RMW;address=32'h1004;mask=1;value=args[63:32];end
                        2:begin op=RMW;address=32'h1004;mask=3;value=3;end
                        3:begin op=WRITE;address=32'h1024;value=args[63:32];end
                        4:begin op=WRITE;address=32'h1028;value=args[63:32];end
                        5:begin op=WRITE;address=32'h100c;value=args[63:32];end
                    endcase
                end else op=FINISH;
            end
            default:op=FINISH;
        endcase
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            state<=IDLE;code<=0;source<=0;args<=0;selected<=0;pc<=0;rmw_write<=0;rmw_data<=0;
            wait_count<=0;action_ticks<=0;delay_count<=0;ack_expected<=0;saved_enable<=0;
            action_status<=0;stop_flush<=0;running_channels<=0;running_sensors<=0;
        end else begin
            stop_flush<=0;
            case(state)
                IDLE:if(action_valid)begin
                    code<=action_code;source<=action_source;args<=action_args;pc<=0;rmw_write<=0;
                    wait_count<=0;action_ticks<=0;delay_count<=0;action_status<=0;state<=CHECK;
                end
                CHECK:begin
                    selected<=normalized_mask;
                    if(validation_error!=0)begin action_status<=validation_error;state<=COMPLETE;end
                    else state<=EXECUTE;
                end
                EXECUTE:begin
                    action_ticks<=action_ticks+1'b1;
                    if(!action_valid)begin state<=IDLE;rmw_write<=0;end
                    else if(action_ticks>=ACTION_TIMEOUT-1)begin action_status<=9;state<=COMPLETE;rmw_write<=0;end
                    else if(bus_operation)begin
                        if(cfg_ready)begin
                            wait_count<=0;
                            if(cfg_error)begin action_status<={28'd0,cfg_error_code};state<=COMPLETE;rmw_write<=0;end
                            else if(op==RMW && !rmw_write)begin rmw_data<=(cfg_rdata&~mask)|(value&mask);rmw_write<=1;end
                            else begin
                                rmw_write<=0;
                                if(write_operation)begin
                                    if(address==32'h2004)running_channels[0]<=cfg_wdata[0];
                                    if(address==32'h2104)running_channels[1]<=cfg_wdata[0];
                                    if(address>=32'h6004 && address<=32'h6604 && address[7:0]==4)running_sensors[address[10:8]]<=cfg_wdata[0];
                                end
                                if(op==POLL)begin if((cfg_rdata&mask)==value)pc<=pc+1'b1;end
                                else if(op==ASSERT_BITS && (cfg_rdata&mask)!=value)begin action_status<=11;state<=COMPLETE;end
                                else if(op==ASSERT_NONZERO && cfg_rdata==0)begin action_status<=11;state<=COMPLETE;end
                                else if(op==CHECK_ACK && cfg_rdata!=ack_expected)begin action_status<=14;state<=COMPLETE;end
                                else begin
                                    if(op==SAVE_ENABLE)saved_enable[address[8]]<=cfg_rdata[0];
                                    if(op==SAVE_ACK)ack_expected<=cfg_rdata+1'b1;
                                    pc<=pc+1'b1;
                                end
                            end
                        end else if(wait_count>=CFG_TIMEOUT-1)begin action_status<=9;state<=COMPLETE;rmw_write<=0;end
                        else wait_count<=wait_count+1'b1;
                    end else begin
                        wait_count<=0;
                        case(op)
                            NOP:pc<=pc+1'b1;
                            DELAY:if(delay_count>=value-1)begin delay_count<=0;pc<=pc+1'b1;end else delay_count<=delay_count+1'b1;
                            DRAIN:if((channels&~channel_datapath_idle)==0 && (!sensors_selected || sensor_datapath_idle))pc<=pc+1'b1;
                            FLUSH:begin stop_flush<=channels;pc<=pc+1'b1;end
                            FINISH:state<=COMPLETE;
                            default:begin action_status<=15;state<=COMPLETE;end
                        endcase
                    end
                end
                COMPLETE:if(!action_valid)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
