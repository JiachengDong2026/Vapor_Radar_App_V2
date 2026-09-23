`timescale 1ns/1ps
module tb_system_registers;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,locked=1,wd=0,v=0,w=0;
    reg [31:0] a=0,d=0,es=0,irq=0,drops=17;reg [3:0] strb=15;
    reg [63:0] ts=64'h12345678ffffffff;
    wire r,e,en,reset,kick,mode,fxreset;wire [31:0] rd,wdms,rm,burst,water,fxms,err,irqs,reason,faults;
    wire [63:0] sm,raw;
    system_registers dut(.sys_clk(clk),.rst_sys_n(rst),.timestamp_now(ts),.clock_locked(locked),.link_ready(1'b1),
      .acquisition_running(1'b0),.watchdog_expired(wd),.module_error_summary(es),.module_irq(irq),
      .protocol_error_count(32'd5),.crc_error_count(32'd2),.tx_fifo_level(32'd20),.rx_fifo_level(32'd10),.total_drop_count(drops),
      .adc0_fifo_level(32'd100),.adc1_fifo_level(32'd200),.dila0_fifo_level(32'd300),.dila1_fifo_level(32'd400),.sensor_fifo_level(32'd500),
      .msg_pending_mask(32'h45),.bulk_pending_mask(32'h6),.arb_grant_count(64'habcdef0112345678),
      .tx_word_count(64'h0123456789abcdef),.rx_word_count(64'hfedcba9876543210),.gpif_stall_count(32'd13),
      .last_sequence_rx(32'd23),.last_sequence_tx(32'd24),.cfg_valid(v),.cfg_write(w),.cfg_addr(a),.cfg_wdata(d),.cfg_wstrb(strb),
      .cfg_ready(r),.cfg_error(e),.cfg_rdata(rd),.global_enable(en),.soft_reset_pulse(reset),.watchdog_kick(kick),
      .watchdog_timeout_ms(wdms),.reset_mask(rm),.stream_mask(sm),.raw_stream_mask(raw),.arb_mode(mode),.max_high_burst(burst),
      .tx_high_water(water),.fx3_reset_ms(fxms),.fx3_reset_request(fxreset),.error_summary(err),.irq_summary(irqs),
      .reset_reason(reason),.clock_fault_count(faults));
    task wr;input [31:0] addr,data;input bad;begin
      @(negedge clk);v=1;w=1;a=addr;d=data;@(posedge clk);if(!r || e!==bad)$fatal(1,"write %h",addr);
      @(negedge clk);v=0;w=0;
    end endtask
    task rr;input [31:0] addr,value;begin
      @(negedge clk);v=1;w=0;a=addr;@(posedge clk);if(!r || e || rd!==value)$fatal(1,"read %h got %h expected %h",addr,rd,value);
      @(negedge clk);v=0;
    end endtask
    initial begin
      repeat(4)@(negedge clk);rst=1;
      rr('h0000,'h00010101);rr('h0110,100000000);rr('h7010,1);rr('h7034,4);rr('h8030,10);
      wr('h0000,1,1);wr('h0004,4,1);wr('h7034,0,1);wr('h0120,'h80000000,1);
      rr('h0024,'hffffffff);ts=64'h1234567900000000;rr('h0028,'h12345678);
      rr('h7040,'h12345678);rr('h7044,'habcdef01);rr('h8018,'h89abcdef);rr('h801c,'h01234567);
      wr('h002c,'h12345678,0);strb=2;wr('h002c,'hffffabff,0);strb=15;rr('h002c,'h1234ab78);
      wr('h0034,'h76543210,0);wr('h0050,'hf0e0d0c0,0);if(raw!==64'hf0e0d0c076543210)$fatal(1,"RAW mask64");
      wr('h700c,'hffffffff,0);wr('h800c,'hffffffff,0);wr('h000c,'hffffffff,0);
      es=6;irq=9;repeat(2)@(negedge clk);wr('h000c,'hffffffff,0);if(err!=6)$fatal(1,"active fault priority");
      es=0;irq=0;wr('h000c,2,0);if(err!=4)$fatal(1,"W1C partial");wr('h0038,1,0);if(irqs!=8)$fatal(1,"IRQ W1C");
      rr('h701c,17);wr('h701c,'hffffffff,0);rr('h701c,0);drops=20;rr('h701c,3);
      wr('h0004,3,0);if(!en || !reset || reason!=5)$fatal(1,"soft reset");@(negedge clk);if(reset)$fatal(1,"W1P repeat");
      wr('h0044,0,0);if(!kick)$fatal(1,"kick");wr('h8004,3,0);if(!fxreset)$fatal(1,"FX reset");
      locked=0;repeat(2)@(negedge clk);locked=1;repeat(2)@(negedge clk);if(faults!=1)$fatal(1,"clock fault");
      wd=1;@(negedge clk);wd=0;if(en || !reset || reason!=15 || !err[0])$fatal(1,"watchdog");
      @(negedge clk);v=1;a='h0200;#1;if(r || e)$fatal(1,"foreign page");v=0;
      $display("tb_system_registers_PASS");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
