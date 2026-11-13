`include "register_map.vh"
`default_nettype none
// Register adapter for the verified DM422 controller. ENA is HIGH to disable
// the installed non-inverting 3.3V/5V converter. No synthetic heartbeat.
module stepper_ctrl #(parameter integer SYS_CLK_HZ=100000000)(
    input wire sys_clk,rst_sys_n,
    input wire system_enable,
    input wire cfg_valid,cfg_write,
    input wire [31:0] cfg_addr,cfg_wdata,
    input wire [3:0] cfg_wstrb,
    output wire cfg_ready,
    output reg [31:0] cfg_rdata,
    output reg cfg_error,
    output wire pul,dir,ena,
    output wire busy,
    output reg done_pulse,
    output reg [31:0] motion_id,position,remaining,
    output reg [31:0] error_status,
    output reg [3:0] cfg_error_code
);
    reg enabled,move_toggle,stop_toggle,heartbeat_toggle,motion_direction;
    reg [31:0] target,frequency,half_period,heartbeat_count;
    reg [15:0] motion_target,counted;
    reg [2:0] launch;
    reg core_was_busy;
    wire [31:0] core_status;
    wire core_busy=core_status[1];
    wire [15:0] sent=core_status[23:8];
    wire [31:0] magnitude=target[31]?(~target+1'b1):target;
    wire [63:0] control={half_period,target[15:0],11'd0,heartbeat_toggle,
                        target[31],stop_toggle,move_toggle,(enabled && system_enable)};
    // Signed target's magnitude is supplied below, rather than its low bits.
    wire [63:0] core_control={control[63:32],magnitude[15:0],control[15:0]};
    dm422_pc_ctrl #(.CLK_HZ(SYS_CLK_HZ),.WATCHDOG_CYCLES(2*SYS_CLK_HZ)) u_dm422(
        .clk(sys_clk),.rst_n(rst_sys_n),.control(core_control),
        .motor_pul(pul),.motor_dir(dir),.motor_disable(ena),.status(core_status));
    assign busy=core_busy || (launch!=0);
    wire selected=cfg_valid && cfg_addr[31:8]==24'h000067;
    wire [7:0] offset=cfg_addr[7:0];
    reg [2:0] calc_state;
    reg [31:0] calc_frequency,calc_half,calc_actual;
    wire divider_busy,divider_done;
    wire [31:0] quotient;
    wire frequency_write=selected && cfg_write && offset==8'h14 && cfg_addr[1:0]==0;
    wire frequency_invalid=busy || cfg_wstrb!=4'hf || cfg_wdata<20 || cfg_wdata>400;
    wire divider_start=(frequency_write && !frequency_invalid && calc_state==0 && !divider_busy) || calc_state==2;
    config_divider u_divider(.clk(sys_clk),.rst_n(rst_sys_n),.start(divider_start),
        .numerator(calc_state==2?SYS_CLK_HZ:SYS_CLK_HZ+{cfg_wdata[30:0],1'b0}-1'b1),.denominator(calc_state==2?{calc_half[30:0],1'b0}:{cfg_wdata[30:0],1'b0}),
        .busy(divider_busy),.done(divider_done),.quotient(quotient));
    assign cfg_ready=selected && (!frequency_write || frequency_invalid ||
                                (calc_state==4 && calc_frequency==cfg_wdata));
    reg known_register,writable_register;
    always @* begin
        cfg_rdata=0;cfg_error=0;cfg_error_code=0;known_register=1;writable_register=0;
        case(offset)
            8'h00:cfg_rdata=`MOTOR_ID_VERSION;
            8'h04:begin cfg_rdata={31'd0,enabled};writable_register=1;end
            8'h08:cfg_rdata={24'd0,((|error_status)||core_status[3]),core_status[0],core_status[5],
                             core_status[2],busy,1'b0,!busy,enabled};
            8'h0c:begin cfg_rdata=error_status;writable_register=1;end
            8'h10:begin cfg_rdata=target;writable_register=1;end
            8'h14:begin cfg_rdata=frequency;writable_register=1;end
            8'h18:cfg_rdata=half_period;
            8'h1c:cfg_rdata=SYS_CLK_HZ/100;
            8'h20:begin cfg_rdata=0;writable_register=1;end
            8'h24:begin cfg_rdata=position;writable_register=1;end
            8'h28:cfg_rdata=remaining;
            8'h2c:begin cfg_rdata=0;writable_register=1;end
            8'h30:begin cfg_rdata=4;writable_register=1;end
            8'h34:cfg_rdata=motion_id;
            8'h38:begin cfg_rdata=heartbeat_count;writable_register=1;end
            8'h3c:cfg_rdata=core_status;
            8'h40:cfg_rdata=SYS_CLK_HZ;
            8'h44:cfg_rdata=2000;
            8'h48:cfg_rdata=400;
            default:known_register=0;
        endcase
        if(selected)begin
            if(!known_register || cfg_addr[1:0]!=0)begin cfg_error=1;cfg_error_code=5;end
            else if(cfg_write)begin
                if(!writable_register)begin cfg_error=1;cfg_error_code=6;end
                else if(cfg_wstrb!=4'hf)begin cfg_error=1;cfg_error_code=7;end
                else case(offset)
                    8'h04:if(cfg_wdata>3 || (cfg_wdata[1] && (busy || cfg_wdata[0])))begin cfg_error=1;cfg_error_code=7;end
                    8'h10:if(busy)begin cfg_error=1;cfg_error_code=8;end
                        else if(cfg_wdata==0 || (cfg_wdata[31]?(~cfg_wdata+1'b1):cfg_wdata)>400)begin cfg_error=1;cfg_error_code=7;end
                    8'h14:if(busy)begin cfg_error=1;cfg_error_code=8;end
                        else if(frequency_invalid)begin cfg_error=1;cfg_error_code=7;end
                    8'h20:if(cfg_wdata!=0)begin cfg_error=1;cfg_error_code=7;end
                    8'h24:if(busy)begin cfg_error=1;cfg_error_code=8;end
                    8'h2c:if(cfg_wdata<1 || cfg_wdata>3)begin cfg_error=1;cfg_error_code=7;end
                        else if(cfg_wdata!=2 && busy)begin cfg_error=1;cfg_error_code=8;end
                        else if(cfg_wdata==1 && (!system_enable || !enabled || !core_status[5] || core_status[3] || ena))begin cfg_error=1;cfg_error_code=11;end
                    8'h30:if(enabled || busy)begin cfg_error=1;cfg_error_code=8;end
                        else if(cfg_wdata!=4)begin cfg_error=1;cfg_error_code=7;end
                    8'h38:if(cfg_wdata!=1)begin cfg_error=1;cfg_error_code=7;end
                    default:begin end
                endcase
            end
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            enabled<=0;move_toggle<=0;stop_toggle<=0;heartbeat_toggle<=0;
            target<=40;frequency<=100;half_period<=SYS_CLK_HZ/200;heartbeat_count<=0;
            launch<=0;core_was_busy<=0;motion_direction<=0;motion_target<=0;counted<=0;
            motion_id<=0;position<=0;remaining<=0;error_status<=0;done_pulse<=0;
            calc_state<=0;calc_frequency<=0;calc_half<=1;calc_actual<=0;
        end else begin
            done_pulse<=0;core_was_busy<=core_busy;
            if(launch!=0)launch<=launch-1'b1;
            if(divider_start && calc_state==0)begin calc_state<=1;calc_frequency<=cfg_wdata;end
            if(calc_state==1 && divider_done)begin calc_half<=quotient;calc_state<=2;end
            if(calc_state==2)calc_state<=3;
            if(calc_state==3 && divider_done)begin calc_actual<=quotient;calc_state<=4;end
            if(calc_state==4 && (!frequency_write || calc_frequency!=cfg_wdata || cfg_ready))calc_state<=0;
            if(launch==0 && sent>counted)begin
                counted<=sent;remaining<=motion_target-sent;
                position<=motion_direction?position-(sent-counted):position+(sent-counted);
            end
            if(core_was_busy && !core_busy && launch==0)done_pulse<=1;
            if(cfg_ready && cfg_write)begin
                if(cfg_error)error_status<=error_status|32'h10;
                else case(offset)
                    8'h04:begin
                        enabled<=cfg_wdata[0];
                        if(cfg_wdata[1])begin position<=0;remaining<=0;error_status<=0;end
                    end
                    8'h0c:error_status<=error_status & ~cfg_wdata;
                    8'h10:target<=cfg_wdata;
                    8'h14:begin frequency<=calc_actual;half_period<=calc_half;end
                    8'h24:position<=cfg_wdata;
                    8'h38:begin heartbeat_toggle<=!heartbeat_toggle;heartbeat_count<=heartbeat_count+1'b1;end
                    8'h2c:case(cfg_wdata)
                        1:begin
                            move_toggle<=!move_toggle;launch<=3;
                            motion_id<=motion_id+1'b1;motion_direction<=target[31];
                            motion_target<=magnitude[15:0];remaining<=magnitude;counted<=0;
                        end
                        2:stop_toggle<=!stop_toggle;
                        3:begin position<=0;remaining<=0;end
                    endcase
                    default:begin end
                endcase
            end
            if(core_status[3])error_status<=error_status|32'h1;
            // Dropping the global gate disarms the module until another host
            // enable command. Reconnecting USB must never re-enable a motor.
            if(!system_enable)enabled<=0;
        end
    end
endmodule
`default_nettype wire
