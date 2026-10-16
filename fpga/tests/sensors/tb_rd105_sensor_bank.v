`timescale 1ns/1ps
module tb_rd105_sensor_bank;
    reg clk=0;always #250 clk=~clk;
    reg rst=0;reg [63:0] ticks=0;always @(posedge clk)ticks<=ticks+1;
    wire cv,cw,cr,ce,tx,rx,de;wire [31:0] ca,cd,rd;wire [3:0] strobe;
    wire [7:0] valid,last,online;wire [127:0] source;
    wire [31:0] requests,writes;reg [31:0] value;
    integer packets=0;
    modbus_cfg_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strobe),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    member3_sensor_bank #(.SYS_CLK_HZ(2000000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(ticks),.time_sync_valid(1'b1),.time_sync_seq(32'd1),.sync_event_pulse(1'b0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strobe),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),
        .ptb_rxd(1'b1),.rs485_rxd(rx),.rs485_txd(tx),.rs485_de(de),.epsilon_rxd(1'b1),.tfa_hf_rxd(1'b1),.tfa_lf_rxd(1'b1),
        .scl_i(1'b1),.sda_i(1'b1),.bmp_int(1'b0),.m_valid(valid),.m_ready(8'hff),.m_last(last),.m_source_id(source),.device_online(online));
    modbus_register_slave_bfm #(.BAUD(19200),.ADDR(2),.DEVICE_KIND(1)) model(
        .rst_n(rst),.master_txd(tx),.master_de(de),.lock_writes(1'b0),.exception_address(16'hffff),.rxd(rx),.requests(requests),.writes(writes));
    always @(posedge clk)if(valid[7] && last[7])begin
        if(source[127:112]!=16'h48 || !online[7])$fatal(1,"RD105 production lane/source");
        packets=packets+1;
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        bus.read32('h6814,value);if(value!=2)$fatal(1,"RD105 shared default address");
        bus.expect_error(1,'h6810,9600);bus.write32('h682c,1);bus.write32('h6820,25000000);bus.write32('h6804,5);
        wait(packets>=1);bus.read32('h6848,value);
        if(value!=1 || writes!=1 || online[6:0]!=0)$fatal(1,"RD105 bank setpoint/other device isolation");
        bus.write32('h6804,0);
        $display("TEST_PASS tb_rd105_sensor_bank production RD105 wrapper, third-owner DE/TX, 19200 address 2, verified target, independent source 0048 and lane");$finish;
    end
    initial begin #500000000;$fatal(1,"RD105 bank timeout");end
endmodule
