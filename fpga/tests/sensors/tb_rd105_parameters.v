`timescale 1ns/1ps
module tb_rd105_parameters;
    reg clk=0;always #250 clk=~clk;
    reg rst=0,locked=0;reg [63:0] ticks=0;always @(posedge clk)ticks<=ticks+1;
    wire cv,cw,cr,ce,tx,rx,de;
    wire [31:0] ca,cd,rd,requests,writes;wire [3:0] strobe;
    reg [31:0] value;integer old_writes;
    modbus_cfg_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strobe),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    modbus_sensor_driver #(.SYS_CLK_HZ(2000000),.DEVICE_KIND(1)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx),.uart_txd(tx),.rs485_de(de),.bus_grant(1'b1),
        .timestamp_now(ticks),.time_sync_valid(1'b1),.time_sync_seq(32'd1),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strobe),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_ready(1'b1));
    modbus_register_slave_bfm #(.DEVICE_KIND(1)) model(.rst_n(rst),.master_txd(tx),.master_de(de),.lock_writes(locked),
        .exception_address(16'hffff),.rxd(rx),.requests(requests),.writes(writes));
    task wait_parameter;
        input integer count;
        begin value=0;while(value<count)bus.read32('h6890,value);end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;
        bus.read32('h6800,value);if(value!='h00480103)$fatal(1,"RD105 independent version");
        bus.outside('h6600);bus.write32('h6810,100000);bus.write32('h682c,1);bus.write32('h6804,1);
        // PID is a two-register int32. The payload bus stores wire bytes low first.
        bus.write32('h6884,'h1400);bus.write32('h6888,2);bus.write32('h68c0,'hb80b0000);
        bus.write32('h6880,2);wait_parameter(1);
        bus.read32('h688c,value);if(value[7:0]!=0)$fatal(1,"RD105 parameter write");
        bus.read32('h68e0,value);if(value!='hb80b0000 || model.memory['h1401]!=3000)$fatal(1,"RD105 parameter readback byte order");
        locked=1;old_writes=writes;bus.write32('h68c0,'hb90b0000);bus.write32('h6880,2);wait_parameter(2);
        bus.read32('h688c,value);if(value[3:0]!=3 || writes!=old_writes+1)$fatal(1,"RD105 lock/mismatch/retry");
        // Setpoint confirmation also needs a readback, not just a write ACK.
        bus.write32('h6820,30000000);bus.write32('h6804,5);
        value=4;while(value[2])bus.read32('h6808,value);
        bus.read32('h6848,value);if(value!=0)$fatal(1,"RD105 false setpoint confirmation");
        bus.write32('h6880,1);bus.write32('h6804,0);wait_parameter(3);
        bus.read32('h688c,value);if(value[3:0]!=5)$fatal(1,"RD105 pending cancellation");
        bus.expect_error(1,'h6880,1);bus.expect_error(1,'h6888,17);
        $display("TEST_PASS tb_rd105_parameters source/page separation, multi-register PID readback, locked write mismatch, no retry, setpoint confirmation, disabled rejection");$finish;
    end
    initial begin #700000000;$fatal(1,"RD105 parameter timeout");end
endmodule
