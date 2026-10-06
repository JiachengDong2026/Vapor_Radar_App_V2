module adc_debug_uart #(
    parameter integer CHANNEL=0,
    parameter integer REPORT_TICKS=50000000
)(
    input wire clk,input wire rst_n,
    input wire sample_valid,input wire [31:0] sample_data,
    output wire cfg_valid,output wire cfg_write,output wire [31:0] cfg_addr,
    output wire [31:0] cfg_wdata,output wire [3:0] cfg_wstrb,
    input wire cfg_ready,input wire [31:0] cfg_rdata,input wire cfg_error,
    output wire txd
);
    localparam integer LINE_LEN=68;
    localparam [LINE_LEN*8-1:0] TEMPLATE="ADC0 status=00000000 sample=00000000 count=00000000 error=00000000\r\n";
    reg [2:0] state;
    reg [31:0] timer,latest_sample,status_reg,sample_reg,count_reg,error_reg;
    reg [6:0] index;
    reg [7:0] byte_data;
    wire tx_ready;
    assign cfg_valid=state==0 || state==2 || state==3 || state==4;
    assign cfg_write=state==0;
    assign cfg_addr=32'h4000+CHANNEL*256+(state==0?32'h4:(state==2?32'h8:(state==3?32'h28:32'hc)));
    assign cfg_wdata=1;assign cfg_wstrb=15;
    function [7:0] hex_char;
        input [3:0] n;
        begin hex_char=n<10?8'h30+n:8'h41+n-10;end
    endfunction
    always @*begin
        byte_data=TEMPLATE>>((LINE_LEN-1-index)*8);
        if(index==3)byte_data=8'h30+CHANNEL;
        else if(index>=12 && index<20)byte_data=hex_char(status_reg>>((19-index)*4));
        else if(index>=28 && index<36)byte_data=hex_char(sample_reg>>((35-index)*4));
        else if(index>=43 && index<51)byte_data=hex_char(count_reg>>((50-index)*4));
        else if(index>=58 && index<66)byte_data=hex_char(error_reg>>((65-index)*4));
    end
    member1_uart_tx #(.SYS_CLK_HZ(100000000)) u_uart(
        .sys_clk(clk),.rst_sys_n(rst_n),.enable(1'b1),.baud_hz(32'd115200),.data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),
        .byte_valid(state==5),.byte_ready(tx_ready),.byte_data(byte_data),.txd(txd),.busy(),.frame_done_pulse());
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=0;timer<=0;latest_sample<=0;status_reg<=0;sample_reg<=0;count_reg<=0;error_reg<=0;index<=0;end
        else begin
            if(sample_valid)latest_sample<=sample_data;
            case(state)
                0:if(cfg_ready)begin state<=1;timer<=0;end
                1:if(timer==REPORT_TICKS-1)begin timer<=0;state<=2;sample_reg<=latest_sample;end else timer<=timer+1'b1;
                2:if(cfg_ready)begin status_reg<=cfg_rdata;state<=3;end
                3:if(cfg_ready)begin count_reg<=cfg_rdata;state<=4;end
                4:if(cfg_ready)begin error_reg<=cfg_rdata|(cfg_error?32'h80000000:0);index<=0;state<=5;end
                5:if(tx_ready)begin if(index==LINE_LEN-1)state<=1;else index<=index+1'b1;end
                default:state<=0;
            endcase
        end
    end
endmodule

