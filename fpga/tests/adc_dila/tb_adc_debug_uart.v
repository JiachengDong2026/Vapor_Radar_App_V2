`timescale 1ns/1ps
module tb_adc_debug_uart;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    wire valid,write,txd;
    wire [31:0] addr,wdata;wire [3:0] strb;
    wire [31:0] rdata=addr[7:0]==8'h08 ? 32'h12345678 : addr[7:0]==8'h28 ? 32'h9abcdef0 : 32'h00112233;
    integer enabled=0,i,j;reg [7:0] value;
    reg [543:0] expected="ADC1 status=12345678 sample=89ABCDEF count=9ABCDEF0 error=00112233\r\n";
    adc_debug_uart #(.CHANNEL(1),.REPORT_TICKS(20)) dut(.clk(clk),.rst_n(rst_n),.sample_valid(1'b1),.sample_data(32'h89abcdef),
        .cfg_valid(valid),.cfg_write(write),.cfg_addr(addr),.cfg_wdata(wdata),.cfg_wstrb(strb),.cfg_ready(valid),.cfg_rdata(rdata),.cfg_error(1'b0),.txd(txd));
    always @(posedge clk)if(rst_n&&valid&&write)begin
        if(addr!=32'h4104||wdata!=1||strb!=15)$fatal(1,"bad enable write");enabled=enabled+1;
    end
    initial begin
        #32;rst_n=1;
        for(i=0;i<68;i=i+1)begin
            @(negedge txd);#13021;
            for(j=0;j<8;j=j+1)begin value[j]=txd;#8681;end
            if(txd!==1'b1)$fatal(1,"bad stop bit");
            if(value!==((expected>>((67-i)*8))&8'hff))$fatal(1,"character %0d got %h",i,value);
        end
        if(enabled!=1)$fatal(1,"enable count");
        $display("ADC_DEBUG_UART_PASS 68bytes baud115200 8N1 register_poll");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
