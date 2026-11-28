`timescale 1ns/1ps
module tb_ai8_scan;
    reg clk=0,rst=0,valid=0,write=0;
    always #5 clk=~clk;
    reg [31:0] addr=0,data=0;
    wire [31:0] rd;
    wire err;
    reg [63:0] tick=64'h1234567800000000, first_tick;
    always @(posedge clk) tick<=tick+1'b1;
    reg done=0;
    reg [3:0] transport=0;
    reg [255:0] response=0;
    integer ch,item,round,k;
    reg found;
    reg [15:0] expected,value;
    ai8_modbus_rs485 #(.SYS_CLK_HZ(2000000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(1'b1),.uart_txd(),.rs485_de(),
        .timestamp_now(tick),.time_sync_valid(1'b1),.time_sync_seq(32'd0),
        .cfg_valid(valid),.cfg_write(write),.cfg_addr(addr),.cfg_wdata(data),.cfg_wstrb(4'hf),
        .cfg_ready(),.cfg_rdata(rd),.cfg_error(err),.cfg_error_code(),
        .m_valid(),.m_ready(1'b1),.m_data(),.m_keep(),.m_sof(),.m_last(),.m_source_id(),.m_msg_id(),
        .m_timestamp(),.m_cycle_id(),.m_flags(),.online(),.errors(),.drop_count(),.fifo_level(),
        .bus_request(),.bus_busy(),.bus_grant(1'b1));
    task wr;
        input [31:0] a,d;
        begin @(negedge clk);valid=1;write=1;addr=a;data=d;
            #1;if(err)$fatal(1,"write rejected %h",a);@(negedge clk);valid=0;write=0;
        end
    endtask
    task check_read;
        input [31:0] a,d;
        begin
            @(negedge clk);valid=1;write=0;addr=a;
            #1;if(err || rd!==d)$fatal(1,"read %h expected %h got %h",a,d,rd);
            @(negedge clk);valid=0;
        end
    endtask
    initial begin
        force dut.core.req_ready=1'b1;
        force dut.core.done=done;
        force dut.core.master_error=transport;
        force dut.core.master_exception=8'd0;
        force dut.core.read_data=response;
        repeat(4)@(negedge clk);rst=1;
        check_read('h6668,1);check_read('h6604,0);check_read('h66fc,15);
        wr('h662c,1);wr('h6604,1);
        for(round=0;round<2;round=round+1)begin
            for(ch=1;ch<=8;ch=ch+1)begin
                for(item=0;item<7;item=item+1)begin
                    wait(dut.core.state==2);@(negedge clk);
                    case(item)
                        0:expected=ch-1;1:expected='h600+ch-1;2:expected='h480+ch-1;
                        3:expected='h360+ch-1;4:expected='h680+(ch-1)/2;
                        5:expected='h6c0+(ch-1)/2;6:expected='h851;
                    endcase
                    if(dut.core.address!==expected)$fatal(1,"wrong CH%0d item%0d address",ch,item);
                    value=item==4 ? (ch%2 ? (ch<=2 ? 'h0008 : 'h0108) : (ch<=2 ? 'h0800 : 'h0801)) : item==6 ? 'h0200 : ch*100+item;
                    response={240'd0,value[7:0],value[15:8]};
                    transport=(round==1 && ch==4)?1:0;done=1;
                    @(negedge clk);done=0;
                    if(transport!=0)item=7;
                end
                wait(dut.record_valid);@(negedge clk);
                if(dut.record_data[15:0]!=3 || dut.core_channel!=ch)$fatal(1,"schema/channel mismatch");
                if(ch==1 && round==0)first_tick=dut.record_timestamp;
                if(ch==1 && round==1 && (dut.record_timestamp-first_tick<2000 || dut.record_timestamp-first_tick>2010))
                    $fatal(1,"round period %d clocks",dut.record_timestamp-first_tick);
                wr('h6698,ch);
                // Compare the selected host window against this record's TLV values.
                check_read('h66a0,{18'd0,dut.record_data[72*8+1 +: 12],1'b1,dut.record_data[72*8]});
                check_read('h66a4,{dut.record_data[16*8 +: 16],dut.record_data[8*8 +: 16]});
                check_read('h66a8,{dut.record_data[24*8 +: 16],dut.record_data[32*8 +: 16]});
                check_read('h66ac,{dut.record_data[56*8 +: 16],dut.record_data[48*8 +: 8],dut.record_data[40*8 +: 8]});
                check_read('h66b0,dut.record_timestamp[31:0]);check_read('h66b4,dut.record_timestamp[63:32]);
                found=0;
                for(k=4;k<dut.record_length;k=k+8)begin
                    if(dut.record_data[k*8+:16]==16'h0468)begin
                        found=1;if(dut.record_data[(k+4)*8+:32]!=ch)$fatal(1,"channel TLV wrong");
                    end
                end
                if(!found)$fatal(1,"missing channel TLV");
                if(dut.cache_good[ch-1]!=(round==1 && ch==4?1:round+1))$fatal(1,"independent success count");
                if(round==1 && ch==4)begin
                    if(dut.cache_bad[3]!=1 || dut.cache_pvsp[3]!=0 || dut.cache_quality[3][0])$fatal(1,"failed channel contains stale data");
                end else begin
                    if(dut.cache_pvsp[ch-1][15:0]!=ch*100+1)$fatal(1,"channel data copied");
                    if(dut.cache_status[ch-1][7:0]!=(ch<=2?0:1))$fatal(1,"local alarm contaminated by global alarm");
                    if(dut.cache_status[ch-1][31:16]!='h0200)$fatal(1,"global alarm lost");
                end
            end
        end
        // Commit during a poll: the queued target must survive until write and verify.
        wr('h666c,7);wr('h6650,321);wr('h6604,5);
        // Finish the current poll if the command has not reached a gap yet.
        while(dut.core.state!=5)begin
            @(negedge clk);
            done=(dut.core.state==2);response=0;transport=0;
        end
        done=0;
        if(dut.core.selected_sp_address!=6)$fatal(1,"set target follows scan cursor");
        wait(dut.core.state==6);@(negedge clk);done=1;
        @(negedge clk);done=0;wait(dut.core.state==8);
        if(dut.core.selected_sp_address!=6)$fatal(1,"verify target changed");
        @(negedge clk);response={240'd0,8'h41,8'h01};done=1;
        @(negedge clk);done=0;repeat(3)@(negedge clk);
        if(dut.confirmed_count!=1 || dut.last_readback!=321)$fatal(1,"set confirmation missing");
        wait(dut.core.state==2);
        if(dut.core.address!=0)$fatal(1,"command in CH8 gap lost round boundary");
        wr('h6604,0);wr('h6668,0);wr('h661c,8);wr('h6604,1);
        wait(dut.core.state==2);
        if(dut.core.address!=7)$fatal(1,"single-channel selection lost");
        wr('h6604,2);check_read('h6604,0);check_read('h6668,1);
        wr('h6668,1);check_read('h6668,1);
        $display("TEST_PASS tb_ai8_scan eight real address sequences, isolated values/alarms/counts, failure progression, single-channel selection");$finish;
    end
    initial begin #10000000;$fatal(1,"watchdog");end
endmodule
