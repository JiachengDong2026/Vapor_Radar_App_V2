`timescale 1ns/1ps
// AD4630-24 independent four-lane channels, shared physical conversion clock.
module tb_ad4630_dual #(parameter integer MIN_DELAYS=0);
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0,cw=0,mr0=1,mr1=1,scan0=0,scan1=0,stall=0;
    reg [31:0] ca=0,cd=0,cycle0=32'h10203040,cycle1=32'h50607080;
    reg [31:0] phase0=32'h10000000,phase1=32'h90000000;
    reg [63:0] tick=0,cycle_tick0=0,cycle_tick1=0;
    reg [1:0] ext0=0,ext1=0;
    always @(posedge clk)if(rst)begin
        tick<=tick+1;phase0<=phase0+32'h10000;phase1<=phase1+32'h30000;
        if(scan0)cycle_tick0<=tick;if(scan1)cycle_tick1<=tick;
    end
    wire cr,ce,mv0,mv1,cnv,busy,sdi,arst,csn,sck,configured;
    wire [31:0] rd,rate0,rate1,conversions;
    wire [7:0] sdo,ecode;
    wire [233:0] pack0,pack1;
    adc_ad4630_dual_if #(.SIMULATION(1),.FIFO_DEPTH(16)) dut(
        .sys_clk(clk),.rst_sys_n(rst),
        .wms0_scan_start(scan0),.wms0_cycle_id(cycle0),.wms0_sine_phase(phase0),.wms0_phase_valid(1'b1),
        .wms1_scan_start(scan1),.wms1_cycle_id(cycle1),.wms1_sine_phase(phase1),.wms1_phase_valid(1'b1),
        .timestamp_now(tick),.time_sync_valid(1'b1),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.cfg_error_code(ecode),
        .m0_valid(mv0),.m0_ready(mr0),.m0_tagged_sample(pack0),
        .m1_valid(mv1),.m1_ready(mr1),.m1_tagged_sample(pack1),
        .external_drop_increment0(ext0),.external_drop_increment1(ext1),
        .sample_rate_actual0(rate0),.sample_rate_actual1(rate1),
        .adc_sdo(sdo),.adc_busy(busy),.adc_sdi(sdi),.adc_rst_n(arst),.adc_cnv(cnv),.adc_cs_n(csn),.adc_sck(sck));
    ad4630_model #(.FPGA_OUTPUT_DELAY_NS(MIN_DELAYS?0.5:4.0),.DATA_DELAY_NS(MIN_DELAYS?1.4:5.6),
        .CSEN_DELAY_NS(MIN_DELAYS?0.0:6.8),.REGISTER_DELAY_NS(MIN_DELAYS?2.1:9.4)) model(.rst_n(arst),.cnv(cnv),.cs_n(csn),.sck(sck),.sdi(sdi),.stall_busy(stall),
        .busy(busy),.sdo(sdo),.conversions(conversions),.configured(configured));
    task write_reg;
        input [31:0] a,d;input [3:0] error_expected;
        begin
            @(negedge clk);cv=1;cw=1;ca=a;cd=d;#1;
            if(!cr||ce!==(error_expected!=0))$fatal(1,"DUAL_CFG a=%h d=%h err=%b expected=%d",a,d,ce,error_expected);
            if(error_expected!=0 && (a[8]?ecode[7:4]:ecode[3:0])!==error_expected)
                $fatal(1,"DUAL_ERROR_CODE a=%h got=%h expected=%h",a,ecode,error_expected);
            @(negedge clk);cv=0;cw=0;
        end
    endtask
    task read_reg;
        input [31:0] a;output [31:0] d;
        begin @(negedge clk);cv=1;cw=0;ca=a;#1;if(!cr||ce)$fatal(1,"DUAL_READ %h",a);d=rd;@(negedge clk);cv=0;end
    endtask
    // Store physical conversion provenance before the pin model's pad delay.
    reg [63:0] cap_tick[0:4095],cap_cycle_tick0[0:4095],cap_cycle_tick1[0:4095];
    reg [31:0] cap_phase0[0:4095],cap_phase1[0:4095],cap_cycle0[0:4095],cap_cycle1[0:4095];
    integer captures=0,received0=0,received1=0;
    integer period_ns=1000;
    realtime last_cnv=0;
    reg enforce_period=0,guard_reset=0;
    always @(negedge arst)if(guard_reset)$fatal(1,"DUAL_LOCAL_RESET_DISTURBED_PHYSICAL_ADC");
    always @(posedge cnv)begin
        if(enforce_period && last_cnv!=0 && $realtime-last_cnv!=period_ns)
            $fatal(1,"DUAL_SHARED_PERIOD got=%f expected=%0d",$realtime-last_cnv,period_ns);
        last_cnv=$realtime;
        cap_tick[captures]=tick-1;cap_phase0[captures]=phase0-32'h10000;cap_phase1[captures]=phase1-32'h30000;
        cap_cycle_tick0[captures]=cycle_tick0;cap_cycle_tick1[captures]=cycle_tick1;
        cap_cycle0[captures]=cycle0;cap_cycle1[captures]=cycle1;captures=captures+1;
    end
    task check_sample;
        input integer channel;input [233:0] p;
        integer i,found;reg [23:0] expected;
        begin
            found=-1;
            for(i=0;i<captures;i=i+1)if(p[167:104]===cap_tick[i])found=i;
            if(found<0)$fatal(1,"DUAL_UNKNOWN_CAPTURE ch=%0d tick=%0d",channel,p[167:104]);
            expected=channel?model.pattern_ch1(found):model.pattern(found);
            if(p[31:0]!=={{8{expected[23]}},expected})$fatal(1,"DUAL_LANE_DATA ch=%0d conversion=%0d got=%h expected=%h",channel,found,p[31:0],expected);
            if(p[32]!==((expected==24'h7fffff)||(expected==24'h800000)))$fatal(1,"DUAL_CLIP_FLAG ch=%0d",channel);
            if(p[103:72] !== (channel?cap_phase1[found]:cap_phase0[found]) ||
               p[71:40] !== (channel?cap_cycle1[found]:cap_cycle0[found]) ||
               p[231:168] !== (channel?cap_cycle_tick1[found]:cap_cycle_tick0[found]) || p[233:232]!==2'b11)
                $fatal(1,"DUAL_WMS_TAG ch=%0d conversion=%0d got=%h",channel,found,p);
        end
    endtask
    reg hold0=0,hold1=0;
    reg [233:0] held0,held1;
    always @(posedge clk)if(rst)begin
        if(hold0 && (!mv0 || pack0!==held0))$fatal(1,"DUAL_STALLED_SAMPLE0_CHANGED");
        if(hold1 && (!mv1 || pack1!==held1))$fatal(1,"DUAL_STALLED_SAMPLE1_CHANGED");
        hold0=mv0&&!mr0;held0=pack0;hold1=mv1&&!mr1;held1=pack1;
        if(mv0&&mr0)begin check_sample(0,pack0);received0=received0+1;end
        if(mv1&&mr1)begin check_sample(1,pack1);received1=received1+1;end
    end
    integer n0,n1,before_count;reg [31:0] value,drop1;
    initial begin
        repeat(8)@(negedge clk);rst=1;
        scan0=1;@(negedge clk);scan0=0;repeat(3)@(negedge clk);scan1=1;@(negedge clk);scan1=0;
        wait(configured);repeat(10)@(negedge clk);
        read_reg('h4118,value);if(value!==32'h00011800)$fatal(1,"DUAL_CH1_FORMAT");
        write_reg('h4110,12500000,6);write_reg('h4130,'h210,6);write_reg('h4134,100,6);
        write_reg('h4010,2000000,7);read_reg('h4010,value);if(value!=1000000)$fatal(1,"DUAL_INVALID_RATE_CHANGED");
        if(rate0!=1000000||rate1!=1000000)$fatal(1,"DUAL_INITIAL_RATES");
        write_reg('h4004,1,0);write_reg('h4104,1,0);guard_reset=1;enforce_period=1;
        wait(received0>=16&&received1>=16);
        // CH1 backpressure must drop only CH1; physical conversions and CH0 continue.
        @(negedge clk);mr1=0;n0=received0;before_count=conversions;
        repeat(6000)@(negedge clk);
        if(received0-n0<55||conversions-before_count<55)$fatal(1,"DUAL_BACKPRESSURE_STOPPED_PEER");
        read_reg('h4024,value);if(value!=0)$fatal(1,"DUAL_CH1_DROP_CHARGED_TO_CH0");
        read_reg('h4124,drop1);if(drop1<30)$fatal(1,"DUAL_CH1_OVERFLOW_NOT_COUNTED");
        @(negedge clk);mr1=1;repeat(200)@(negedge clk);
        @(negedge clk);ext0=2;@(negedge clk);ext0=0;
        read_reg('h4024,value);if(value!=2)$fatal(1,"DUAL_EXTERNAL_DROP0");
        read_reg('h4124,value);if(value!=drop1)$fatal(1,"DUAL_EXTERNAL_DROP_LEAKED");
        // Disable CH0; resetting its shared PHY while CH1 is live must be rejected.
        write_reg('h4004,0,0);repeat(200)@(negedge clk);n0=received0;n1=received1;
        write_reg('h4004,2,8);write_reg('h4004,4,8);
        repeat(1200)@(negedge clk);
        if(received0!=n0||received1-n1<10)$fatal(1,"DUAL_CH1_ONLY_ENABLE");
        // CH1 soft reset and CLEAR affect only CH1 while CH0 remains enabled.
        write_reg('h4004,1,0);repeat(300)@(negedge clk);n0=received0;
        @(posedge cnv);write_reg('h4104,2,0);repeat(300)@(negedge clk);n1=received1;
        repeat(700)@(negedge clk);
        if(received1!=n1||received0-n0<8)$fatal(1,"DUAL_LOCAL_SOFT_RESET_ISOLATION");
        read_reg('h4128,value);if(value!=0)$fatal(1,"DUAL_LOCAL_SOFT_RESET_COUNTER");
        write_reg('h4104,1,0);repeat(300)@(negedge clk);
        @(posedge cnv);write_reg('h4104,9,0);repeat(1000)@(negedge clk);
        // Shared timing commits are legal only while both logical channels stop.
        enforce_period=0;write_reg('h4004,0,0);write_reg('h4104,0,0);repeat(200)@(negedge clk);
        write_reg('h4010,500000,0);write_reg('h4004,4,0);write_reg('h4104,1,8);write_reg('h4004,1,8);
        repeat(120)@(negedge clk);read_reg('h4008,value);if(value[2])$fatal(1,"DUAL_RATE_COMMIT_STUCK");
        read_reg('h4110,value);if(value!=500000)$fatal(1,"DUAL_CH1_SHARED_REQUEST_READBACK");
        read_reg('h4114,value);if(value!=500000||rate0!=value||rate1!=value)$fatal(1,"DUAL_RATE_EXPORT_MISMATCH");
        period_ns=2000;last_cnv=0;enforce_period=1;n0=received0;n1=received1;
        write_reg('h4104,1,0);wait(received1>=n1+12);
        if(received0!=n0)$fatal(1,"DUAL_DISABLED_CH0_PRODUCED_DATA");
        write_reg('h4004,1,0);wait(received0>=n0+5);enforce_period=0;stall=1;
        repeat(500)@(negedge clk);
        read_reg('h400c,value);if(!value[0])$fatal(1,"DUAL_TIMEOUT0_MISSING");
        read_reg('h410c,value);if(!value[0])$fatal(1,"DUAL_TIMEOUT1_MISSING");
        $display("AD4630_DUAL_PASS ch0=%0d ch1=%0d conversions=%0d independent_lanes signed_boundaries WMS_tags rate reset backpressure drops timeout",received0,received1,conversions);
        $finish;
    end
    initial begin #1000000;$fatal(1,"AD4630_DUAL_WATCHDOG");end
endmodule
