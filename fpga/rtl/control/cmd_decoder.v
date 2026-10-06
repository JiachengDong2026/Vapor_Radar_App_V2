`default_nettype none
// Executes only a CRC-validated vlp_cmd_rx candidate. Parser storage remains
// owned until the complete response is accepted; failed CRC never reaches cfg.
module cmd_decoder #(parameter integer CFG_TIMEOUT=2048, ACTION_TIMEOUT=10000000)(
    input wire sys_clk,rst_sys_n,
    input wire [63:0] timestamp_now,
    input wire command_valid,
    output reg command_done,
    input wire [31:0] command_status,command_sequence,command_payload_bytes,
    input wire [15:0] command_source,command_id,
    output reg [31:0] payload_read_word,
    input wire [31:0] payload_read_data,
    output reg cfg_valid,cfg_write,
    output reg [31:0] cfg_addr,cfg_wdata,
    output wire [3:0] cfg_wstrb,
    input wire cfg_ready,cfg_error,
    input wire [31:0] cfg_rdata,
    output reg action_valid,
    input wire action_ready,
    input wire [31:0] action_status,
    output wire [15:0] action_code,action_source,
    output wire [127:0] action_args,
    output wire m_valid,
    input wire m_ready,
    output wire [31:0] m_data,
    output wire [3:0] m_keep,
    output wire m_sof,m_last,
    output wire [15:0] m_source_id,m_msg_id,
    output reg [63:0] m_timestamp,
    output wire [31:0] m_cycle_id,m_flags,
    output reg [7:0] m_frame_type,
    output wire [31:0] m_sequence,
    output wire m_sequence_valid,
    input wire [3:0] cfg_error_code
);
    localparam IDLE=0,PARAM_WAIT=1,PARAM_USE=2,DECODE=3,READ_HEADER=4,READ_BUS=5,
      WRITE_WAIT=6,WRITE_USE=7,WRITE_BUS=8,MASK_READ=9,MASK_WRITE=10,ACTION=11,
      PING_WAIT=12,PING_COPY=13,CAPS=14,FINISH=15,TX_WAIT=16,TX=17,CHECK_PAGES=18,REGISTER_DISPATCH=19,RELEASE=20;
    reg [4:0] state;
    reg [31:0] p [0:3];
    reg [31:0] index,word_count,response_bytes,status,wait_count,tx_index;
    reg [1:0] param_index;
    reg [7:0] check_page,last_page;
    reg auto_action;
    (* ram_style="block" *) reg [31:0] response [0:1023];
    reg [31:0] response_data;
    reg [9:0] response_read_addr;
    reg response_write;
    reg [9:0] response_write_addr;
    reg [31:0] response_write_data;
    wire [32:0] register_end={1'b0,p[0]}+({17'd0,p[1][15:0]}<<2);
    wire [32:0] register_last=register_end-1'b1;
    wire register_range_ok=p[0][1:0]==0 && p[0][31:16]==0 && p[1][15:0]!=0 && register_end<=65536;
    wire register_state=state==READ_BUS || state==WRITE_BUS || state==MASK_READ || state==MASK_WRITE;
    function source_known;
        input [15:0] src;
        begin case(src)
            16'h1,16'h2,16'h10,16'h11,16'h20,16'h21,16'h30,16'h31,
            16'h40,16'h41,16'h42,16'h43,16'h44,16'h45,16'h46,16'h47,16'h50,16'hffff:source_known=1;
            default:source_known=0;
        endcase end
    endfunction
    function source_owns;
        input [15:0] src;input [7:0] page;
        begin case(src)
            16'h1,16'hffff:source_owns=1;
            16'h2:source_owns=page==8'h10;
            16'h10:source_owns=page==8'h20 || page==8'h30;
            16'h11:source_owns=page==8'h21 || page==8'h31;
            16'h20:source_owns=page==8'h40;
            16'h21:source_owns=page==8'h41;
            16'h30:source_owns=page==8'h50;
            16'h31:source_owns=page==8'h51;
            16'h40,16'h41,16'h42,16'h43,16'h44,16'h45,16'h46,16'h47:source_owns=page==src[7:0]+8'h20;
            16'h50:source_owns=page==8'h70 || page==8'h80;
            default:source_owns=0;
        endcase end
    endfunction
    // DAC pages commit their owning WMS channel, preserving the coordinated
    // stop/DAC-commit/WMS-commit/restore sequence in action_controller.
    function [15:0] commit_source;
        input [7:0] page;
        begin case(page)
            8'h20,8'h30:commit_source=16'h10;
            8'h21,8'h31:commit_source=16'h11;
            8'h40:commit_source=16'h20;8'h41:commit_source=16'h21;
            8'h50:commit_source=16'h30;8'h51:commit_source=16'h31;
            8'h60,8'h61,8'h62,8'h63,8'h64,8'h65,8'h66:commit_source={8'd0,page}-16'h20;
            default:commit_source=16'hffff;
        endcase end
    endfunction
    wire [15:0] auto_source=commit_source(p[0][15:8]);
    assign cfg_wstrb=4'hf;
    assign action_code=auto_action?16'h5:command_id;
    assign action_source=auto_action?auto_source:command_source;
    assign action_args=auto_action?(128'd1<<auto_source[5:0]):{p[3],p[2],p[1],p[0]};
    assign m_valid=state==TX;
    assign m_data=response_data;
    assign m_sof=tx_index==0;
    assign m_last=tx_index==(response_bytes+3)/4-1;
    assign m_keep=(!m_last || response_bytes[1:0]==0)?4'hf:((1<<response_bytes[1:0])-1);
    assign m_source_id=command_source;
    assign m_msg_id=command_id;
    assign m_cycle_id=32'hffffffff;
    assign m_flags=1;
    assign m_sequence=command_sequence;
    assign m_sequence_valid=1;
    always @* begin
        response_read_addr=0;
        if(state==TX)response_read_addr=tx_index+(m_ready && !m_last);
    end
    // One physical write port is required for block RAM inference. Multiple
    // procedural array assignments with different addresses infer 32768 FFs.
    always @*begin
        response_write=0;response_write_addr=0;response_write_data=0;
        case(state)
            DECODE:if(command_id==2)begin response_write=1;response_write_addr=1;response_write_data=p[0];end
            READ_HEADER:begin response_write=1;response_write_addr=2;response_write_data={16'd0,word_count[15:0]};end
            READ_BUS:if(cfg_ready && !cfg_error)begin response_write=1;response_write_addr=index+3;response_write_data=cfg_rdata;end
            PING_COPY:begin response_write=1;response_write_addr=index+1;response_write_data=payload_read_data;end
            FINISH:begin response_write=1;response_write_data=status;end
            CAPS:begin
                response_write=1;response_write_addr=index;
                case(index)
                    1:response_write_data=32'h0000ffff;
                    2:response_write_data=32'h00000100;
                    3:response_write_data=100000000;
                    4:response_write_data=8192;
                    5:response_write_data=4096;
                    6:response_write_data=32'h00000001;
                    default:response_write=0;
                endcase
            end
        endcase
    end
    always @(posedge sys_clk)begin
        response_data<=response[response_read_addr];
        if(rst_sys_n && response_write)response[response_write_addr]<=response_write_data;
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            state<=IDLE;command_done<=0;payload_read_word<=0;cfg_valid<=0;cfg_write<=0;cfg_addr<=0;cfg_wdata<=0;
            action_valid<=0;m_timestamp<=0;m_frame_type<=2;index<=0;word_count<=0;response_bytes<=4;status<=0;
            wait_count<=0;tx_index<=0;param_index<=0;p[0]<=0;p[1]<=0;p[2]<=0;p[3]<=0;
            auto_action<=0;check_page<=0;last_page<=0;
        end else begin
            command_done<=0;
            if(!cfg_valid && !action_valid)wait_count<=0;
            else if((cfg_valid && cfg_ready) || (action_valid && action_ready))wait_count<=0;
            else wait_count<=wait_count+1'b1;
            case(state)
                IDLE:if(command_valid)begin
                    status<=command_status;response_bytes<=4;index<=0;tx_index<=0;
                    m_timestamp<=timestamp_now;m_frame_type<=command_status==0?8'h02:8'h7f;
                    param_index<=0;payload_read_word<=0;
                    auto_action<=0;
                    if(command_status!=0)state<=FINISH;else state<=PARAM_WAIT;
                end
                PARAM_WAIT:state<=PARAM_USE;
                PARAM_USE:begin
                    p[param_index]<=command_payload_bytes>param_index*4?payload_read_data:0;
                    if(param_index==3)state<=DECODE;
                    else begin param_index<=param_index+1'b1;payload_read_word<=param_index+1'b1;state<=PARAM_WAIT;end
                end
                DECODE:begin
                    status<=0;
                    if(!source_known(command_source))begin status<=4;state<=FINISH;end
                    else if(command_id==4 && !source_owns(command_source,p[0][15:8]))begin status<=4;state<=FINISH;end
                    else
                    case(command_id)
                        16'h01:if(command_payload_bytes!=0)begin status<=2;state<=FINISH;end
                            else begin response_bytes<=28;index<=1;state<=CAPS;end
                        16'h02:if(command_payload_bytes!=8 || p[1][31:16]!=0)begin status<=2;state<=FINISH;end
                            else if(!register_range_ok || p[1][15:0]>1021)begin status<=7;state<=FINISH;end
                            else begin
                                word_count<=p[1][15:0];index<=0;
                                check_page<=p[0][15:8];last_page<=register_last[15:8];state<=CHECK_PAGES;
                            end
                        16'h03:if(command_payload_bytes!=8+p[1][15:0]*4 || p[1][31:17]!=0)begin status<=2;state<=FINISH;end
                            else if(!register_range_ok)begin status<=7;state<=FINISH;end
                            else if(p[1][16] && p[0][15:8]!=register_last[15:8])begin status<=7;state<=FINISH;end
                            else if(p[1][16] && auto_source==16'hffff)begin status<=13;state<=FINISH;end
                            else begin
                                word_count<=p[1][15:0];index<=0;payload_read_word<=2;
                                check_page<=p[0][15:8];last_page<=register_last[15:8];state<=CHECK_PAGES;
                            end
                        16'h04:if(command_payload_bytes!=12)begin status<=2;state<=FINISH;end
                            else if(p[0][1:0]!=0 || p[0][31:16]!=0)begin status<=7;state<=FINISH;end
                            else begin cfg_valid<=1;cfg_write<=0;cfg_addr<=p[0];state<=MASK_READ;end
                        16'h05,16'h06,16'h07,16'h08,16'h09,16'h0a,16'h0b,16'h0c,16'h0d:begin
                            if(((command_id==5 || command_id==8 || command_id==9) && command_payload_bytes!=8) ||
                               ((command_id==6 || command_id==7 || command_id==10) && command_payload_bytes!=16) ||
                               ((command_id==11 || command_id==12 || command_id==13) && command_payload_bytes!=8))begin
                                status<=2;state<=FINISH;
                            end else begin action_valid<=1;state<=ACTION;end
                        end
                        16'hfe:begin
                            response_bytes<=command_payload_bytes+4;index<=0;payload_read_word<=0;
                            if(command_payload_bytes==0)state<=FINISH;else state<=PING_WAIT;
                        end
                        default:begin status<=1;state<=FINISH;end
                    endcase
                end
                // Validate every traversed page before the first bus operation.
                CHECK_PAGES:begin
                    if(!source_owns(command_source,check_page))begin status<=4;state<=FINISH;end
                    else if(check_page==last_page)state<=REGISTER_DISPATCH;
                    else check_page<=check_page+1'b1;
                end
                REGISTER_DISPATCH:begin
                    if(command_id==2)begin response_bytes<=12+word_count*4;state<=READ_HEADER;end
                    else state<=WRITE_WAIT;
                end
                READ_HEADER:begin
                    cfg_valid<=1;cfg_write<=0;cfg_addr<=p[0];state<=READ_BUS;
                end
                READ_BUS:if(cfg_ready)begin
                    if(cfg_error)begin status<={28'd0,cfg_error_code};cfg_valid<=0;response_bytes<=4;state<=FINISH;end
                    else begin
                        if(index==word_count-1)begin cfg_valid<=0;state<=FINISH;end
                        else begin index<=index+1'b1;cfg_addr<=cfg_addr+4;end
                    end
                end
                WRITE_WAIT:state<=WRITE_USE;
                WRITE_USE:begin cfg_valid<=1;cfg_write<=1;cfg_addr<=p[0]+index*4;cfg_wdata<=payload_read_data;state<=WRITE_BUS;end
                WRITE_BUS:if(cfg_ready)begin
                    cfg_valid<=0;
                    if(cfg_error)begin status<={28'd0,cfg_error_code};state<=FINISH;end
                    else if(index==word_count-1)begin
                        if(p[1][16])begin auto_action<=1;action_valid<=1;state<=ACTION;end
                        else state<=FINISH;
                    end else begin index<=index+1'b1;payload_read_word<=index+3;state<=WRITE_WAIT;end
                end
                MASK_READ:if(cfg_ready)begin
                    if(cfg_error)begin status<={28'd0,cfg_error_code};cfg_valid<=0;state<=FINISH;end
                    else begin cfg_write<=1;cfg_wdata<=(cfg_rdata & ~p[1]) | (p[2] & p[1]);state<=MASK_WRITE;end
                end
                MASK_WRITE:if(cfg_ready)begin cfg_valid<=0;if(cfg_error)status<={28'd0,cfg_error_code};state<=FINISH;end
                ACTION:if(action_ready)begin action_valid<=0;status<=action_status;state<=FINISH;end
                PING_WAIT:state<=PING_COPY;
                PING_COPY:begin
                    if((index+1)*4>=command_payload_bytes)state<=FINISH;
                    else begin index<=index+1'b1;payload_read_word<=index+1'b1;state<=PING_WAIT;end
                end
                CAPS:begin
                    if(index==6)state<=FINISH;else index<=index+1'b1;
                end
                FINISH:begin tx_index<=0;state<=TX_WAIT;end
                TX_WAIT:state<=TX;
                TX:if(m_ready)begin
                    if(m_last)begin command_done<=1;state<=RELEASE;end
                    else tx_index<=tx_index+1'b1;
                end
                RELEASE:state<=IDLE;
            endcase
            if(register_state && cfg_valid && !cfg_ready && wait_count>=CFG_TIMEOUT-1)begin
                cfg_valid<=0;status<=9;response_bytes<=4;state<=FINISH;
            end
            if(state==ACTION && action_valid && !action_ready && wait_count>=ACTION_TIMEOUT-1)begin
                action_valid<=0;status<=9;state<=FINISH;
            end
        end
    end
endmodule
`default_nettype wire
