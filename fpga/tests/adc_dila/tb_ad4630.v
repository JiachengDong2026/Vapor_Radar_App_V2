`timescale 1ns/1ps
module tb_ad4630 #(parameter integer MIN_DELAYS=0);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,cv=0,cw=0,mr=1,scan=0,stall=0;
    reg [31:0] ca=0,cd=0,cycle=1,phase=0;
    reg [3:0] cs=15;
    reg [63:0] tick=0;
    always @(posedge clk)if(rst_n)begin tick<=tick+1;phase<=phase+32'h10000;end
    wire cr,ce,mv,raw,cnv,busy,sdi,arst,csn,sck,configured;
    wire [31:0] rd,md,rate,expected,conversions;
    wire [7:0] mf,sdo;
    wire [233:0] pack;
    adc_ad4630_if #(.SIMULATION(1),.FIFO_DEPTH(16)) dut(
        .sys_clk(clk),.rst_sys_n(rst_n),.wms_scan_start(scan),.wms_cycle_id(cycle),.wms_sine_phase(phase),.wms_phase_valid(1'b1),
        .timestamp_now(tick),.time_sync_valid(1'b1),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_valid(mv),.m_ready(mr),.m_data(md),.m_flags(mf),.m_tagged_sample(pack),
        .external_drop_increment(2'd0),.capture_drop_pulse(),.raw_enable(raw),.sample_rate_actual(rate),.expected_per_cycle(expected),.adc_sdo(sdo),.adc_busy(busy),.adc_sdi(sdi),
        .adc_rst_n(arst),.adc_cnv(cnv),.adc_cs_n(csn),.adc_sck(sck));
    ad4630_model #(.FPGA_OUTPUT_DELAY_NS(MIN_DELAYS?0.5:4.0),.DATA_DELAY_NS(MIN_DELAYS?1.4:5.6),
        .CSEN_DELAY_NS(MIN_DELAYS?0.0:6.8),.REGISTER_DELAY_NS(MIN_DELAYS?2.1:9.4)) model(.rst_n(arst),.cnv(cnv),.cs_n(csn),.sck(sck),.sdi(sdi),.stall_busy(stall),.busy(busy),.sdo(sdo),.conversions(conversions),.configured(configured));
    task write_reg;
        input [31:0] a,d;input [3:0] strb;input bad;
        begin @(negedge clk);cv=1;cw=1;ca=a;cd=d;cs=strb;@(posedge clk);if(!cr||ce!==bad)$fatal(1,"ADC0 cfg %h",a);@(negedge clk);cv=0;cw=0;end
    endtask
    task read_reg;
        input [31:0] a;output [31:0] d;
        begin @(negedge clk);cv=1;cw=0;ca=a;@(posedge clk);if(!cr||ce)$fatal(1,"ADC0 read %h",a);d=rd;@(negedge clk);cv=0;end
    endtask
    realtime previous_cnv=0;
    always @(posedge cnv)if(!stall)begin
        if(previous_cnv!=0 && $realtime-previous_cnv!=1000)$fatal(1,"AD4630_1MSPS_PERIOD %f",$realtime-previous_cnv);
        previous_cnv=$realtime;
    end
    integer samples=0;
    reg checking=1;
    reg [23:0] expected_word;
    reg [63:0] capture_ticks[0:255];
    reg [31:0] capture_phases[0:255];
    integer capture_count=0;
    always @(posedge cnv)begin capture_ticks[capture_count]=tick-1;capture_phases[capture_count]=phase-32'h10000;capture_count=capture_count+1;end
    always @(posedge clk)if(rst_n && mv&&mr && checking)begin
        expected_word=model.pattern(samples);
        if(md!=={{8{expected_word[23]}},expected_word})$fatal(1,"ADC0 data n=%0d got=%h expected=%h",samples,md,expected_word);
        if(pack[167:104]!==capture_ticks[samples] || pack[103:72]!==capture_phases[samples])
            $fatal(1,"ADC0 capture tag n=%0d got tick=%0d exp=%0d phase=%h exp=%h",samples,pack[167:104],capture_ticks[samples],pack[103:72],capture_phases[samples]);
        samples=samples+1;
    end
    reg [31:0] value;
    reg [233:0] held;
    integer before_conversions;
    initial begin #500000;$fatal(1,"AD4630 watchdog");end
    initial begin
        repeat(8)@(negedge clk);rst_n=1;scan=1;@(negedge clk);scan=0;
        write_reg(32'h4010,2000000,15,1);read_reg(32'h4010,value);if(value!=1000000)$fatal(1,"Rejected rate changed");
        @(negedge clk);cv=1;ca=32'h4100;@(posedge clk);if(cr||ce||rd!=0)$fatal(1,"Foreign page");@(negedge clk);cv=0;
        write_reg(32'h4030,1,15,1);read_reg(32'h4030,value);if(value!=2)$fatal(1,"Rejected CNV width changed");
        write_reg(32'h403c,1,1,0);write_reg(32'h4004,1,15,0);
        wait(samples==16);checking=0;@(negedge clk);mr=0;
        wait(mv);held=pack;before_conversions=conversions;
        repeat(4000)begin @(posedge clk);if(!mv||pack!==held)$fatal(1,"ADC0 stalled metadata changed");end
        if(conversions-before_conversions<30)$fatal(1,"Physical sampling stopped under backpressure");
        read_reg(32'h4024,value);if(value==0)$fatal(1,"ADC0 overflow not counted");
        write_reg(32'h4004,9,15,0);@(negedge clk);mr=1;
        stall=1;repeat(250)@(negedge clk);read_reg(32'h400c,value);if(!value[0])$fatal(1,"Busy timeout missing");
        write_reg(32'h4004,2,15,0);stall=0;repeat(10)@(negedge clk);read_reg(32'h4028,value);if(value!=0)$fatal(1,"Soft reset sample count");
        $display("AD4630_PASS samples=%0d continuous_conversions=%0d",samples,conversions);$finish;
    end
endmodule
