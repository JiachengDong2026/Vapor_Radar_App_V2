`timescale 1ns/1ps
module tb_system_registers_semantics;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,locked=1,link=1,wd=0,v=0,w=0;
    reg [31:0] protocol_errors=0,crc_errors=0;
    wire stream_en,usb_en,clock_reset,stream_reset,stream_clear,usb_clear;
    reg [31:0] a=0,d=0,es=0,irq=0,drops=17;reg [3:0] strb=15;
    reg [63:0] ts=64'h12345678ffffffff;
    wire r,e,en,reset,kick,mode,fxreset;wire [31:0] rd,wdms,rm,burst,water,fxms,err,irqs,reason,faults;
    wire [63:0] sm,raw;
    system_registers #(.CAPABILITIES0(32'h5a5a)) dut(.sys_clk(clk),.rst_sys_n(rst),.timestamp_now(ts),.clock_locked(locked),.link_ready(link),
      .acquisition_running(1'b0),.watchdog_expired(wd),.module_error_summary(es),.module_irq(irq),
      .protocol_error_count(protocol_errors),.crc_error_count(crc_errors),.tx_fifo_level(32'd20),.rx_fifo_level(32'd10),.total_drop_count(drops),
      .adc0_fifo_level(32'd100),.adc1_fifo_level(32'd200),.dila0_fifo_level(32'd300),.dila1_fifo_level(32'd400),.sensor_fifo_level(32'd500),
      .msg_pending_mask(32'h45),.bulk_pending_mask(32'h6),.arb_grant_count(64'habcdef0112345678),
      .tx_word_count(64'h0123456789abcdef),.rx_word_count(64'hfedcba9876543210),.gpif_stall_count(32'd13),
      .last_sequence_rx(32'd23),.last_sequence_tx(32'd24),.cfg_valid(v),.cfg_write(w),.cfg_addr(a),.cfg_wdata(d),.cfg_wstrb(strb),
      .cfg_ready(r),.cfg_error(e),.cfg_rdata(rd),.global_enable(en),.soft_reset_pulse(reset),.watchdog_kick(kick),
      .watchdog_timeout_ms(wdms),.reset_mask(rm),.stream_mask(sm),.raw_stream_mask(raw),.arb_mode(mode),.max_high_burst(burst),
      .tx_high_water(water),.fx3_reset_ms(fxms),.fx3_reset_request(fxreset),.error_summary(err),.irq_summary(irqs),
      .reset_reason(reason),.clock_fault_count(faults),.stream_enable(stream_en),.usb_enable(usb_en),
      .clock_reset_request(clock_reset),.stream_reset_pulse(stream_reset),.stream_clear_pulse(stream_clear),.usb_clear_pulse(usb_clear));
    task wr;input [31:0] addr,data;input bad;begin
      @(negedge clk);v=1;w=1;a=addr;d=data;@(posedge clk);if(!r || e!==bad)$fatal(1,"write %h",addr);
      @(negedge clk);v=0;w=0;
    end endtask
    task rr;input [31:0] addr,value;begin
      @(negedge clk);v=1;w=0;a=addr;@(posedge clk);if(!r || e || rd!==value)$fatal(1,"read %h got %h expected %h",addr,rd,value);
      @(negedge clk);v=0;
    end endtask
    initial begin
      drops=0;
      repeat(4)@(negedge clk);rst=1;
      rr('h0020,'h5a5a);rr('h0104,1);rr('h7004,1);rr('h8004,1);
      wr('h0104,0,1);wr('h0104,5,1);wr('h7004,5,1);wr('h8004,5,1);
      wr('h010c,0,0);wr('h700c,0,0);wr('h800c,0,0);
      wr('h7004,0,0);if(stream_en)$fatal(1,"stream enable");
      strb=2;wr('h7004,1,0);if(stream_en)$fatal(1,"strobe enable");strb=15;
      wr('h7004,9,0);if(!stream_en || !stream_clear || stream_reset)$fatal(1,"stream clear");
      @(negedge clk);if(stream_clear)$fatal(1,"clear pulse width");
      wr('h7010,0,0);wr('h7018,40,0);wr('h7034,7,0);
      wr('h7004,3,0);if(!stream_reset)$fatal(1,"stream reset");
      rr('h7010,1);rr('h7018,1536);rr('h7034,4);
      wr('h8004,0,0);if(usb_en)$fatal(1,"USB enable");
      link=0;repeat(2)@(negedge clk);rr('h800c,0);
      wr('h8004,9,0);if(!usb_en || !usb_clear)$fatal(1,"USB clear");
      rr('h800c,8);wr('h800c,8,0);rr('h800c,8);
      link=1;repeat(2)@(negedge clk);wr('h800c,8,0);rr('h800c,0);
      protocol_errors=1;repeat(2)@(negedge clk);rr('h800c,2);
      wr('h800c,2,0);rr('h800c,0);
      // A new protocol event on the W1C edge takes priority.
      @(negedge clk);v=1;w=1;a='h800c;d=2;crc_errors=1;
      @(negedge clk);v=0;w=0;rr('h800c,2);
      wr('h800c,2,0);protocol_errors=0;crc_errors=0;
      repeat(2)@(negedge clk);rr('h800c,0);
      locked=0;repeat(2)@(negedge clk);rr('h010c,'h20);wr('h010c,'h20,0);rr('h010c,'h20);
      locked=1;repeat(2)@(negedge clk);rr('h0124,1);wr('h010c,'h20,0);rr('h010c,0);
      wr('h0104,3,0);if(!clock_reset)$fatal(1,"clock reset request");rr('h0124,0);
      // W1C counter bits and concurrent increments are independent.
      drops=17;repeat(2)@(negedge clk);rr('h701c,17);rr('h700c,4);
      wr('h700c,4,0);rr('h700c,0);rr('h701c,17);
      wr('h701c,1,0);rr('h701c,16);
      @(negedge clk);v=1;w=1;a='h701c;d='hffffffff;drops=20;
      @(negedge clk);v=0;w=0;rr('h701c,3);rr('h700c,4);
      drops=0;repeat(2)@(negedge clk);rr('h701c,3);
      drops=2;repeat(2)@(negedge clk);rr('h701c,5);
      // Separate 64-bit RAW and normal masks, including high-byte strobes.
      wr('h002c,'h12345678,0);wr('h0030,'hdeadbeef,0);
      wr('h0034,'h76543210,0);wr('h0050,'h12345678,0);
      strb=8;wr('h0050,'habffffff,0);strb=15;
      if(sm!==64'hdeadbeef12345678 || raw!==64'hab34567876543210)$fatal(1,"mask independence");
      irq='h80000001;repeat(2)@(negedge clk);wr('h0038,'hffffffff,0);if(irqs!='h80000001)$fatal(1,"IRQ active priority");
      irq=0;strb=1;wr('h0038,'hffffffff,0);strb=15;rr('h0038,'h80000000);
      // No-op write strobes must not issue commands.
      strb=0;wr('h0044,0,0);if(kick)$fatal(1,"zero-strobe kick");
      wr('h8004,11,0);if(fxreset || usb_clear)$fatal(1,"zero-strobe reset");strb=15;
      wr('h0004,3,0);if(!reset || reason!=13)$fatal(1,"software reason");
      // Reset-reason W1C does not erase a simultaneous watchdog event.
      @(negedge clk);v=1;w=1;a='h003c;d='hffffffff;wd=1;
      @(negedge clk);v=0;w=0;if(reason!=2 || !reset || en)$fatal(1,"watchdog priority");
      @(negedge clk);if(reset)$fatal(1,"watchdog held level repeated pulse");
      wr('h0004,1,0);if(en || reset)$fatal(1,"held watchdog cannot re-enable");
      wd=0;wr('h003c,2,0);rr('h003c,0);
      // Live faults prevent clearing the aggregate until their page is clear.
      wr('h700c,'hffffffff,0);wr('h800c,'hffffffff,0);wr('h000c,'hffffffff,0);rr('h000c,0);
      wr('h0001,0,1);wr('h0010,0,1);wr('h0054,0,1);wr('h0120,'h00200000,1);
      wr('h0120,63,0);rr('h0120,63);wr('h0120,64,1);rr('h0120,63);
      @(negedge clk);v=1;a='h10000004;#1;if(r || e)$fatal(1,"full address decode");v=0;
      $display("tb_system_registers_semantics_PASS page CONTROL/ERROR, WSTRB, sticky W1C event priority, mask64, IRQ, counter snapshot, watchdog reason");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
