`timescale 1ns/1ps
module tb_sdfm300_baud_rates;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,rx=1,cv=0,cw=0;
    reg [31:0] ca=0,cd=0;wire cr,ce,mv,ml;wire [31:0] md;
    integer rates[0:6];integer j,k,ns_bit,packets=0;
    sdfm300_uart dut(.sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx),
        .timestamp_now(64'd1),.time_sync_valid(1'b0),.time_sync_seq(32'd0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),
        .cfg_ready(cr),.cfg_error(ce),.m_valid(mv),.m_ready(1'b1),.m_data(md),.m_last(ml));
    always @(posedge clk)if(mv&&ml)begin
        if(md!=43540)$fatal(1,"baud payload %d",md);
        packets=packets+1;
    end
    task wr;input [31:0] a,d;begin
        @(negedge clk);cv=1;cw=1;ca=a;cd=d;#1;
        if(!cr||ce)$fatal(1,"baud cfg %h %d",a,d);
        @(negedge clk);cv=0;cw=0;
    end endtask
    task serial;input [7:0] b;begin
        rx=0;#(ns_bit);for(k=0;k<8;k=k+1)begin rx=b[k];#(ns_bit);end
        rx=1;#(ns_bit);
    end endtask
    initial begin
        rates[0]=9600;rates[1]=19200;rates[2]=38400;rates[3]=115200;
        rates[4]=230400;rates[5]=256000;rates[6]=460800;
        repeat(8)@(negedge clk);rst=1;
        for(j=0;j<7;j=j+1)begin
            wr('h6504,0);wr('h6510,rates[j]);wr('h6504,1);
            ns_bit=1000000000/rates[j];repeat(20)@(negedge clk);
            serial('h5c);serial('h02);serial('h11);serial('hec);
            repeat(50)@(negedge clk);
            if(packets!=j+1)$fatal(1,"no manual frame at baud=%d packets=%d",rates[j],packets);
        end
        $display("TB_SDFM300_BAUD_RATES_PASS seven physical serial rates at SYS100MHz");$finish;
    end
    initial begin #20000000;$fatal(1,"watchdog");end
endmodule
