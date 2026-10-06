`timescale 1ns/1ps
module tb_time_sync_core;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,sync_pin=0,tag_valid=0;reg[63:0] tag=64'd1700000000000000;
    wire[63:0] ticks,event_tick,event_tag;wire valid,event_pulse,event_tag_valid;
    wire[31:0] seq,errors;
    reg cv=0,cw=0;reg[31:0] ca=0,cd=0;reg[3:0] cs=0;
    wire cr,ce;wire[31:0] rd;
    time_sync_core #(.SYS_CLK_HZ(10000)) dut(clk,rst,sync_pin,tag,tag_valid,ticks,valid,seq,event_pulse,event_tick,event_tag,event_tag_valid,errors,cv,cw,ca,cd,cs,cr,rd,ce,1'b1,);
    reg[31:0] got;reg[63:0] t0,previous=0;integer events=0;
    always @(negedge clk) if(rst)begin
        if(previous!=0 && ticks!=previous+1)$fatal(1,"time must be monotonic");
        previous=ticks;if(event_pulse)events=events+1;
    end else previous=0;
    task write_reg;input[31:0] addr,data;input[3:0] strobe;input expect_error;
      begin @(negedge clk);cv=1;cw=1;ca=addr;cd=data;cs=strobe;#1;
        if(!cr || ce!==expect_error)$fatal(1,"write response addr=%h",addr);
        @(negedge clk);cv=0;cw=0;cs=0;end
    endtask
    task read_reg;input[31:0] addr;begin
        @(negedge clk);cv=1;cw=0;ca=addr;#1;got=rd;
        if(!cr || ce)$fatal(1,"read");@(negedge clk);cv=0;end endtask
    task pulse;begin @(negedge clk);sync_pin=1;repeat(6)@(negedge clk);sync_pin=0;repeat(6)@(negedge clk);end endtask
    initial begin
        repeat(3)@(negedge clk);rst=1;
        write_reg('h1028,5,15,0);write_reg('h1028,0,15,1);
        read_reg('h1028);if(got!=5)$fatal(1,"invalid mutated state");
        write_reg('h1000,0,15,1);write_reg('h1024,2,15,1);
        @(negedge clk);cv=1;ca='h9999;#1;if(cr||ce)$fatal(1,"wrong page");cv=0;
        tag_valid=1;@(negedge clk);tag_valid=0;pulse;
        if(!valid || seq!=1 || event_tag!=tag || !event_tag_valid)$fatal(1,"first edge");
        t0=event_tick;repeat(5)@(negedge clk);pulse;
        read_reg('h102c);if(got!=event_tick-t0)$fatal(1,"interval");
        repeat(60)@(negedge clk);if(valid||!(errors&1))$fatal(1,"sync timeout");
        write_reg('h100c,1,1,0);if(errors&1)$fatal(1,"W1C");
        write_reg('h1024,1,1,0);pulse;
        if(seq!=3 || !valid)$fatal(1,"falling edge");
        write_reg('h1004,0,1,0);pulse;if(seq!=3 || valid)$fatal(1,"disabled");
        t0=ticks;write_reg('h1004,3,1,0);if(ticks<t0)$fatal(1,"soft reset time");
        pulse;if(seq!=4)$fatal(1,"restart");
        read_reg('h1010);read_reg('h1014);if(got!=0)$fatal(1,"snapshot");
        $display("tb_time_sync_core_PASS");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
