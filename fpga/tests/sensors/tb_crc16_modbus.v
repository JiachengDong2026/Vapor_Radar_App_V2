`timescale 1ns/1ps
module tb_crc16_modbus;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,clear=0,valid=0;reg [7:0] data=0;wire [15:0] crc;
    integer i;
    crc16_modbus dut(.clk(clk),.rst_n(rst),.clear(clear),.valid(valid),.data(data),.crc(crc));
    task vector;
        input [127:0] bytes;input integer length;input [15:0] expected;integer j;
        begin
            @(negedge clk);clear=1;valid=0;@(negedge clk);clear=0;
            for(j=0;j<length;j=j+1)begin valid=1;data=bytes[j*8+:8];@(negedge clk);end
            valid=0;if(crc!==expected)$fatal(1,"CRC_KNOWN_VECTOR got=%h expected=%h",crc,expected);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=1;
        vector(128'h393837363534333231,9,16'h4b37);
        vector(128'h020000100301,6,16'hcbc0);
        vector(128'ha025260004020000101001,11,16'h4cc5);
        vector(128'h020000101001,6,16'h0845);
        vector(128'ha0252600040301,7,16'h1001);
        vector(128'h0400000003f0,6,16'h2851);
        vector(128'h008000,3,16'h0010);
        vector(128'hff,1,16'h00ff);
        vector(128'h00000000,4,16'h2400);
        vector(128'h010007000301,6,16'hcb35);
        clear=1;@(negedge clk);clear=0;if(crc!==16'hffff)$fatal(1,"CRC_CLEAR");
        $display("TEST_PASS tb_crc16_modbus 10 known vectors including RD105 manual and 123456789=4B37");$finish;
    end
endmodule
