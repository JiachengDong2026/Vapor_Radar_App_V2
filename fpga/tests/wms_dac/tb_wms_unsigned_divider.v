`timescale 1ns/1ps
module tb_wms_unsigned_divider;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,start=0;reg [95:0] num=0,den=1;
    wire busy,done;wire [95:0] q,r;
    integer i;
    wms_unsigned_divider dut(.clk(clk),.rst_n(rst),.start(start),.numerator(num),.denominator(den),.busy(busy),.done(done),.quotient(q),.remainder(r));
    initial begin
        repeat(3)@(negedge clk);rst=1;
        for(i=0;i<32;i=i+1)begin
            @(negedge clk);num={$random,$random,$random};den={64'd0,$random}|1;start=1;
            @(negedge clk);start=0;wait(done);#1;
            if(q!==num/den || r!==num%den)$fatal(1,"DIVIDER_MISMATCH");
        end
        @(negedge clk);start=1;@(negedge clk);start=0;repeat(8)@(negedge clk);rst=0;
        @(negedge clk);if(busy || done)$fatal(1,"DIVIDER_RESET");
        $display("TEST_PASS tb_wms_unsigned_divider vectors=32 plus reset");$finish;
    end
    initial begin #1000000;$fatal(1,"TIMEOUT");end
endmodule
