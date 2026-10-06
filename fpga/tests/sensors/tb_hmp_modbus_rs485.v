`timescale 1ns/1ps
module tb_hmp_modbus_rs485;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;reg [63:0] now=0;always @(posedge clk)now<=now+1;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire txd,rxd,de,online;wire [31:0] errors,drops,level;
    wire mv,sof,last;reg mr=1;wire [31:0] md,flags,cycle;wire [3:0] keep;wire [15:0] source,msg;wire [63:0] stamp;
    reg [3:0] inject=0;wire [31:0] requests,writes,last_written;reg [31:0] data;
    integer packets=0,index=0,n;reg [223:0] packet=0,last_packet=0;reg [31:0] last_flags;reg [63:0] first_ts;
    modbus_cfg_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    hmp_modbus_rs485 #(.SYS_CLK_HZ(1000000)) dut(.sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rxd),.uart_txd(txd),.rs485_de(de),
        .timestamp_now(now),.time_sync_valid(1'b1),.time_sync_seq(32'd0),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_valid(mv),.m_ready(mr),.m_data(md),.m_keep(keep),.m_sof(sof),.m_last(last),
        .m_source_id(source),.m_msg_id(msg),.m_timestamp(stamp),.m_cycle_id(cycle),.m_flags(flags),.online(online),.errors(errors),.drop_count(drops),.fifo_level(level));
    modbus_sensor_model #(.SYS_CLK_HZ(1000000),.DEVICE_KIND(0)) device(.clk(clk),.rst_n(rst),.request_txd(txd),.rs485_de(de),.response_rxd(rxd),
        .inject_mode(inject),.native_temperature(32'd0),.device_error(16'd0),.request_count(requests),.write_count(writes),.last_written(last_written),.response_start_pulse());
    always @(posedge clk)if(rst && mv && mr)begin
        if(source!==16'h41 || msg!==16'h1100 || cycle!==32'hffffffff || keep!=15 || flags[2:0]!=5)$fatal(1,"HMP_METADATA");
        if(sof)begin index=0;packet=0;first_ts=stamp;end
        if(stamp!==first_ts || stamp==0 || stamp>=now)$fatal(1,"HMP_TIMESTAMP");
        packet[index*32+:32]=md;index=index+1;
        if(last)begin last_packet=packet;last_flags=flags;packets=packets+1;end
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        for(n=0;n<=18;n=n+1)bus.read32('h6100+4*n,data);
        bus.read32('h6118,data);if(data!=1)$fatal(1,"HMP_DEFAULT_8N2");
        bus.outside('h10006100);bus.outside('h6600);bus.expect_error(0,'h6101,0);bus.expect_error(1,'h6124,0);
        bus.expect_error(1,'h6120,4);bus.expect_error(1,'h6134,'h7fc00000);
        bus.masked('h6134,'h00002000,2);bus.read32('h6134,data);if(data!=='h447d2000)$fatal(1,"HMP_WSTRB");
        bus.write32('h6134,'h447d5000);bus.write32('h611c,1);bus.write32('h6104,5);
        wait(packets>=1);if(last_packet[95:64]!=='h42480000 || last_packet[159:128]!=='h41cc0000 || last_packet[63:32]!=='h04090100)$fatal(1,"HMP_F32_TLV");
        if(last_written!=='h447d5000 || writes!=1)$fatal(1,"PRESSURE_DEVICE_WRITE");
        bus.read32('h6140,data);if(data!=='h447d5000)$fatal(1,"PRESSURE_CONFIRMED");
        bus.expect_error(1,'h6110,9600);
        inject=1;wait(requests>=5);wait(errors[1]);bus.read32('h612c,data);if(data==0)$fatal(1,"CRC_COUNT");
        inject=6;wait(errors[0]);bus.read32('h6130,data);if(data==0)$fatal(1,"TIMEOUT_COUNT");
        inject=0;wait(online);mr=0;wait(drops!=0);if(!errors[2])repeat(3)@(negedge clk);
        if(!errors[2])$fatal(1,"FIFO_OVERFLOW_VISIBLE");
        mr=1;wait(level==0);bus.write32('h610c,'hffffffff);
        inject=10;n=packets;wait(packets>n+1);if(!last_flags[4])$fatal(1,"NAN_FLAG");
        bus.write32('h6104,0);bus.write32('h6104,2);bus.read32('h6148,data);if(data)$fatal(1,"SOFT_RESET_COUNTER");
        $display("TEST_PASS tb_hmp_modbus_rs485 F32 word order, pressure device commit, cfg, CRC/timeout/retry, FIFO backpressure/overflow, NaN, reset");$finish;
    end
    initial begin #20000000;$fatal(1,"TIMEOUT");end
endmodule
