`timescale 1ns/1ps
module tb_ai8_shared_bus;
    reg clk=0,rst=0;always #250 clk=~clk;
    reg [63:0] ticks=0;always @(posedge clk)ticks<=ticks+1;
    wire cv,cw,cr,ce;wire [31:0] ca,cd,rd;wire [3:0] cs;
    wire [1:0] cfgready,cfgerror,request,busy,tx,de,grant,rx;
    wire [31:0] rdh,rda;
    wire physical_tx,physical_de,physical_rx;
    wire ai_valid,ai_sof,ai_last,ai_online,hmp_valid,hmp_online;
    wire [31:0] ai_data,ai_flags,ai_errors,ai_drops,ai_level,hmp_errors;
    wire [3:0] ai_keep,ai_cfgcode,hmp_cfgcode;
    wire [15:0] ai_source,ai_msg;
    wire [63:0] ai_stamp;
    wire [31:0] ai_cycle;
    reg ai_ready=1,hmp_ready=1,live_sync=1,expected_record_sync=0;
    reg [63:0] expected_record_ticks=0;
    integer sync_boundary_checks=0;
    reg [3:0] ai_fault=0,hmp_fault=0;
    wire [31:0] total_requests,ai_writes,verify_count,hmp_requests,hmp_writes,pressure;
    wire [15:0] current_sp;
    reg [31:0] data;
    integer ai_packets=0,hmp_packets=0,index=0,old_packets,old_hmp,old_writes,n,stage=0;
    reg [863:0] packet,last_packet;
    reg [197:0] stalled;
    reg stalled_valid=0;
    reg [1:0] previous_grant=0,previous_busy=0;
    assign cr=|cfgready;assign ce=|(cfgerror & cfgready);
    assign rd=cfgready[1]?rda:cfgready[0]?rdh:0;
    modbus_cfg_bfm cfg(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),
        .cfg_wstrb(cs),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    hmp_modbus_rs485 #(.SYS_CLK_HZ(2000000),.FIFO_DEPTH(64),.SHARED_BUS(1)) hmp(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx[0]),.uart_txd(tx[0]),.rs485_de(de[0]),
        .timestamp_now(ticks),.time_sync_valid(1'b1),.time_sync_seq(32'd0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cfgready[0]),.cfg_rdata(rdh),.cfg_error(cfgerror[0]),.cfg_error_code(hmp_cfgcode),
        .m_valid(hmp_valid),.m_ready(hmp_ready),.m_data(),.m_keep(),.m_sof(),.m_last(),.m_source_id(),.m_msg_id(),
        .m_timestamp(),.m_cycle_id(),.m_flags(),.online(hmp_online),.errors(hmp_errors),.drop_count(),.fifo_level(),
        .bus_request(request[0]),.bus_busy(busy[0]),.bus_grant(grant[0]));
    ai8_modbus_rs485 #(.SYS_CLK_HZ(2000000),.FIFO_DEPTH(64),.SHARED_BUS(1)) ai(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx[1]),.uart_txd(tx[1]),.rs485_de(de[1]),
        .timestamp_now(ticks),.time_sync_valid(live_sync),.time_sync_seq(32'd0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cfgready[1]),.cfg_rdata(rda),.cfg_error(cfgerror[1]),.cfg_error_code(ai_cfgcode),
        .m_valid(ai_valid),.m_ready(ai_ready),.m_data(ai_data),.m_keep(ai_keep),.m_sof(ai_sof),.m_last(ai_last),
        .m_source_id(ai_source),.m_msg_id(ai_msg),.m_timestamp(ai_stamp),.m_cycle_id(ai_cycle),.m_flags(ai_flags),
        .online(ai_online),.errors(ai_errors),.drop_count(ai_drops),.fifo_level(ai_level),
        .bus_request(request[1]),.bus_busy(busy[1]),.bus_grant(grant[1]));
    rs485_transaction_arbiter arb(.clk(clk),.rst_n(rst),.request(request),.busy(busy),.txd(tx),.de(de),
        .uart_rxd(physical_rx),.grant(grant),.rxd(rx),.uart_txd(physical_tx),.rs485_de(physical_de));
    ai8_hmp_bus_bfm devices(.rst_n(rst),.master_txd(physical_tx),.master_de(physical_de),.slave_txd(physical_rx),
        .fault_mode(ai_fault),.hmp_fault(hmp_fault),.request_count(total_requests),.write_count(ai_writes),
        .verify_count(verify_count),.current_sp(current_sp),.hmp_count(hmp_requests),.hmp_write_count(hmp_writes),.pressure_bits(pressure));
    always @(posedge clk)if(rst)begin
        if(ai.core_sample_valid)begin
            expected_record_sync=ai.core_sample_sync;expected_record_ticks=ai.core_ticks;
        end
        if(grant==3 || de==3 || |(de & ~grant))$fatal(1,"shared bus collision/grant");
        if((previous_grant & previous_busy)!=0 && grant!=previous_grant && (busy & previous_grant)!=0)
            $fatal(1,"grant changed during transaction");
        if(!grant[0] && hmp.core.req_ready)$fatal(1,"HMP accepted ungranted request");
        if(!grant[1] && ai.core.req_ready)$fatal(1,"AI8 accepted ungranted request");
        previous_grant<=grant;previous_busy<=busy;
        if(stalled_valid && {ai_data,ai_keep,ai_sof,ai_last,ai_source,ai_msg,ai_stamp,ai_cycle,ai_flags}!==stalled)
            $fatal(1,"stream changed under backpressure");
        stalled_valid<=ai_valid && !ai_ready;
        stalled<={ai_data,ai_keep,ai_sof,ai_last,ai_source,ai_msg,ai_stamp,ai_cycle,ai_flags};
        if(ai_valid && ai_ready)begin
            if(ai_source!==16'h46 || ai_msg!==16'h1100 || ai_keep!==15 || ai_cycle!==32'hffffffff)
                $fatal(1,"AI8 stream metadata");
            if(ai_sof)begin index=0;packet=0;end
            packet[index*32+:32]=ai_data;index=index+1;
            if(ai_last)begin last_packet=packet;ai_packets=ai_packets+1;end
        end
        if(hmp_valid && hmp_ready)hmp_packets=hmp_packets+1;
    end
    // Deliberately change the live sync epoch after core publication, before
    // the wrapper consumes it. Records must keep the core's matching pair.
    always @(negedge clk)if(rst)begin
        if(ai.core_sample_valid)live_sync=~live_sync;
        if(ai.record_valid)begin
            if(ai.record_flags[2]!==expected_record_sync || ai.record_timestamp!==expected_record_ticks)
                $fatal(1,"wrapper timestamp/sync epoch mismatch");
            sync_boundary_checks=sync_boundary_checks+1;
        end
    end
    task await_result;
        input [3:0] expected;
        begin
            begin:poll_result
                forever begin
                    cfg.read32('h6608,data);
                    if(!data[2] && data[9])disable poll_result;
                    #100000;
                end
            end
            cfg.read32('h664c,data);
            if(data[3:0]!==expected || !data[16])$fatal(1,"command result=%h expected=%d",data,expected);
        end
    endtask
    initial begin
        repeat(10)@(negedge clk);rst=1;
        repeat(1000)@(negedge clk);
        if(total_requests || request || physical_de)$fatal(1,"disabled startup traffic");
        cfg.read32('h6600,data);if(data!==32'h00460200)$fatal(1,"AI8 protocol ID");
        cfg.read32('h6118,data);if(data!==0)$fatal(1,"shared HMP format not N1");
        cfg.expect_error(1,'h6610,38400);cfg.expect_error(1,'h6618,1);
        cfg.expect_error(1,'h6110,38400);cfg.expect_error(1,'h6118,1);
        cfg.expect_error(1,'h661c,9);cfg.expect_error(1,'h6650,32001);
        cfg.expect_error(1,'h6620,24400001);cfg.expect_error(1,'h6620,-999100000);
        cfg.write32('h661c,1);cfg.write32('h662c,1);cfg.write32('h6660,20);
        cfg.write32('h611c,1);
        cfg.write32('h6104,1);cfg.write32('h6604,1);
        wait(ai_packets>=1 && hmp_packets>0);
        stage=1;
        if(last_packet[31:0]!==32'h000d0002 || last_packet[63:32]!==32'h04070460 ||
            last_packet[95:64]!==244 || last_packet[159:128]!==500 || last_packet[223:192]!==450)
            $fatal(1,"AI8 v2 raw TLV data");
        if(ai_writes || hmp_writes || !ai_online || !hmp_online)$fatal(1,"startup should only poll");
        cfg.read32('h6624,data);if(data!==24400000)$fatal(1,"PV microdegrees scale");
        cfg.expect_error(1,'h6614,2);
        cfg.write32('h6620,25100000);cfg.write32('h6604,5);
        await_result(0);cfg.read32('h6648,data);if(data!==1 || current_sp!==251)$fatal(1,"confirmed SP write");
        stage=2;
        ai_fault=1;cfg.write32('h6650,333);cfg.write32('h6604,5);await_result(3);
        cfg.read32('h6648,data);if(data!==1)$fatal(1,"locked write falsely acknowledged");
        stage=3;
        ai_fault=5;cfg.write32('h6650,444);cfg.write32('h6604,5);await_result(2);
        cfg.read32('h664c,data);if(data[7:4]!==1)$fatal(1,"verify timeout diagnostic");
        stage=4;
        ai_fault=0;cfg.write32('h6650,32000);cfg.write32('h6604,5);await_result(0);
        old_packets=ai_packets;wait(ai_packets>old_packets);
        cfg.read32('h6608,data);if(data[11])$fatal(1,"overflow SP exposed as valid microdegrees");
        cfg.read32('h6640,data);if(data!==0)$fatal(1,"overflow microdegree read truncated");
        cfg.read32('h6658,data);if(data[31:16]!==32000)$fatal(1,"full-range SP raw lost");
        stage=5;
        // HMP timeout/retries retain ownership, then round-robin lets AI8 progress.
        hmp_fault=1;old_packets=ai_packets;old_hmp=hmp_requests;
        wait(hmp_errors[0]);wait(ai_packets>old_packets);hmp_fault=0;
        if(hmp_requests<old_hmp+2)$fatal(1,"HMP retry not observed");
        wait(hmp_online);
        stage=6;
        ai_ready=0;wait(ai_drops>0);repeat(10)@(negedge clk);
        if(!ai_errors[2])$fatal(1,"FIFO drop not diagnosed");
        ai_ready=1;wait(ai_level==0);
        stage=7;
        // Queue a command while HMP owns a transaction, then disable AI8.
        wait(busy[0]);old_writes=ai_writes;
        cfg.write32('h6650,555);cfg.write32('h6604,5);cfg.write32('h6604,0);
        repeat(50)@(negedge clk);
        cfg.read32('h6608,data);if(data[2] || request[1] || busy[1])$fatal(1,"disable left AI8 pending/owner");
        cfg.read32('h664c,data);if(data[3:0]!==5 || data[7:4]!==6)$fatal(1,"cancel not diagnosed");
        if(ai_writes!=old_writes)$fatal(1,"cancelled command wrote device");
        stage=8;
        // Soft reset while the newly enabled AI8 master owns its initial quiet interval.
        cfg.write32('h6604,1);wait(busy[1] && !de[1]);cfg.write32('h6604,2);
        repeat(50)@(negedge clk);
        if(request[1] || busy[1] || grant[1] || de[1])$fatal(1,"soft reset did not release bus");
        old_hmp=hmp_requests;wait(hmp_requests>old_hmp);
        cfg.read32('h6604,data);if(data!==0)$fatal(1,"soft reset enabled AI8");
        if(sync_boundary_checks<2)$fatal(1,"missing sync-boundary records");
        $display("TEST_PASS tb_ai8_shared_bus atomic arbitration, mixed devices, set/readback errors, cfg, FIFO, timeout, cancellation and sync-epoch flags");
        $finish;
    end
    initial begin repeat(5)#1000000000;$fatal(1,"shared watchdog stage=%d requests=%d ai_packets=%d hmp_packets=%d",stage,total_requests,ai_packets,hmp_packets);end
endmodule
