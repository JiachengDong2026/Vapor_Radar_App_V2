`timescale 1ns/1ps
module tb_ai8_scan_parameters;
    reg clk=0;always #250 clk=~clk;
    reg rst=0;reg [63:0] ticks=0;always @(posedge clk)ticks<=ticks+1;
    wire cv,cw,cr,ce,tx,rx,de,mv,ml,ms;
    wire [31:0] ca,cd,rd,md,flags;wire [3:0] strobe;
    wire [15:0] source;
    reg locked=0;reg [15:0] exception_address=16'h602;
    wire [31:0] requests,writes;
    reg [31:0] value;integer i,packets=0,channel_tag=0,before_writes;
    reg [255:0] seen=0;reg [15:0] last_tag=0;
    modbus_cfg_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strobe),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    ai8_modbus_rs485 #(.SYS_CLK_HZ(2000000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx),.uart_txd(tx),.rs485_de(de),.bus_grant(1'b1),
        .timestamp_now(ticks),.time_sync_valid(1'b1),.time_sync_seq(32'd1),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strobe),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),
        .m_valid(mv),.m_ready(1'b1),.m_data(md),.m_sof(ms),.m_last(ml),.m_source_id(source),.m_flags(flags));
    modbus_register_slave_bfm model(.rst_n(rst),.master_txd(tx),.master_de(de),.lock_writes(locked),
        .exception_address(exception_address),.rxd(rx),.requests(requests),.writes(writes));
    reg header=1,tlv_value=0;
    always @(posedge clk)if(mv)begin
        if(ms)begin
            if(md[15:0]!=3 || source!=16'h46)$fatal(1,"scan schema/source");
            channel_tag=0;tlv_value=0;header=0;
        end else if(!tlv_value)begin last_tag=md[15:0];tlv_value=1;end
        else begin
            if(last_tag=='h468)channel_tag=md;
            tlv_value=0;
        end
        if(ml)begin
            if(channel_tag<1 || channel_tag>8)$fatal(1,"missing channel tag");
            seen[channel_tag]=1;packets=packets+1;
            if(channel_tag==3 && !flags[4])$fatal(1,"failed channel quality");
        end
    end
    task wait_parameter;
        input integer count;
        begin value=0;while(value<count)bus.read32('h6694,value);end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;
        bus.write32('h6610,100000);bus.write32('h662c,1);bus.write32('h6664,0);
        bus.write32('h6668,1);bus.write32('h6604,1);bus.expect_error(1,'h6668,0);
        wait(&seen[8:1]);
        for(i=1;i<=8;i=i+1)begin
            bus.write32('h6698,i);bus.read32('h66a4,value);
            if(i!=3 && value[15:0]!=199+i)$fatal(1,"cache channel %0d pv=%0d",i,value[15:0]);
            if(i==3 && value!=0)$fatal(1,"failed channel reused another snapshot");
        end
        // A setpoint for channel eight must not modify channel one or the scan.
        bus.write32('h666c,8);bus.write32('h6650,1234);bus.write32('h6604,5);
        value=0;while(value==0)bus.read32('h6648,value);
        if(model.memory[7]!=1234 || model.memory[0]!=100)$fatal(1,"setpoint channel ownership");
        // PID parameter for channel eight; write ACK is followed by FC03.
        bus.write32('h6684,'h67);bus.write32('h6688,765);bus.write32('h6680,2);wait_parameter(1);
        bus.read32('h668c,value);if(value[7:0]!=0)$fatal(1,"parameter result");
        bus.read32('h6690,value);if(value!=765)$fatal(1,"parameter readback");
        locked=1;before_writes=writes;
        bus.write32('h6688,766);bus.write32('h6680,2);wait_parameter(2);
        bus.read32('h668c,value);if(value[3:0]!=3 || writes!=before_writes+1)$fatal(1,"locked write retry/mismatch");
        bus.expect_error(1,'h6680,3); // no documented AI8 factory command
        bus.expect_error(1,'h6684,65536);
        bus.write32('h6684,'h600);bus.expect_error(1,'h6680,2);
        bus.write32('h6680,1);bus.write32('h6604,0);wait_parameter(3);
        bus.read32('h668c,value);if(value[3:0]!=5)$fatal(1,"AI8 pending cancellation");
        $display("TEST_PASS tb_ai8_scan_parameters channels 1..8, failed snapshot isolation, tagged TLVs, setpoint target, PID verified writes, lock mismatch, no retry");$finish;
    end
    initial begin #1200000000;$fatal(1,"scan timeout packets=%0d",packets);end
endmodule
