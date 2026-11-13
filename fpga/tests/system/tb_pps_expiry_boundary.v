`timescale 1ns/1ps
module tb_pps_expiry_boundary;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,pin=0,tagv=0,cv=0,cw=0;
    reg [31:0] ca=0,cd=0;
    wire cr,ce;wire [31:0] rd,seq;
    wire [63:0] tick,pps_tick;
    // Keep multiple cycles per ms: SYS=1000 collapses the expiry/recovery
    // window to one cycle and cannot expose this maintenance-tick boundary.
    time_sync_core #(.SYS_CLK_HZ(100000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.clock_valid(1'b1),.sync_in_async(pin),
        .gnss_time_tag(64'd1700000000123456),.gnss_time_tag_valid(tagv),
        .timestamp_now(tick),.sync_seq(seq),.sync_event_tick(pps_tick),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),
        .cfg_wstrb(4'hf),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    task wr;input [31:0] address,data;begin
        @(negedge clk);cv=1;cw=1;ca=address;cd=data;#1;
        if(!cr || ce)$fatal(1,"anchor setup rejected");
        @(negedge clk);cv=0;cw=0;
    end endtask
    task pps;input fresh_tag;begin
        if(seq!=0)wait(tick>=pps_tick+99998);
        @(negedge clk);pin=1;tagv=fresh_tag;
        repeat(5)@(negedge clk);pin=0;tagv=0;
        repeat(2)@(negedge clk);
    end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        pps(1);pps(1);pps(1);pps(1);
        wr('h1070,1700000000);wr('h1074,seq);wr('h1078,1);
        if(!dut.utc_anchored)$fatal(1,"anchor not established");
        pps(0);
        // UART expires while the PPS stream remains fresh and qualified.
        wait(dut.tag_age_ms==2000);
        @(negedge clk);cv=1;cw=0;ca='h1044;#1;
        if(rd[1])$fatal(1,"UTC valid at expired UART age");
        tagv=1;
        @(negedge clk);tagv=0;#1;
        if(rd[1])$fatal(1,"immediate UART recovery revived expired UTC anchor");
        if(!rd[0] || !rd[2] || !rd[3])$fatal(1,"boundary coverage missing PPS/tag freshness");
        cv=0;
        wr('h1074,seq);wr('h1078,1);
        if(!dut.utc_anchored)$fatal(1,"explicit recovery anchor failed");
        // A host commit on the exact PPS timeout tick must lose to expiry.
        // Keep UART valid to isolate PPS expiry from the tag-age condition.
        tagv=1;
        wait(dut.elapsed_ms==1999 && dut.sub_ms==99);
        @(negedge clk);cv=1;cw=1;ca='h1078;cd=1;#1;
        if(!cr || !ce)$fatal(1,"PPS timeout-tick anchor commit must be rejected");
        @(negedge clk);cv=1;cw=0;ca='h1044;#1;
        if(rd[2:0]!=0 || dut.utc_anchored)$fatal(1,"PPS timeout lost to anchor commit");
        $display("tb_pps_expiry_boundary_PASS exact_expiry immediate_UART_recovery_no_auto_anchor");$finish;
    end
    initial begin #10000000;$fatal(1,"expiry boundary timeout");end
endmodule
