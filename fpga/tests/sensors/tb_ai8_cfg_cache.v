`timescale 1ns/1ps
module tb_ai8_cfg_cache;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg cv=0,cw=0;reg [31:0] ca=0,cd=0;reg [3:0] cs=0;
    wire cr,ce;wire [31:0] rd;wire [3:0] ec;
    reg [31:0] reference_raw=250,reference_uc=25000000;
    reg [31:0] mask,merged,expected_uc;
    reg expected_error;
    integer i,j,checks=0;
    ai8_modbus_rs485 #(.SYS_CLK_HZ(100000000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(1'b1),.uart_txd(),.rs485_de(),
        .timestamp_now(64'd0),.time_sync_valid(1'b0),.time_sync_seq(32'd0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.cfg_error_code(ec),
        .m_valid(),.m_ready(1'b1),.m_data(),.m_keep(),.m_sof(),.m_last(),.m_source_id(),.m_msg_id(),
        .m_timestamp(),.m_cycle_id(),.m_flags(),.online(),.errors(),.drop_count(),.fifo_level(),
        .bus_request(),.bus_busy(),.bus_grant(1'b1));
    always @(posedge clk)if(rst && cv && ca==32'h6604 && cw)begin
        if(dut.ctrl_write_fire !== (cr && !ce))$fatal(1,"local CONTROL acceptance differs from cfg handshake");
        if(dut.soft_reset !== (cr && !ce && cs[0] && cd[1]))$fatal(1,"soft reset acceptance differs");
        if(dut.commit !== (cr && !ce && cs[0] && cd[2]))$fatal(1,"commit acceptance differs");
        if(dut.clear_fifo !== (cr && !ce && cs[0] && cd[3]))$fatal(1,"clear acceptance differs");
    end
    task shadow_write;
        input raw_mode;input [31:0] data;input [3:0] strb;
        begin
            mask={{8{strb[3]}},{8{strb[2]}},{8{strb[1]}},{8{strb[0]}}};
            merged=((raw_mode?reference_raw:reference_uc)&~mask)|(data&mask);
            expected_error=raw_mode ? ($signed(merged)<-9990 || $signed(merged)>32000):
                ($signed(merged)<-999000000 || $signed(merged)%100000!=0);
            @(negedge clk);cv=1;cw=1;ca=raw_mode?'h6650:'h6620;cd=data;cs=strb;
            @(posedge clk);
            if(!cr || ce!==expected_error || (ce && ec!==7))$fatal(1,"shadow validation raw=%d data=%h mask=%h",raw_mode,data,strb);
            if(!expected_error)begin
                if(raw_mode)begin reference_raw=merged;reference_uc=$signed(merged)>21474 ? 0:$signed(merged)*100000;end
                else begin reference_uc=merged;reference_raw=$signed(merged)/100000;end
            end
            // Read on the very next accepted cfg cycle: no pipeline settling gap.
            @(negedge clk);cw=0;cs=0;ca='h6620;
            @(posedge clk);if(!cr || ce || rd!==reference_uc)$fatal(1,"next-cycle UC cache mismatch got=%h exp=%h",rd,reference_uc);
            @(negedge clk);ca='h6650;
            @(posedge clk);if(!cr || ce || rd!==reference_raw)$fatal(1,"raw/cache coherence mismatch got=%h exp=%h",rd,reference_raw);
            @(negedge clk);cv=0;checks=checks+1;
        end
    endtask
    task control_write;
        input [31:0] data;input [3:0] strb;input [3:0] expected_code;
        begin
            @(negedge clk);cv=1;cw=1;ca='h6604;cd=data;cs=strb;
            @(posedge clk);
            if(!cr || ce!==(expected_code!=0) || ec!==expected_code)$fatal(1,"CONTROL priority data=%h strb=%h code=%h",data,strb,ec);
            @(negedge clk);cv=0;checks=checks+1;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;
        shadow_write(0,40000000,15);shadow_write(1,400,1);
        shadow_write(1,-123,15);shadow_write(0,-12300000,15);
        shadow_write(1,-9990,15);shadow_write(1,32000,15);
        shadow_write(1,32'hffff8000,3); // invalid partial negative/sign extension
        shadow_write(0,0,0); // visible UC zero becomes raw zero, as before
        shadow_write(1,32000,15);shadow_write(1,0,0); // raw no-op retains 32000
        shadow_write(0,40000000,15);shadow_write(0,40000001,1); // invalid nonmultiple
        shadow_write(0,0,1);shadow_write(0,32'h7fffffff,15);shadow_write(0,-999100000,15);
        shadow_write(1,32001,15);shadow_write(1,32'hffffd8f9,15);
        for(i=0;i<16;i=i+1)begin
            shadow_write(0,40000000,i[3:0]);
            shadow_write(1,-123,i[3:0]);
        end
        control_write(4,1,7); // disabled commit rejected
        control_write(32'hffffffff,0,0); // masked reserved/commit/reset bits inert
        control_write(32'h100,2,7);control_write(32'h100,1,0);
        if(dut.enabled)$fatal(1,"masked control unexpectedly enabled");
        shadow_write(0,40000000,15);
        control_write(5,1,0); // enable+commit captures the immediately updated raw
        if(!dut.pending || dut.pending_raw!==400)$fatal(1,"commit did not capture coherent new shadow");
        control_write(5,1,8);control_write(21,1,7);control_write(4,1,7);
        control_write(32'h500,2,7);control_write(5,0,0);
        if(!dut.pending)$fatal(1,"rejected/masked CONTROL lost pending command");
        control_write(2,1,0); // local reset accepted independently of shadow arithmetic
        if(dut.enabled || dut.pending || dut.shadow_raw!==250 || dut.shadow_uc_cached!==25000000)
            $fatal(1,"soft reset cache/default mismatch");
        $display("TEST_PASS tb_ai8_cfg_cache masked raw/UC writes, next-cycle cache coherence, full range, zero-strobe, CONTROL priority and commit checks=%0d",checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"cfg cache watchdog");end
endmodule
