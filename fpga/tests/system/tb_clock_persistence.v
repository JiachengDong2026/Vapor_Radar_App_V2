`timescale 1ns/1ps
module tb_clock_persistence;
    reg ref25=0;always #20 ref25=~ref25;
    reg run_sys=1,simclk=0;always #5 if(run_sys)simclk=~simclk;
    reg por=0,sw=0,pps=0;
    wire sys,gpif,operational,gpif_reset,locked,persistent;
    wire [31:0] total_ref,total_sys,count,errors;
    wire [63:0] ticks;
    wire sync_valid,soft_pulse,clock_request;
    reg cv=0,cw=0;reg [31:0] ca=0,cd=0;
    wire [31:0] sr,tr;wire ready,ce;
    reg [63:0] held;reg [31:0] expected_faults,expected_count;
    clk_rst_mgr #(.SIMULATION(1),.GPIF_CLK_HZ(50000000)) u_clock(
        .ref_clk(simclk),.ext_reset_n(por),.sw_global_reset(sw),
        .sys_clk(sys),.gpif_clk(gpif),.rst_sys_n(operational),.rst_gpif_n(gpif_reset),
        .clocks_locked(locked),.rst_persistent_n(persistent));
    clock_health_monitor u_health(.ref_clk(ref25),.por_n(por),.clock_locked(locked),.fault_total(total_ref));
    counter_cdc u_count(.src_clk(ref25),.src_rst_n(por),.dst_clk(sys),.dst_rst_n(persistent),.src_count(total_ref),.dst_count(total_sys));
    time_sync_core #(.CHECK_CLOCK_VALID(1)) u_time(
        .sys_clk(sys),.rst_sys_n(persistent),.clock_valid(operational),.sync_in_async(pps),
        .gnss_time_tag(64'd0),.gnss_time_tag_valid(1'b0),.timestamp_now(ticks),.sync_valid(sync_valid),.error_status(errors),
        .cfg_valid(cv && ca[15:8]==8'h10),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),.cfg_rdata(tr));
    system_registers #(.USE_EXTERNAL_CLOCK_FAULTS(1),.GPIF_CLK_HZ(50000000)) u_regs(
        .sys_clk(sys),.rst_sys_n(persistent),.timestamp_now(ticks),.clock_locked(operational),.clock_fault_total(total_sys),
        .link_ready(1'b1),.acquisition_running(1'b0),.watchdog_expired(1'b0),
        .module_error_summary(32'd0),.module_irq(32'd0),.protocol_error_count(32'd0),.crc_error_count(32'd0),
        .tx_fifo_level(32'd0),.rx_fifo_level(32'd0),.total_drop_count(32'd0),
        .adc0_fifo_level(32'd0),.adc1_fifo_level(32'd0),.dila0_fifo_level(32'd0),.dila1_fifo_level(32'd0),.sensor_fifo_level(32'd0),
        .msg_pending_mask(32'd0),.bulk_pending_mask(32'd0),.arb_grant_count(64'd0),.tx_word_count(64'd0),.rx_word_count(64'd0),
        .gpif_stall_count(32'd0),.last_sequence_rx(32'd0),.last_sequence_tx(32'd0),
        .cfg_valid(cv && ca[15:8]!=8'h10),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),
        .cfg_ready(ready),.cfg_error(ce),.cfg_rdata(sr),.clock_fault_count(count),.soft_reset_pulse(soft_pulse),.clock_reset_request(clock_request));
    task write_reg;input [31:0] a,d;
        begin @(negedge sys);cv=1;cw=1;ca=a;cd=d;#1;
            if(a[15:8]!=8'h10 && (!ready || ce))$fatal(1,"cfg write failed");
            @(negedge sys);cv=0;cw=0;
        end
    endtask
    task read_expect;input [31:0] a,d;
        begin @(negedge sys);cv=1;cw=0;ca=a;#1;
            if(!ready || ce || sr!==d)$fatal(1,"cfg read %h got %h expected %h",a,sr,d);
            @(negedge sys);cv=0;
        end
    endtask
    task lose_clock;
        begin
            @(negedge sys);force u_clock.clock_locked=0;run_sys=0;#1;
            if(operational || gpif_reset || !persistent)$fatal(1,"reset domain separation");
            held=ticks;#400;
            if(ticks!==held || total_ref!==expected_faults)$fatal(1,"clock absent capture/retention");
            run_sys=1;repeat(8)@(negedge sys);
            if(ticks!==held || sync_valid || !(errors & 32'h20))$fatal(1,"invalid time state");
            release u_clock.clock_locked;
            wait(operational);repeat(12)@(negedge sys);
            if(ticks<=held || count!==expected_count)$fatal(1,"relock time/count %d",count);
        end
    endtask
    initial begin
        #17;por=1;wait(operational && persistent);repeat(12)@(negedge sys);
        if(count!==0 || total_ref!==0)$fatal(1,"startup counted as fault");
        write_reg(32'h0004,1);
        pps=1;repeat(6)@(negedge sys);pps=0;if(!sync_valid)$fatal(1,"PPS missing");
        expected_faults=1;expected_count=1;lose_clock();read_expect(32'h0124,1);
        read_expect(32'h0004,0);read_expect(32'h003c,9);
        write_reg(32'h010c,32'hffffffff);read_expect(32'h010c,0);read_expect(32'h0124,1);
        held=ticks;write_reg(32'h0004,2);sw=1;repeat(3)@(negedge sys);
        if(!persistent || operational || count!==1 || ticks<held)$fatal(1,"software retention");
        sw=0;wait(operational);repeat(8)@(negedge sys);
        write_reg(32'h1004,3);if(ticks<held)$fatal(1,"time module reset rewind");
        write_reg(32'h0104,3);repeat(3)@(negedge sys);read_expect(32'h0124,0);
        if(total_ref!==1)$fatal(1,"clear destroyed lifetime count");
        expected_faults=2;expected_count=1;lose_clock();read_expect(32'h0124,1);
        read_expect(32'h010c,32'h20);
        // A newly synchronized lifetime event wins a simultaneous diagnostic
        // clear: total reaches 3 at a sys edge, clear before the next edge.
        @(negedge sys);force u_clock.clock_locked=0;run_sys=0;#400;
        run_sys=1;wait(total_sys==3);@(negedge sys);
        cv=1;cw=1;ca=32'h0104;cd=3;@(negedge sys);cv=0;cw=0;
        if(count!==1)$fatal(1,"new fault lost during simultaneous clear");
        release u_clock.clock_locked;wait(operational);repeat(10)@(negedge sys);
        read_expect(32'h0124,1);
        por=0;#2;if(persistent || count!==0 || total_ref!==0 || ticks!==0)$fatal(1,"POR did not reset");
        por=1;wait(operational);repeat(12)@(negedge sys);read_expect(32'h0124,0);
        $display("tb_clock_persistence_PASS MMCM_unlock stopped_sysclk relock persistent_time fault_count clear_base software_reset POR");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
