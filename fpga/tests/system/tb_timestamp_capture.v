`timescale 1ns/1ps
module tb_timestamp_capture;
    reg sys=0,evclk=0;always #5 sys=~sys;always #7 evclk=~evclk;
    reg rst=0,event_pulse=0,ready=0;
    reg[63:0] ticks=0,held;wire busy,valid;wire[63:0] value;wire[31:0] rejected;
    always @(posedge sys)if(!rst)ticks<=0;else ticks<=ticks+1;
    timestamp_capture dut(evclk,rst,event_pulse,busy,rejected,sys,rst,ticks,valid,ready,value);
    task send;begin @(negedge evclk);event_pulse=1;@(negedge evclk);event_pulse=0;end endtask
    initial begin
        repeat(4)@(negedge evclk);rst=1;send;
        wait(valid);#1;held=value;
        if(!busy || held==0 || held>ticks)$fatal(1,"capture time");
        send;
        repeat(12)begin @(negedge sys);if(!valid || value!=held)$fatal(1,"stall");end
        if(rejected!=1)$fatal(1,"busy reject");
        ready=1;@(negedge sys);ready=0;wait(!busy);send;
        wait(valid);if(value<=held)$fatal(1,"next event");
        rst=0;@(negedge sys);if(valid||busy)$fatal(1,"reset");
        rst=1;send;wait(valid);ready=1;repeat(10)@(negedge sys);
        if(valid||busy)$fatal(1,"duplicate event");
        $display("tb_timestamp_capture_PASS");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
