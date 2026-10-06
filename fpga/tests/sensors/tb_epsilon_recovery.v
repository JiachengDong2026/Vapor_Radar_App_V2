`timescale 1ns/1ps
module tb_epsilon_recovery;
    reg clk=0; always #20 clk=~clk;
    reg rst=0,rx=1,cv=0,cw=0;
    reg [31:0] ca=0,cd=0;
    wire cr,ce,tx,online,mv,ml;
    wire [31:0] rd,rx_count,good_count,crc_count,errors;
    wire [3:0] state;
    wire [15:0] attempts;
    reg [63:0] now=0; always @(posedge clk) now<=now+1'b1;
    epsilon_rs232 #(.SYS_CLK_HZ(25000000),.PASSIVE_MS(4),.RESPONSE_MS(2),
        .QUIET_MS(1),.ONLINE_MS(6)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx),.uart_txd(tx),
        .timestamp_now(now),.time_sync_valid(1'b0),.time_sync_seq(32'd0),
        .sync_event_pulse(1'b0),.gnss_time_tag(),.gnss_time_tag_valid(),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),
        .cfg_ready(cr),.cfg_error(ce),.cfg_rdata(rd),
        .m_valid(mv),.m_ready(1'b1),.m_data(),.m_keep(),.m_sof(),.m_last(ml),
        .m_source_id(),.m_msg_id(),.m_timestamp(),.m_cycle_id(),.m_flags(),
        .online(online),.errors(errors),.drop_count(),.fifo_level(),
        .debug_rx_bytes(rx_count),.debug_good_frames(good_count),
        .debug_crc_errors(crc_count),.debug_probe_state(state),.debug_attempts(attempts));

    real bit_ns=1085.069;
    reg [7:0] tx_bytes[0:1023];
    reg [7:0] sampled;
    integer tx_count=0,tx_edges=0,packets=0,j,base,old_edges,tests=0,k;
    real last_rx_end,query_wait_at,exit_wait_at;
    reg [3:0] old_state=0;
    always @(posedge clk) begin
        old_state<=state;
        if(state==5 && old_state!=5) query_wait_at=$realtime;
        if(state==7 && old_state!=7) exit_wait_at=$realtime;
        if(mv && ml) packets=packets+1;
    end
    // Independent wire decoder, including complete stop-bit observation. It is
    // never reset along with the DUT, so truncated reset/disable TX is visible.
    initial forever begin
        @(negedge tx); tx_edges=tx_edges+1;
        #(bit_ns*1.5);
        for(j=0;j<8;j=j+1) begin sampled[j]=tx; #(bit_ns); end
        if(tx!==1'b1) $fatal(1,"TX stop bit truncated, byte=%0d state=%0d",tx_count,state);
        tx_bytes[tx_count]=sampled; tx_count=tx_count+1;
        #(bit_ns*0.40);
        if(tx!==1'b1) $fatal(1,"TX full stop interval cut short");
    end
    function [7:0] c8;
        input [7:0] a,b; integer n; reg [7:0] v;
        begin v=a^b; for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^8'h8c:v>>1; c8=v; end
    endfunction
    function [15:0] c16;
        input [15:0] a; input [7:0] b; integer n; reg [15:0] v;
        begin v=a^{b,8'd0};for(n=0;n<8;n=n+1)v=v[15]?(v<<1)^16'h1021:v<<1;c16=v;end
    endfunction
    task serial;
        input [7:0] value; integer n;
        begin
            rx=0; #(bit_ns);
            for(n=0;n<8;n=n+1)begin rx=value[n]; #(bit_ns); end
            rx=1; #(bit_ns); last_rx_end=$realtime;
        end
    endtask
    task frame;
        input [7:0] id; input integer bad;
        reg [7:0] h; reg [15:0] c;
        begin
            h=c8(c8(c8(c8(0,8'hfc),id),8'd1),8'h19); c=c16(0,8'h55);
            serial(8'hfc);serial(id);serial(1);serial(8'h19);
            serial(h^(bad==1?8'h01:8'h00)); serial(c[15:8]);
            serial(c[7:0]^(bad==2?8'h01:8'h00));serial(8'h55);
            serial(bad==3?8'h00:8'hfd);
            repeat(20) @(negedge clk);
        end
    endtask
    task ack;
        begin serial("*");serial("#");serial("O");serial("K");serial(13);serial(10); end
    endtask
    task wr;
        input [31:0] address,value; input bad;
        begin
            @(negedge clk); cv=1;cw=1;ca=address;cd=value;#1;
            if(cr!==1 || ce!==bad)$fatal(1,"cfg access %h error=%b expected=%b",address,ce,bad);
            @(negedge clk);cv=0;cw=0;
        end
    endtask
    task fresh;
        begin
            if(dut.recovery_busy)$fatal(1,"test tried to discard ongoing cleanup");
            @(negedge clk);rst=0;rx=1;cv=0;cw=0;
            repeat(20)@(negedge clk);rst=1;
            repeat(20)@(negedge clk);bit_ns=1085.069;
            base=tx_count;old_edges=tx_edges;
        end
    endtask
    task check_line;
        input integer start,kind;
        reg [95:0] expected; integer n,len;
        begin
            if(kind==0)begin expected={"#fconfig",8'h0d,8'h0a};len=10;end
            else if(kind==1)begin expected={"#fmsg",8'h0d,8'h0a};len=7;end
            else begin expected={"#fdeconfig",8'h0d,8'h0a};len=12;end
            for(n=0;n<len;n=n+1)
                if(tx_bytes[start+n]!==((expected>>((len-1-n)*8))&8'hff))
                    $fatal(1,"command byte mismatch at=%0d kind=%0d got=%h",start+n,kind,tx_bytes[start+n]);
        end
    endtask
    task finish_three;
        begin
            wait(tx_count>=base+29);repeat(40)@(negedge clk);
            check_line(base,0);check_line(base+10,1);check_line(base+17,2);
            if(tx_count!=base+29)$fatal(1,"unexpected extra command bytes");
        end
    endtask
    task finish_cleanup;
        input integer with_query;
        begin
            wait(tx_count>=base+(with_query?29:22));
            wait(state==0);repeat(40)@(negedge clk);
            check_line(base,0);
            if(with_query)begin check_line(base+10,1);check_line(base+17,2);end
            else check_line(base+10,2);
            if(tx_count!=base+(with_query?29:22) || tx!==1)$fatal(1,"cleanup count/idle");
        end
    endtask

    initial begin
        // Valid frames outside both ID range and configured filter suppress TX.
        fresh;wr('h6214,0,0);wr('h6218,0,0);wr('h6204,1,0);
        frame(8'ha5,0);wait(state==9);
        if(good_count!=1 || !online || attempts!=0)$fatal(1,"filtered valid health");
        #7000000;
        if(online || tx_edges!=old_edges || attempts!=0 || state!=9 || packets!=0)
            $fatal(1,"passive healthy/late loss must never send recovery");
        tests=tests+1;

        // No stream: exact three CRLF lines, acknowledged config and multiline query.
        fresh;wr('h6204,1,0);wait(state==3);check_line(base,0);ack;
        wait(state==5);check_line(base+10,1);
        serial("I");serial("D");serial("5");serial("0");serial(13);serial(10);
        #400000;serial("1");serial("H");serial("z");serial(13);serial(10);
        wait(state==6);
        if($realtime-last_rx_end<990000)$fatal(1,"query did not wait bounded quiet gap");
        finish_three;ack;frame(8'h40,0);wait(state==9);
        if(attempts!=1 || good_count!=1 || !online || rx_count<20)$fatal(1,"recovered diagnostics");
        #8000000;if(tx_count!=base+29)$fatal(1,"recovered later loss retried");
        tests=tests+1;

        // Header CRC, payload CRC and trailer corruption do not count as health.
        fresh;wr('h6204,1,0);frame(8'h50,1);frame(8'h50,2);frame(8'h50,3);
        serial("*");serial("#");serial("O");serial("K");serial(13);serial(10);
        if(good_count!=0 || online || crc_count!=3)$fatal(1,"bad frame or ASCII marked online");
        // Missing ACK and missing query response still execute all three commands.
        finish_three;wait(state==10);
        if(attempts!=1 || good_count!=0)$fatal(1,"timeout outcome");
        if($realtime-exit_wait_at<3990000 || $realtime-exit_wait_at>4020000)
            $fatal(1,"post-exit passive interval must start at final UART completion");
        #12000000;if(tx_count!=base+29)$fatal(1,"unbounded retry");
        frame(8'ha5,0);wait(state==9);
        if(!online || attempts!=1 || tx_count!=base+29)$fatal(1,"late valid stream not recovered");
        tests=tests+1;

        // Endless multiline response cannot hold the device in config indefinitely.
        fresh;wr('h6204,1,0);wait(state==3);ack;wait(state==5);
        fork
            begin for(k=0;k<40;k=k+1)begin serial("x");#100000;end end
            begin
                wait(state==6);
                if($realtime-query_wait_at>2020000)$fatal(1,"query hard deadline exceeded");
            end
        join
        finish_three;wait(state==10);tests=tests+1;

        // Disable while fconfig is physically in flight: finish whole line, then exit.
        fresh;wr('h6204,1,0);wait(tx_count>=base+2);#2500;
        wr('h6204,0,0);wr('h6210,500000,1);
        finish_cleanup(0);#6000000;
        if(tx_count!=base+22 || attempts!=1)$fatal(1,"disabled cleanup retried");
        // Re-enable creates a new epoch and can attempt once again.
        base=tx_count;wr('h6204,1,0);finish_three;wait(state==10);
        if(attempts!=2)$fatal(1,"disable/enable did not rearm once");tests=tests+1;

        // A pulse of software reset during query preserves the complete in-flight line.
        fresh;wr('h6204,1,0);wait(state==3);ack;wait(tx_count>=base+12);#2500;
        wr('h6204,2,0);finish_cleanup(1);
        if(attempts!=0 || good_count!=0 || online)$fatal(1,"soft-reset deferred cleanup");tests=tests+1;

        // Sustained external reset during exit must not truncate any UART bit.
        fresh;wr('h6204,1,0);wait(state==3);ack;wait(state==5);
        serial("q");wait(tx_count>=base+19);#2500;
        @(negedge clk);rst=0;#500000;
        finish_cleanup(1);
        if(attempts!=0)$fatal(1,"hard reset did not clear after cleanup");
        rst=1;repeat(20)@(negedge clk);tests=tests+1;

        // A valid (filtered) frame during configuration skips query but always exits.
        fresh;wr('h6214,0,0);wr('h6218,0,0);wr('h6204,1,0);
        wait(state==3);frame(8'ha5,0);wait(tx_count>=base+22);wait(state==9);
        check_line(base,0);check_line(base+10,2);
        if(!online || attempts!=1 || tx_count!=base+22)$fatal(1,"config health cleanup");tests=tests+1;

        // Response time starts at final LF stop completion, even at slow 9600 baud.
        fresh;bit_ns=104166.667;wr('h6210,9600,0);wr('h6204,1,0);
        wait(tx_count>=base+10);wait(state==3);#1500000;
        if(state!=3)$fatal(1,"config timeout started before physical command completion");
        #600000;
        if(state!=4)$fatal(1,"missing ACK must progress to read-only query");
        // Short global reset changes core baud to default; cleanup must retain 9600.
        wait(tx_count>=base+12);#200000;
        @(negedge clk);rst=0;repeat(5)@(negedge clk);rst=1;
        finish_cleanup(1);
        if(attempts!=0)$fatal(1,"slow reset cleanup diagnostics");tests=tests+1;

        // Disable/re-enable while cleanup is pending must not cut or restart a line.
        fresh;wr('h6204,1,0);wait(tx_count>=base+2);wr('h6204,0,0);wr('h6204,1,0);
        wait(tx_count>=base+22);wait(state==1);
        check_line(base,0);check_line(base+10,2);
        #1000000;if(tx_count!=base+22)$fatal(1,"cleanup/re-enable bypassed passive interval");
        wr('h6204,0,0);wait(state==0);tests=tests+1;

        $display("EPSILON_RECOVERY_REGRESSION_PASS cases=%0d physical_uart_commands CRC_filter_health bounded_timeouts disable_soft_hard_reset",tests);
        $finish;
    end
    initial begin #300000000;$fatal(1,"recovery watchdog state=%0d bytes=%0d cases=%0d",state,tx_count,tests);end
endmodule
