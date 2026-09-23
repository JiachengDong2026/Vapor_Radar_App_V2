`default_nettype none
// DM422: count active PUL edges. STOP completes the current high and low
// interval before releasing ENA. ENA precedes DIR, then DIR precedes PUL.
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
    // DM422 minima include +100 ppm clock frequency and 50 ns differential
    // FPGA/PCB/edge uncertainty budget. Products are 64-bit elaboration only.
    localparam integer FAST_SYS_HZ=SYS_CLK_HZ+(SYS_CLK_HZ+9999)/10000;
    localparam integer MIN_HIGH=(64'd2550*FAST_SYS_HZ+999999999)/1000000000;
    localparam integer MIN_DIR=(64'd5050*FAST_SYS_HZ+999999999)/1000000000;
    localparam integer ENA_GUARD=(64'd5000050*FAST_SYS_HZ+999999999)/1000000000;
    localparam integer MAX_FREQUENCY=SYS_CLK_HZ/(2*MIN_HIGH);
    localparam IDLE=0,ENA_WAIT=1,DIR_WAIT=2,HIGH=3,LOW=4;
    reg [2:0] state;
    reg enabled,direction,pending_direction,pulse_active,ena_active,stop_pending;
    reg [2:0] polarity;
    reg [31:0] target,freq,high_ticks,dir_ticks,period,timer;
    reg known_register,writable_register;
    wire selected=cfg_valid && cfg_addr[31:8]==24'h000067;
    wire [7:0] offset=cfg_addr[7:0];
    reg [2:0] calc_state;
    reg [31:0] calc_frequency,calc_period,calc_actual;
    wire divider_busy,divider_done;
    wire [31:0] calculated_period;
    wire frequency_write=selected && cfg_write && offset==8'h14;
    wire frequency_invalid=busy || cfg_wstrb!=4'hf || cfg_wdata==0 || cfg_wdata>MAX_FREQUENCY;
    wire divider_start=(frequency_write && !frequency_invalid && calc_state==0 && !divider_busy) || calc_state==2;
    config_divider u_divider(.clk(sys_clk),.rst_n(rst_sys_n),.start(divider_start),
        .numerator(SYS_CLK_HZ),.denominator(calc_state==2?calc_period:cfg_wdata),.busy(divider_busy),.done(divider_done),.quotient(calculated_period));
    assign cfg_ready=selected && (!frequency_write || frequency_invalid || (calc_state==4 && calc_frequency==cfg_wdata));
    wire stop_now=!system_enable || !enabled || (cfg_ready && cfg_write && !cfg_error &&
        ((offset==8'h2c && cfg_wdata==2) || (offset==8'h04 && !cfg_wdata[0])));
    assign busy=state!=IDLE;
    assign pul=pulse_active ^ polarity[0];
    assign dir=direction ^ polarity[1];
    assign ena=ena_active ^ polarity[2];
    always @* begin
        cfg_rdata=0;cfg_error=0;cfg_error_code=0;known_register=1;writable_register=1;
        case(offset)
            8'h00:cfg_rdata=32'h00470100;
            8'h04:cfg_rdata={31'd0,enabled};
            8'h08:cfg_rdata={24'd0,(|error_status),3'd0,busy,1'b0,!busy,enabled};
            8'h0c:cfg_rdata=error_status;
            8'h10:cfg_rdata=target;
            8'h14:cfg_rdata=freq;
            8'h18:cfg_rdata=high_ticks;
            8'h1c:cfg_rdata=dir_ticks;
            8'h20:cfg_rdata=0;
            8'h24:cfg_rdata=position;
            8'h28:cfg_rdata=remaining;
            8'h2c:cfg_rdata=0;
            8'h30:cfg_rdata={29'd0,polarity};
            8'h34:cfg_rdata=motion_id;
            default:begin cfg_error=1;known_register=0;end
        endcase
        if(cfg_write)begin
            if(cfg_wstrb!=4'hf)cfg_error=1;
            case(offset)
                8'h04:if(cfg_wdata[31:2]!=0 || (busy && cfg_wdata[1]))cfg_error=1;
                8'h0c:begin end
                8'h10,8'h24:if(busy)cfg_error=1;
                8'h14:if(frequency_invalid || (calc_state==4 && calc_period<high_ticks+MIN_HIGH))cfg_error=1;
                8'h18:if(busy || cfg_wdata<MIN_HIGH || cfg_wdata>period-MIN_HIGH)cfg_error=1;
                8'h1c:if(busy || cfg_wdata<MIN_DIR)cfg_error=1;
                8'h20:if(busy || cfg_wdata!=0)cfg_error=1;
                8'h2c:if(cfg_wdata<1 || cfg_wdata>3 || (cfg_wdata!=2 && busy) || (cfg_wdata==1 && (!enabled || !system_enable)))cfg_error=1;
                8'h30:if(busy || enabled || cfg_wdata>7)cfg_error=1;
                default:begin cfg_error=1;writable_register=0;end
            endcase
        end
        if(cfg_addr[1:0]!=0)cfg_error=1;
        if(!selected)cfg_error=0;
        if(cfg_error)begin
            cfg_error_code=7;
            // Reasons follow the same predicates that rejected the transfer.
            case(offset)
                8'h04:if(busy && cfg_wdata[1] && cfg_wdata[31:2]==0)cfg_error_code=8;
                8'h10,8'h24:if(busy)cfg_error_code=8;
                8'h14:if(busy && cfg_wdata!=0 && cfg_wdata<=MAX_FREQUENCY)cfg_error_code=8;
                8'h18:if(busy && cfg_wdata>=MIN_HIGH && cfg_wdata<=period-MIN_HIGH)cfg_error_code=8;
                8'h1c:if(busy && cfg_wdata>=MIN_DIR)cfg_error_code=8;
                8'h20:if(busy && cfg_wdata==0)cfg_error_code=8;
                8'h2c:if(cfg_wdata>=1 && cfg_wdata<=3)begin
                    if(cfg_wdata!=2 && busy)cfg_error_code=8;
                    else if(cfg_wdata==1 && (!enabled || !system_enable))cfg_error_code=11;
                end
                8'h30:if((busy || enabled) && cfg_wdata<=7)cfg_error_code=8;
            endcase
            if(cfg_wstrb!=4'hf)cfg_error_code=7;
            if(cfg_write && !writable_register)cfg_error_code=6;
            if(!known_register || cfg_addr[1:0]!=0)cfg_error_code=5;
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            state<=IDLE;enabled<=0;direction<=0;pending_direction<=0;pulse_active<=0;ena_active<=0;stop_pending<=0;
            polarity<=0;target<=0;freq<=1000;high_ticks<=MIN_HIGH;dir_ticks<=MIN_DIR;
            period<=SYS_CLK_HZ/1000;timer<=0;motion_id<=0;position<=0;remaining<=0;
            done_pulse<=0;error_status<=0;calc_state<=0;calc_frequency<=0;calc_period<=1;calc_actual<=0;
        end else begin
            done_pulse<=0;
            if(divider_start && calc_state==0)begin calc_state<=1;calc_frequency<=cfg_wdata;end
            if(calc_state==1 && divider_done)begin calc_period<=calculated_period;calc_state<=2;end
            if(calc_state==2)calc_state<=3;
            if(calc_state==3 && divider_done)begin calc_actual<=calculated_period;calc_state<=4;end
            if(calc_state==4 && (!frequency_write || calc_frequency!=cfg_wdata || cfg_ready))calc_state<=0;
            if(busy && (!system_enable || !enabled))stop_pending<=1;
            if(cfg_ready && cfg_write)begin
                if(cfg_error)error_status<=error_status|32'h10;
                else case(offset)
                    8'h04:begin
                        enabled<=cfg_wdata[0];
                        if(cfg_wdata[1])begin error_status<=0;remaining<=0;position<=0;end
                    end
                    8'h0c:error_status<=error_status & ~cfg_wdata;
                    8'h10:target<=cfg_wdata;
                    8'h14:begin freq<=calc_actual;period<=calc_period;end
                    8'h18:high_ticks<=cfg_wdata;
                    8'h1c:dir_ticks<=cfg_wdata;
                    8'h24:position<=cfg_wdata;
                    8'h30:polarity<=cfg_wdata[2:0];
                    8'h2c:case(cfg_wdata)
                        1:begin
                            motion_id<=motion_id+1'b1;stop_pending<=0;pending_direction<=target[31];
                            remaining<=target[31]?(~target+1'b1):target;
                            if(target==0)done_pulse<=1;
                            else begin state<=ENA_WAIT;ena_active<=1;timer<=ENA_GUARD-1;end
                        end
                        2:if(busy)stop_pending<=1;
                        3:begin position<=0;remaining<=0;end
                    endcase
                endcase
            end
            case(state)
                ENA_WAIT:begin
                    if(stop_pending || stop_now)begin state<=IDLE;ena_active<=0;done_pulse<=1;end
                    else if(timer==0)begin
                        direction<=pending_direction;state<=DIR_WAIT;timer<=dir_ticks-1;
                    end else timer<=timer-1'b1;
                end
                DIR_WAIT:begin
                    if(stop_pending || stop_now)begin state<=IDLE;ena_active<=0;done_pulse<=1;end
                    else if(timer==0)begin
                        state<=HIGH;pulse_active<=1;timer<=high_ticks-1;remaining<=remaining-1'b1;
                        position<=direction?position-1'b1:position+1'b1;
                    end else timer<=timer-1'b1;
                end
                HIGH:if(timer==0)begin state<=LOW;pulse_active<=0;timer<=period-high_ticks-1;end
                     else timer<=timer-1'b1;
                LOW:if(timer==0)begin
                    if(remaining==0 || stop_pending || stop_now)begin state<=IDLE;ena_active<=0;done_pulse<=1;end
                    else begin
                        state<=HIGH;pulse_active<=1;timer<=high_ticks-1;remaining<=remaining-1'b1;
                        position<=direction?position-1'b1:position+1'b1;
                    end
                end else timer<=timer-1'b1;
            endcase
        end
    end
endmodule
`default_nettype wire
