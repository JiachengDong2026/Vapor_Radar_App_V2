`timescale 1ns/1ps
module tb_msg_stream_hex_uart;
    reg clk=0;always #20 clk=~clk;
    reg rst=0,v=0;wire ready,tx;
    reg [31:0] data=32'h89abcdef,flags=5;reg [3:0] keep=7;
    reg sof=1,last=0;reg [15:0] source_id='h43,msg_id='h1100;
    reg [63:0] timestamp=64'h0123456789abcdef;
    msg_stream_hex_uart dut(.sys_clk(clk),.rst_sys_n(rst),.s_valid(v),.s_ready(ready),
        .s_data(data),.s_flags(flags),.s_keep(keep),.s_sof(sof),.s_last(last),
        .s_source_id(source_id),.s_msg_id(msg_id),.s_timestamp(timestamp),.txd(tx));
    reg [575:0] line=0;reg [7:0] b;integer bit_index,count=0,lines=0;
    initial forever begin
        @(negedge tx);#13020.833;
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin b[bit_index]=tx;#8680.556;end
        if(tx!==1)$fatal(1,"UART stop");line={line[567:0],b};count=count+1;
        if(count==72)begin
            if(lines==0&&line!={"SRC=0043 MSG=1100 T=0123456789ABCDEF D=89ABCDEF F=00000005 K=7 S=1 L=0",8'h0d,8'h0a})
                $fatal(1,"first line mismatch %s",line);
            if(lines==1&&line!={"SRC=0044 MSG=1401 T=0000000000000001 D=00000100 F=00000001 K=F S=1 L=1",8'h0d,8'h0a})
                $fatal(1,"second line mismatch %s",line);
            count=0;lines=lines+1;
        end
    end
    initial begin
        repeat(10)@(negedge clk);rst=1;
        @(negedge clk);v=1;@(negedge clk);v=0;
        // Change source immediately after capture; serialization must retain it.
        source_id='h44;msg_id='h1401;timestamp=1;data='h100;flags=1;keep=15;last=1;
        repeat(100)@(negedge clk);if(ready)$fatal(1,"missing backpressure");
        wait(ready);@(negedge clk);v=1;@(negedge clk);v=0;
        wait(lines==2);$display("MSG_STREAM_HEX_UART_PASS lines=2");$finish;
    end
    initial begin #20000000;$fatal(1,"watchdog");end
endmodule
