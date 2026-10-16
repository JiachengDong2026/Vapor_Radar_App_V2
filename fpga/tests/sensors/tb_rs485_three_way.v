`timescale 1ns/1ps
module tb_rs485_three_way;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;reg [2:0] request=0,busy=0,de=0,txd=7;
    wire [2:0] grant,rxd;wire tx,drive;
    integer i,j;
    rs485_transaction_arbiter #(.N(3)) dut(.clk(clk),.rst_n(rst),.request(request),.busy(busy),.txd(txd),.de(de),
        .uart_rxd(1'b1),.grant(grant),.rxd(rxd),.uart_txd(tx),.rs485_de(drive));
    initial begin
        repeat(3)@(negedge clk);rst=1;
        for(j=0;j<2;j=j+1)for(i=0;i<3;i=i+1)begin
            request=7;
            wait(grant==(1<<i));@(negedge clk);busy[i]=1;de[i]=1;txd[i]=0;
            repeat(5)begin @(negedge clk);if(grant!=(1<<i) || tx!=0 || !drive)$fatal(1,"RS485 ownership/interleave");end
            de[i]=0;request[i]=0;repeat(5)@(negedge clk);
            if(grant!=(1<<i))$fatal(1,"RS485 released before response/timeout");
            busy[i]=0;txd[i]=1;@(negedge clk);
        end
        rst=0;@(negedge clk);if(grant!=0 || drive || tx!=1)$fatal(1,"RS485 reset");
        $display("TEST_PASS tb_rs485_three_way fair HMP/AI8/RD105 grants, transaction ownership, quiet/response hold, reset");$finish;
    end
    initial begin #100000;$fatal(1,"RS485 timeout grant=%b",grant);end
endmodule
