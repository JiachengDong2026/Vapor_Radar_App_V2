`timescale 1ns/1ps
module tb_rs485_halfduplex_ctrl;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,req=0,busy=0;wire de,grant,rx;
    rs485_halfduplex_ctrl #(.GUARD_TICKS(5)) dut(.clk(clk),.rst_n(rst),.tx_request(req),.uart_busy(busy),.de(de),.tx_grant(grant),.rx_enable(rx));
    initial begin
        repeat(3)@(negedge clk);rst=1;req=1;
        @(negedge clk);if(!de || grant || rx)$fatal(1,"DE_GUARD_START");
        repeat(4)@(negedge clk);if(grant)$fatal(1,"DE_GUARD_SHORT");
        @(negedge clk);if(!grant)$fatal(1,"DE_GRANT");busy=1;req=0;
        repeat(20)@(negedge clk);if(!de)$fatal(1,"DE_DROPPED_DURING_UART");
        busy=0;repeat(5)@(negedge clk);if(!de)$fatal(1,"DE_POST_GUARD_SHORT");
        repeat(2)@(negedge clk);if(de || !rx)$fatal(1,"DE_RELEASE");
        req=1;repeat(3)@(negedge clk);rst=0;@(negedge clk);if(de)$fatal(1,"DE_RESET");
        $display("TEST_PASS tb_rs485_halfduplex_ctrl pre/post guard, UART drain, reset");$finish;
    end
endmodule
