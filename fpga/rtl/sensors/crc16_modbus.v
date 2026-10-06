module crc16_modbus(
    input wire clk,input wire rst_n,input wire clear,input wire valid,
    input wire [7:0] data,output reg [15:0] crc
);
    function [15:0] update;
        input [15:0] c;input [7:0] b;reg [15:0] v;integer i;
        begin v=c^{8'd0,b};for(i=0;i<8;i=i+1)v=v[0]?(v>>1)^16'ha001:v>>1;update=v;end
    endfunction
    always @(posedge clk)begin
        if(!rst_n || clear)crc<=16'hffff;
        else if(valid)crc<=update(crc,data);
    end
endmodule
