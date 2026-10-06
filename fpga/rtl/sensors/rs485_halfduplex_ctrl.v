module rs485_halfduplex_ctrl #(
    parameter integer GUARD_TICKS=101
)(
    input wire clk,input wire rst_n,input wire tx_request,input wire uart_busy,
    output reg de,output wire tx_grant,output wire rx_enable
);
    reg [1:0] state;
    reg [31:0] count;
    assign tx_grant=state==2 && tx_request;
    assign rx_enable=!de;
    always @(posedge clk)begin
        if(!rst_n)begin state<=0;count<=0;de<=0;end
        else case(state)
            0:if(tx_request)begin de<=1;count<=GUARD_TICKS-1;state<=1;end
            1:if(count==0)state<=2;else count<=count-1'b1;
            2:if(!tx_request && !uart_busy)begin count<=GUARD_TICKS-1;state<=3;end
            3:if(count==0)begin de<=0;state<=0;end else count<=count-1'b1;
            default:begin state<=0;de<=0;end
        endcase
    end
endmodule
