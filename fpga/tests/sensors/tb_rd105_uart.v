`timescale 1ns/1ps
module tb_rd105_uart;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;reg [63:0] now=0;always @(posedge clk)now<=now+1;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire txd,rxd,online;wire [31:0] errors,drops,level;
    wire mv,sof,last;reg mr=1;wire [31:0] md,flags,cycle;wire [3:0] keep;wire [15:0] source,msg;wire [63:0] stamp;
    reg [3:0] inject=0;reg [31:0] native_temp=2500000;reg [15:0] dev_error=0;
    wire [31:0] requests,writes,last_written,channel2_requests;reg [31:0] data;
    integer packets=0,index=0,n;reg [223:0] packet=0,last_packet=0;reg [31:0] last_flags;
    modbus_cfg_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    rd105_uart #(.SYS_CLK_HZ(1000000)) dut(.sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rxd),.uart_txd(txd),
        .timestamp_now(now),.time_sync_valid(1'b1),.time_sync_seq(32'd0),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_valid(mv),.m_ready(mr),.m_data(md),.m_keep(keep),.m_sof(sof),.m_last(last),
        .m_source_id(source),.m_msg_id(msg),.m_timestamp(stamp),.m_cycle_id(cycle),.m_flags(flags),.online(online),.errors(errors),.drop_count(drops),.fifo_level(level));
    modbus_sensor_model #(.SYS_CLK_HZ(1000000),.DEVICE_KIND(1)) device(.clk(clk),.rst_n(rst),.request_txd(txd),.rs485_de(1'b0),.response_rxd(rxd),
        .inject_mode(inject),.native_temperature(native_temp),.device_error(dev_error),.request_count(requests),.write_count(writes),.last_written(last_written),.response_start_pulse(),.channel2_requests(channel2_requests));
    always @(posedge clk)if(rst && mv && mr)begin
        if(source!==16'h46 || msg!==16'h1100 || cycle!==32'hffffffff || keep!=15 || flags[2:0]!=5)$fatal(1,"RD_METADATA");
        if(sof)begin index=0;packet=0;end
        if(stamp==0 || stamp>=now)$fatal(1,"RD_TIMESTAMP");
        packet[index*32+:32]=md;index=index+1;
        if(last)begin last_packet=packet;last_flags=flags;packets=packets+1;end
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        for(n=0;n<=18;n=n+1)bus.read32('h6600+4*n,data);
        bus.outside('h10006600);bus.outside('h6100);bus.expect_error(0,'h6601,0);bus.expect_error(1,'h6624,0);
        bus.expect_error(1,'h6618,1);bus.expect_error(1,'h661c,3);bus.expect_error(1,'h6620,25000001);
        bus.write32('h662c,1);bus.write32('h6620,25000000);bus.write32('h6604,5);
        wait(packets>=1);if(last_written!=2500000 || last_packet[95:64]!=25000000 || last_packet[159:128]!=25000000)$fatal(1,"RD_UNIT_CONVERSION");
        bus.read32('h6640,data);if(data!=25000000)$fatal(1,"TARGET_CONFIRM");
        // Write failure must not promote shadow target to confirmed active value.
        inject=5;bus.write32('h6620,30000000);bus.write32('h6604,5);bus.expect_error(1,'h6604,5);
        wait(errors[6]);bus.read32('h6640,data);if(data!=25000000)$fatal(1,"FAILED_WRITE_CHANGED_ACTIVE");
        inject=0;bus.write32('h6620,-32'sd12500000);bus.write32('h6604,5);
        wait(last_written== -32'sd1250000);wait(online);native_temp=-32'sd1000000;n=packets;wait(packets>n+1);
        if(last_packet[159:128]!==-32'sd10000000)$fatal(1,"NEGATIVE_ACTUAL");
        native_temp=999999999;dev_error=16'h20;n=packets;wait(packets>n+1);
        if(!last_flags[4] || last_packet[31:16]!=2 || last_packet[127:96]!=='h04030002 || last_packet[159:128]!=32)$fatal(1,"SENTINEL_OR_DEVICE_ERROR");
        inject=1;bus.read32('h6630,data);while(data==0)bus.read32('h6630,data);
        inject=6;wait(errors[0]);inject=0;native_temp=2500000;dev_error=0;wait(online);
        mr=0;wait(drops!=0);mr=1;wait(level==0);
        bus.write32('h6604,0);bus.write32('h6604,2);bus.read32('h6648,data);if(data)$fatal(1,"RD_RESET");
        bus.write32('h661c,2);bus.write32('h6604,1);n=packets;wait(packets>n);if(channel2_requests<2)$fatal(1,"RD_CHANNEL_OFFSET");
        $display("TEST_PASS tb_rd105_uart read target/actual/error, unit conversion, confirmed write, invalid sentinel, exceptions, CRC/timeout, FIFO overflow, reset");$finish;
    end
    initial begin #25000000;$fatal(1,"TIMEOUT");end
endmodule
