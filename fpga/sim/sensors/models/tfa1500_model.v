`timescale 1ns/1ps
module tfa1500_model #(parameter integer BIT_NS=2000)(output reg hf_rxd=1,output reg lf_rxd=1);
    task send_byte;input lf;input [7:0] b;integer j;begin
        if(lf) lf_rxd=0;else hf_rxd=0;#BIT_NS;
        for(j=0;j<8;j=j+1) begin if(lf) lf_rxd=b[j];else hf_rxd=b[j];#BIT_NS;end
        if(lf) lf_rxd=1;else hf_rxd=1;#BIT_NS;
    end endtask
    task high_frame;input [23:0] cm;input bad;reg [7:0] sum;begin
        sum=cm[7:0]+cm[15:8]+cm[23:16];
        send_byte(0,8'h5c);send_byte(0,cm[7:0]);send_byte(0,cm[15:8]);send_byte(0,cm[23:16]);
        send_byte(0,(~sum)^bad);
    end endtask
endmodule
