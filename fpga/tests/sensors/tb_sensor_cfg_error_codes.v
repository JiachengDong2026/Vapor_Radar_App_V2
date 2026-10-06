`timescale 1ns/1ps
module tb_sensor_cfg_error_codes;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0,cw=0;reg [31:0] ca=0,cd=0;reg [3:0] ws=15;
    wire ready,error;wire [31:0] rd;wire [27:0] reasons;
    integer checks=0,lane;reg [31:0] saved;
    member3_sensor_bank #(.FIFO_DEPTH(16),.PTB_BOOT_MS(1)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(64'd0),.time_sync_valid(1'b0),.time_sync_seq(32'd0),.sync_event_pulse(1'b0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(ws),.cfg_ready(ready),.cfg_error(error),.cfg_rdata(rd),.cfg_error_code(reasons),
        .ptb_rxd(1'b1),.rs485_rxd(1'b1),.epsilon_rxd(1'b1),.tfa_hf_rxd(1'b1),.tfa_lf_rxd(1'b1),
        .scl_i(1'b1),.sda_i(1'b1),.bmp_int(1'b0),.m_ready(7'h7f));
    task access;input integer l;input write;input [7:0] ofs;input [31:0] value;input [3:0] strobes,code;
        reg [27:0] expected;begin
            @(negedge clk);cv=1;cw=write;ca=32'h6000+l*256+ofs;cd=value;ws=strobes;
            expected=0;expected[l*4+:4]=code;#1;
            if(!ready||error!==(code!=0)||reasons!==expected)$fatal(1,"cfg lane=%d ofs=%h wr=%b data=%h strobes=%h ready=%b err=%b codes=%h expected=%h",l,ofs,write,value,strobes,ready,error,reasons,expected);
            checks=checks+1;@(negedge clk);cv=0;cw=0;#1;
            if(ready||error||reasons!=0)$fatal(1,"inactive cfg reason not zero");
        end
    endtask
    task read_value;input integer l;input [7:0] ofs;begin
        @(negedge clk);cv=1;cw=0;ca=32'h6000+l*256+ofs;#1;
        if(!ready||error||reasons!=0)$fatal(1,"read_value failed");saved=rd;
        @(negedge clk);cv=0;#1;
    end endtask
    task unchanged;input integer l;input [7:0] ofs;input [31:0] prior;begin
        read_value(l,ofs);if(saved!==prior)$fatal(1,"rejected cfg modified register lane=%d ofs=%h",l,ofs);
    end endtask
    reg [31:0] before_value;
    initial begin
        repeat(10)@(negedge clk);rst=1;repeat(5)@(negedge clk);
        for(lane=0;lane<7;lane=lane+1)begin
            access(lane,0,8'h00,0,15,0);
            access(lane,0,8'hfc,0,15,5);access(lane,1,8'hfc,0,15,5);
            access(lane,0,8'h01,0,15,5);access(lane,1,8'h01,32'hffffffff,15,5);
            access(lane,1,8'h00,0,15,6);access(lane,1,8'h08,0,15,6);
            access(lane,1,8'h04,32'h10,15,7);
            access(lane,1,8'h04,32'hffffffff,0,0);
        end
        // Per-device range restrictions while idle.
        access(0,1,8'h10,0,15,7);access(0,1,8'h14,0,15,7);access(0,1,8'h18,0,15,7);access(0,1,8'h1c,2,15,7);access(0,1,8'h2c,0,15,7);
        access(1,1,8'h14,248,15,7);access(1,1,8'h18,6,15,7);access(1,1,8'h20,4,15,7);access(1,1,8'h34,32'h7f800000,15,7);
        access(2,1,8'h10,0,15,7);access(2,1,8'h1c,2,15,7);
        access(3,1,8'h10,8'h75,15,7);access(3,1,8'h18,63,15,7);access(3,1,8'h1c,18,15,7);access(3,1,8'h20,1,15,7);access(3,1,8'h24,4,15,7);access(3,1,8'h38,1,15,7);
        access(4,1,8'h10,8'h44,15,6);access(4,1,8'h14,0,15,7);access(4,1,8'h18,3,15,7);access(4,1,8'h1c,7,15,7);access(4,1,8'h1c,2,15,7);
        access(5,1,8'h10,115199,15,7);access(5,1,8'h14,3,15,7);access(5,1,8'h18,5,15,7);access(5,1,8'h18,1,0,7);access(5,1,8'h3c,0,15,7);access(5,1,8'h4c,1001,15,7);
        access(6,1,8'h18,1,15,7);access(6,1,8'h1c,9,15,7);access(6,1,8'h20,32'd25000001,15,7);access(6,1,8'h20,-32'sd400000001,15,7);access(6,1,8'h2c,0,15,7);
        // Valid writes are unchanged, and masked invalid upper bytes are ignored.
        access(0,1,8'h10,32'hffff4b00,3,0);read_value(0,8'h10);if(saved!=19200)$fatal(1,"WSTRB merge");
        for(lane=0;lane<7;lane=lane+1)access(lane,1,8'h04,1,15,0);
        read_value(0,8'h10);before_value=saved;access(0,1,8'h10,9600,15,8);access(0,1,8'h10,0,15,7);unchanged(0,8'h10,before_value);
        access(0,1,8'h14,8'h48,15,8);access(0,1,8'h14,0,15,7);
        access(1,1,8'h10,38400,15,7);access(1,1,8'h18,1,15,7);access(1,1,8'h10,19200,15,8);access(1,1,8'h10,0,15,7);access(1,1,8'h14,240,15,8);access(1,1,8'h14,0,15,7);
        access(1,1,8'h18,0,15,8);access(1,1,8'h18,6,15,7);access(1,1,8'h1c,1000,15,8);access(1,1,8'h1c,0,15,7);access(1,1,8'h20,3,15,8);access(1,1,8'h20,0,15,7);
        access(1,1,8'h04,5,15,0);access(1,1,8'h04,5,15,8);access(1,1,8'h04,32'h15,15,7);
        access(2,1,8'h10,500000,15,8);access(2,1,8'h10,0,15,7);
        access(3,1,8'h10,8'h76,15,8);access(3,1,8'h10,8'h75,15,7);
        access(4,1,8'h14,1000,15,8);access(4,1,8'h14,0,15,7);access(4,1,8'h18,1,15,8);access(4,1,8'h18,3,15,7);access(4,1,8'h1c,0,15,8);access(4,1,8'h1c,2,15,7);
        access(5,1,8'h18,1,15,8);access(5,1,8'h18,5,15,7);access(5,1,8'h4c,10,15,8);access(5,1,8'h4c,0,15,7);
        access(5,1,8'h50,0,15,8);access(5,1,8'h50,256,15,7);access(5,1,8'h58,8'hcb,15,8);access(5,1,8'h58,256,15,7);
        access(6,1,8'h10,19200,15,8);access(6,1,8'h14,1,15,8);access(6,1,8'h18,0,15,8);access(6,1,8'h18,1,15,7);
        access(6,1,8'h1c,1,15,8);access(6,1,8'h1c,9,15,7);access(6,1,8'h2c,1000,15,8);access(6,1,8'h2c,0,15,7);
        access(6,1,8'h04,5,15,0);access(6,1,8'h04,5,15,8);access(6,1,8'h04,32'h15,15,7);
        @(negedge clk);cv=1;ca=32'h6700;cw=1;#1;if(ready||error||reasons!=0)$fatal(1,"unselected bank page");
        $display("tb_sensor_cfg_error_codes_PASS checks=%0d lanes=7 address_readonly_range_busy WSTRB rejected_write_atomicity packed_sidebands",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"cfg reason timeout");end
endmodule
