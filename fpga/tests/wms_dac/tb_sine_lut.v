`timescale 1ns/1ps
module tb_sine_lut;
    reg clk=0;always #5 clk=~clk;
    reg [31:0] phase=0;
    wire signed [31:0] value;
    reg [31:0] expected;
    integer f,r,n;
    sine_lut dut(.clk(clk),.phase(phase),.sin_value(value));
    initial begin
        f=$fopen("sine_vectors.txt","r");if(!f)$fatal(1,"VECTOR_OPEN");n=0;
        while(!$feof(f))begin
            @(negedge clk);r=$fscanf(f,"%h %h\n",phase,expected);
            @(posedge clk);#1;if(r==2 && value!==expected)$fatal(1,"LUT %h actual=%h expected=%h",phase,value,expected);
            n=n+1;
        end
        $display("TEST_PASS tb_sine_lut vectors=%0d",n);$finish;
    end
endmodule
