`timescale 1ns/1ps
module sdfm300_model #(parameter integer BIT_NS=2170)(output reg uart_rxd=1);
    task send_byte;input [7:0] b;integer j;begin
        uart_rxd=0;#BIT_NS;
        for(j=0;j<8;j=j+1) begin uart_rxd=b[j];#BIT_NS;end
        uart_rxd=1;#BIT_NS;
    end endtask
    task distance_frame;input [15:0] cm;input bad;reg [7:0] sum;begin
        sum=cm[7:0]+cm[15:8];
        send_byte(8'h5c);send_byte(cm[7:0]);send_byte(cm[15:8]);send_byte((~sum)^bad);
    end endtask
endmodule
