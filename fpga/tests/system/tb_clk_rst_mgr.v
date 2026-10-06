`timescale 1ns/1ps
module tb_clk_rst_mgr;
    reg refclk=0;always #5 refclk=~refclk;
    reg reset=0,sw=0;wire sys,gpif,rs,rg,locked,persistent;integer n;
    clk_rst_mgr #(.SIMULATION(1))dut(refclk,reset,sw,sys,gpif,rs,rg,locked,persistent);
    initial begin
        #17;reset=1;
        wait(locked);#1;if(rs||rg)$fatal(1,"reset released at lock");
        for(n=0;n<15;n=n+1)begin @(posedge refclk);#1;if(rs||rg)$fatal(1,"release too early");end
        @(posedge refclk);#1;if(!rs||!rg||persistent)$fatal(1,"release missing or persistent early");
        @(posedge refclk);#1;if(!persistent)$fatal(1,"persistent release missing");
        #2;sw=1;#1;if(rs||rg||!persistent)$fatal(1,"not async asserted or persistent lost");
        @(negedge refclk);sw=0;repeat(15)begin @(posedge refclk);#1;if(rs)$fatal(1,"software early release");end
        @(posedge refclk);#1;if(!rs)$fatal(1,"software reset stuck");
        reset=0;#1;if(rs||rg||locked||persistent)$fatal(1,"external reset");
        $display("tb_clk_rst_mgr_PASS");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
