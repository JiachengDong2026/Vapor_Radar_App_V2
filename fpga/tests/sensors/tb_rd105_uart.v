`timescale 1ns/1ps
module tb_rd105_uart;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [63:0] ticks=0;always @(posedge clk)ticks<=ticks+1;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire tx,rx,de;
    wire [7:0] mv,ms,ml,on;reg [7:0] ready=255;
    wire [255:0] data,cycles,flags,errors,drops,levels;
    wire [31:0] keep,codes;wire [127:0] sources,msg;wire [511:0] stamps;
    reg [3:0] fault=0;
    wire [31:0] requests,writes,ch1,ch2,hmp,ai8;
    reg [31:0] value,old_count;integer i,n,old_writes,stage=0;
    integer tag_index,channel_value,duty_value,enable_value,actual_value,actual_seen,target_value,invalid_samples=0;
    reg [31:0] expected_ch2_target=-32'sd12500000;
    integer packets1=0,packets2=0,position=0;
    reg [31:0] packet[0:12];reg [197:0] held;reg stalled=0;
    reg [2:0] prev_grant=0,prev_busy=0;
    member3_sensor_bank #(.SYS_CLK_HZ(1000000),.HC2A_ENABLE(0)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(ticks),.time_sync_valid(1'b1),.time_sync_seq(32'd0),.sync_event_pulse(1'b0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_error(ce),.cfg_rdata(rd),.cfg_error_code(codes),
        .ptb_rxd(1'b1),.ptb_txd(),.rs485_rxd(rx),.rs485_txd(tx),.rs485_de(de),.epsilon_rxd(1'b1),.epsilon_txd(),.epsilon_correction_txd(),
        .sdfm300_rxd(1'b1),.sdfm300_txd(),.hc2a_rxd(1'b1),.hc2a_txd(),.scl_i(1'b1),.sda_i(1'b1),.bmp_int(1'b0),.scl_drive_low(),.sda_drive_low(),
        .gnss_time_tag(),.gnss_time_tag_valid(),.m_valid(mv),.m_ready(ready),.m_data(data),.m_keep(keep),.m_sof(ms),.m_last(ml),
        .m_source_id(sources),.m_msg_id(msg),.m_timestamp(stamps),.m_cycle_id(cycles),.m_flags(flags),.device_online(on),.device_error(errors),.device_drop_count(drops),.device_fifo_level(levels));
    modbus_cfg_bfm cfg(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    rd105_bus_bfm device(.rst_n(rst),.master_txd(tx),.master_de(de),.fault(fault),.slave_txd(rx),.rd_count(requests),.rd_writes(writes),
        .ch1_count(ch1),.ch2_count(ch2),.hmp_count(hmp),.ai8_count(ai8));
    always @(posedge clk)if(rst)begin
        if((dut.bus_grant & (dut.bus_grant-1))!=0 || |(dut.bus_de & ~dut.bus_grant))$fatal(1,"bus collision");
        if((prev_grant & prev_busy & dut.bus_busy)!=0 && dut.bus_grant!=prev_grant)$fatal(1,"ownership lost during timeout/retry");
        prev_grant<=dut.bus_grant;prev_busy<=dut.bus_busy;
        if(stalled && {data[224+:32],keep[28+:4],ms[7],ml[7],sources[112+:16],msg[112+:16],stamps[448+:64],cycles[224+:32],flags[224+:32]}!==held)$fatal(1,"stalled metadata");
        stalled<=mv[7]&&!ready[7];held<={data[224+:32],keep[28+:4],ms[7],ml[7],sources[112+:16],msg[112+:16],stamps[448+:64],cycles[224+:32],flags[224+:32]};
        if(mv[7] && ready[7])begin
            if(sources[112+:16]!='h4a || msg[112+:16]!='h1100 || keep[28+:4]!=15 || cycles[224+:32]!='hffffffff || flags[224+:3]!=5 || stamps[448+:64]==0)$fatal(1,"metadata");
            if(ms[7])position=0;
            packet[position]=data[224+:32];position=position+1;
            if(ml[7])begin
                channel_value=0;duty_value=0;enable_value=2;actual_seen=0;
                if(packet[0][15:0]!=2 || packet[0][31:16]<5 || packet[0][31:16]>6)$fatal(1,"schema2");
                for(tag_index=1;tag_index<position;tag_index=tag_index+2)case(packet[tag_index][15:0])
                    'h14:target_value=packet[tag_index+1];
                    'h15:begin actual_value=packet[tag_index+1];actual_seen=1;end
                    'h480:channel_value=packet[tag_index+1];
                    'h481:duty_value=packet[tag_index+1];
                    'h482:enable_value=packet[tag_index+1];
                endcase
                if(enable_value>1)$fatal(1,"enable");
                if(!actual_seen)begin invalid_samples=invalid_samples+1;if(!flags[228])$fatal(1,"missing invalid sample flag");end
                if(channel_value==1)begin
                    packets1=packets1+1;
                    if(duty_value!==-32'sd40000)$fatal(1,"signed int64 duty");
                end else if(channel_value==2)begin
                    packets2=packets2+1;
                    if(target_value!==expected_ch2_target || (actual_seen && actual_value!==-32'sd10000000) || duty_value!=20000)$fatal(1,"channel2 scaling");
                end else $fatal(1,"channel missing");
            end
        end
    end
    task parameter_command;
        input [31:0] operation,address,quantity,expected;
        begin
            cfg.read32('h6a90,old_count);cfg.write32('h6a84,address);cfg.write32('h6a88,quantity);cfg.write32('h6a80,operation);
            cfg.expect_error(1,'h6a84,address);cfg.expect_error(1,'h6ac0,0);
            begin:await_param
                forever begin cfg.read32('h6a8c,value);if(value[17]&&!value[16])disable await_param;#10000;end
            end
            if(value[3:0]!=expected)$fatal(1,"parameter result %h expected %h stage %d",value,expected,stage);
            cfg.read32('h6a90,value);if(value!=old_count+1)$fatal(1,"completion counter");
            cfg.read32('h6a8c,value);
        end
    endtask
    initial begin
        repeat(6)@(negedge clk);rst=1;
        cfg.read32('h6a00,value);if(value!='h004a0103)$fatal(1,"ID");
        for(i=0;i<19;i=i+1)cfg.read32('h6a00+4*i,value);
        cfg.outside('h6800);cfg.outside('h6900);cfg.outside('h10006a00);
        cfg.read32('h6600,value);if(value!='h00460200)$fatal(1,"AI8 changed");
        cfg.expect_error(1,'h6a04,5);cfg.expect_error(1,'h6a80,1);cfg.expect_error(1,'h6a14,1);cfg.expect_error(1,'h6a10,9600);
        cfg.expect_error(1,'h6a20,25000001);cfg.expect_error(1,'h6a18,1);
        cfg.write32('h6120,3);cfg.write32('h611c,1);cfg.write32('h6104,1);
        cfg.write32('h662c,1);cfg.write32('h6604,1);
        cfg.write32('h6a2c,1);cfg.write32('h6a04,1);
        wait(packets1>=2 && packets2>=2 && hmp>=2 && ai8>=14);stage=1;
        cfg.write32('h6a20,30000000);cfg.write32('h6a04,5);
        cfg.expect_error(1,'h6a04,5);wait(dut.u_7.write_count==1);
        if({device.memory['h1000],device.memory['h1001]}!=3000000)$fatal(1,"target write conversion");
        fault=5;cfg.write32('h6a20,31000000);cfg.write32('h6a04,5);wait(!dut.u_7.pending);if(dut.u_7.write_count!=1)$fatal(1,"ACK accepted as success");fault=0;
        n=packets2;wait(packets2>n);cfg.read32('h6a40,value);if(value!=30000000)$fatal(1,"poll overwrote confirmed target");
        stage=2;cfg.write32('h6ac0,'h0100);parameter_command(2,'h1100,1,0);
        cfg.read32('h6ae0,value);if(value[15:0]!='h0100)$fatal(1,"wire byte packing");
        cfg.write32('h6ac0,'h0a00);fault=5;parameter_command(2,'h110e,1,3);fault=0;
        old_writes=writes;
        fork
            parameter_command(2,'h110e,1,2);
            begin wait(writes>old_writes);fault=3;end
        join
        fault=0;if(writes!=old_writes+1)$fatal(1,"readback failure repeated write");
        parameter_command(1,'h1200,16,0);
        for(i=0;i<8;i=i+1)cfg.write32('h6ac0+4*i,'h32107654+i);
        parameter_command(2,'h1400,16,0);
        for(i=0;i<8;i=i+1)begin cfg.read32('h6ae0+4*i,value);if(value!='h32107654+i)$fatal(1,"32-byte buffer order");end
        cfg.write32('h6a88,1);
        for(i=0;i<=12;i=i+1)if(i<=3 || i==7 || i==8 || i==9 || i==12)begin
            cfg.write32('h6a84,i);cfg.expect_error(1,'h6a80,2);
        end
        cfg.write32('h6a84,0);cfg.expect_error(1,'h6a80,3);
        cfg.write32('h6a84,4);cfg.write32('h6a88,6);cfg.expect_error(1,'h6a80,2);
        cfg.write32('h6a84,65535);cfg.write32('h6a88,2);cfg.expect_error(1,'h6a80,1);
        stage=3;
        for(n=1;n<=4;n=n+1)begin
            fault=n;parameter_command(1,'h1200,2,1);
            if(value[7:4]==0)$fatal(1,"missing transport error");
        end
        fault=3;old_writes=writes;cfg.write32('h6ac0,'h0100);parameter_command(2,'h1107,1,1);
        if(writes!=old_writes+1)$fatal(1,"non-idempotent write retried");
        fault=0;wait(packets1>3 && packets2>3);stage=4;
        device.memory['h1002]='h3b9a;device.memory['h1003]='hc9ff; // invalid sentinel999999999
        wait(invalid_samples>0);device.memory['h1002]='h0026;device.memory['h1003]='h25a0;
        old_count=dut.u_7.timeout_count;fault=3;wait(dut.u_7.timeout_count>=old_count+2);fault=0;
        n=packets2;wait(packets2>n);
        ready[7]=0;wait(drops[224+:32]!=0);ready[7]=1;wait(levels[224+:32]==0);
        cfg.write32('h6a04,0);old_writes=requests;repeat(5000)@(negedge clk);if(requests!=old_writes)$fatal(1,"disabled TX");
        stage=5;cfg.write32('h6a1c,2);cfg.write32('h6a20,-32'sd13000000);cfg.write32('h6a04,1);
        expected_ch2_target=-32'sd13000000;cfg.write32('h6a04,5);wait(dut.u_7.write_count==2);
        cfg.read32('h6a40,value);if(value!==-32'sd13000000)$fatal(1,"channel2 target commit");
        fault=3;cfg.read32('h6a90,old_count);cfg.write32('h6a84,'h1200);cfg.write32('h6a88,2);cfg.write32('h6a80,1);
        wait(dut.u_7.state==12 && dut.u_7.transport.state==7);cfg.write32('h6a04,0);repeat(4)@(negedge clk);
        cfg.read32('h6a8c,value);if(value[17:16]!=2 || value[3:0]!=5)$fatal(1,"cancel result");
        cfg.read32('h6a90,value);if(value!=old_count+1)$fatal(1,"cancel counted twice/missing");fault=0;
        cfg.write32('h6a04,2);cfg.read32('h6a48,value);if(value)$fatal(1,"reset counter");
        $display("TEST_PASS tb_rd105_uart schema2 dual channel, signed units, three client arbitration, write/readback mismatch, CRC/station/exception/timeout, no write retry, FIFO/backpressure/reset");$finish;
    end
    initial begin #200000000;$fatal(1,"timeout stage %d",stage);end
endmodule
