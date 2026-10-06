`timescale 1ns/1ps
module tb_watchdog;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,kick=0;reg[31:0] timeout=0;
    wire expired;wire[31:0] count;
    watchdog #(.SYS_CLK_HZ(10000)) dut(clk,rst,timeout,kick,expired,count);
    integer pulses=0;
    always @(posedge clk) if(expired) pulses=pulses+1;
    initial begin
        repeat(3) @(negedge clk);rst=1;
        repeat(40) @(negedge clk); if(count!=0)$fatal(1,"disabled");
        timeout=2;repeat(12) @(negedge clk);kick=1;
        @(negedge clk);kick=0;repeat(19) @(negedge clk);
        if(count!=0)$fatal(1,"kick reset interval");
        repeat(3) @(negedge clk);if(count!=1)$fatal(1,"expiry");
        timeout=0;repeat(40) @(negedge clk);if(count!=1)$fatal(1,"disable");
        timeout=3;repeat(20) @(negedge clk);timeout=4;
        repeat(39) @(negedge clk);if(count!=1)$fatal(1,"reconfigure restart");
        repeat(4) @(negedge clk);if(count!=2)$fatal(1,"new interval");
        rst=0;@(negedge clk);if(count!=0 || expired)$fatal(1,"reset");
        $display("tb_watchdog_PASS");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
