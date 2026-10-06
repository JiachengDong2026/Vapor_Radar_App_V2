`timescale 1ns/1ps
module tb_adc3660;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,cv=0,cw=0,mr=1,scan=0,stop_clock=0,slip=0;
    reg [31:0] ca=0,cd=0,cycle=7,phase=0;
    reg [3:0] cs=15;
    reg [63:0] tick=0;
    always @(posedge clk)if(rst_n)begin tick<=tick+1;phase<=phase+32'h10000;end
    wire cr,ce,mv,raw,dclkin,clkp,clkn,sen,sclk,arst,sync,dclk,fclk,da5,da6,db5,db6,configured;
    wire [31:0] rd,md,rate,expected,model_samples;
    wire [7:0] mf;
    wire [233:0] pack;
    wire sdio;
    adc_adc3660_if #(.SIMULATION(1),.FIFO_DEPTH(16)) dut(
        .sys_clk(clk),.rst_sys_n(rst_n),.wms_scan_start(scan),.wms_cycle_id(cycle),.wms_sine_phase(phase),.wms_phase_valid(1'b1),
        .timestamp_now(tick),.time_sync_valid(1'b1),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_valid(mv),.m_ready(mr),.m_data(md),.m_flags(mf),.m_tagged_sample(pack),
        .external_drop_increment(2'd0),.capture_drop_pulse(),.raw_enable(raw),.sample_rate_actual(rate),.expected_per_cycle(expected),
        .adc_da5(da5),.adc_da6(da6),.adc_db5(db5),.adc_db6(db6),.adc_dclk(dclk),.adc_fclk(fclk),.adc_dclkin(dclkin),
        .adc_clkp(clkp),.adc_clkn(clkn),.adc_sen(sen),.adc_sclk(sclk),.adc_sdio(sdio),.adc_reset(arst),.adc_sync(sync));
    adc3660_model model(.rst_n(!arst),.sample_clk(clkp),.dclkin(dclkin),.sen(sen),.sclk(sclk),.sdio(sdio),
        .stop_dclk(stop_clock),.slip(slip),.dclk(dclk),.fclk(fclk),.da5(da5),.da6(da6),.db5(db5),.db6(db6),
        .configured(configured),.sample_count(model_samples));
    task write_reg;
        input [31:0] a,d;input bad;
        begin @(negedge clk);cv=1;cw=1;ca=a;cd=d;@(posedge clk);if(!cr||ce!==bad)$fatal(1,"ADC1 cfg %h",a);@(negedge clk);cv=0;cw=0;end
    endtask
    task read_reg;
        input [31:0] a;output [31:0] d;
        begin @(negedge clk);cv=1;cw=0;ca=a;@(posedge clk);if(!cr||ce)$fatal(1,"ADC1 read %h",a);d=rd;@(negedge clk);cv=0;end
    endtask
    integer samples=0;
    reg checking=1;
    reg [15:0] expected_word;
    reg [31:0] source_index;
    always @(posedge clk)if(rst_n && mv&&mr)begin
        if(checking)begin
            source_index=(pack[167:104]+1)/8-1;
            expected_word=16'h8000+source_index;
            if(md!=={{16{expected_word[15]}},expected_word})$fatal(1,"ADC1 sample/tag n=%0d got=%h expected=%h tick=%0d source=%0d",samples,md,expected_word,pack[167:104],source_index);
            if(pack[103:72]!==((pack[167:104])*32'h10000))$fatal(1,"ADC1 phase association");
        end
        samples=samples+1;
    end
    reg [31:0] value,sync_before;
    reg [233:0] held;
    integer before_samples;
    initial begin #2000000;$fatal(1,"ADC3660 watchdog samples=%0d configured=%b state=%d",samples,configured,dut.state);end
    initial begin
        repeat(8)@(negedge clk);rst_n=1;scan=1;@(negedge clk);scan=0;
        write_reg(32'h4110,65000000,1);write_reg(32'h4104,1,0);
        wait(samples>=256);
        @(negedge clk);mr=0;wait(mv);held=pack;
        repeat(500)begin @(posedge clk);if(!mv||pack!==held)$fatal(1,"ADC1 backpressure stability");end
        read_reg(32'h4124,value);if(value==0)$fatal(1,"ADC1 drop counter");
        write_reg(32'h4104,9,0);@(negedge clk);mr=1;
        read_reg(32'h4138,sync_before);
        stop_clock=1;repeat(200)@(negedge clk);stop_clock=0;
        repeat(500)@(negedge clk);read_reg(32'h4138,value);if(value<=sync_before)$fatal(1,"ADC1 DCLK restart did not resynchronize");
        read_reg(32'h410c,value);if(!value[0])$fatal(1,"ADC1 DCLK stop timeout");
        checking=0;slip=1;repeat(8)@(negedge clk);slip=0;repeat(200)@(negedge clk);
        read_reg(32'h410c,value);if(!value[7])$fatal(1,"ADC1 frame alignment error missing");
        $display("ADC3660_PASS samples=%0d source_samples=%0d",samples,model_samples);$finish;
    end
endmodule
