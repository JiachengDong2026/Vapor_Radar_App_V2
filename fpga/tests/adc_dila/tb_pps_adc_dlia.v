`timescale 1ns/1ps
module tb_pps_adc_dlia;
    reg  sys_clk=0;
    reg  rst_sys_n=0;
    reg [63:0] timestamp_now=0;
    reg  time_sync_valid=0;
    wire wms0_scan_start;
    wire [31:0] wms0_cycle_id;
    wire [31:0] wms0_sine_phase;
    wire wms0_phase_valid;
    wire wms1_scan_start;
    wire [31:0] wms1_cycle_id;
    wire [31:0] wms1_sine_phase;
    wire wms1_phase_valid;
    wire cfg_valid;
    wire cfg_write;
    wire [31:0] cfg_addr;
    wire [31:0] cfg_wdata;
    wire [3:0] cfg_wstrb;
    wire  cfg_ready;
    wire [31:0] cfg_rdata;
    wire  cfg_error;
    wire  ADC_AD4630_SDI;
    wire  ADC_AD4630_RSTN;
    wire  ADC_AD4630_CNV;
    wire  ADC_AD4630_CSN;
    wire  ADC_AD4630_SCK;
    wire  ADC_AD4630_BUSY;
    wire [7:0] ADC_AD4630_SDO;
    wire  ADC_ADC3660_DA5;
    wire  ADC_ADC3660_DA6;
    wire  ADC_ADC3660_DB5;
    wire  ADC_ADC3660_DB6;
    wire  ADC_ADC3660_DCLK;
    wire  ADC_ADC3660_FCLK;
    wire  ADC_ADC3660_DCLKIN;
    wire  ADC_ADC3660_CLKP;
    wire  ADC_ADC3660_CLKN;
    wire  ADC_ADC3660_SEN;
    wire  ADC_ADC3660_SCLK;
    wire  ADC_ADC3660_RST;
    wire  ADC_ADC3660_SYNC;
    wire  ADC_ADC3660_SDIO;
    wire  raw0_valid;
    reg  raw0_ready=0;
    wire [31:0] raw0_data;
    wire [7:0] raw0_flags;
    wire [31:0] raw0_capture_cycle_id;
    wire [31:0] raw0_capture_phase;
    wire [63:0] raw0_capture_timestamp;
    wire [63:0] raw0_cycle_timestamp;
    wire  raw0_capture_phase_valid;
    wire  raw0_capture_time_sync_valid;
    wire  dila0_valid;
    reg  dila0_ready=0;
    wire [31:0] dila0_data;
    wire [3:0] dila0_keep;
    wire  dila0_sof;
    wire  dila0_last;
    wire [15:0] dila0_source_id;
    wire [15:0] dila0_msg_id;
    wire [63:0] dila0_timestamp;
    wire [31:0] dila0_cycle_id;
    wire [31:0] dila0_flags;
    wire  raw1_valid;
    reg  raw1_ready=0;
    wire [31:0] raw1_data;
    wire [7:0] raw1_flags;
    wire [31:0] raw1_capture_cycle_id;
    wire [31:0] raw1_capture_phase;
    wire [63:0] raw1_capture_timestamp;
    wire [63:0] raw1_cycle_timestamp;
    wire  raw1_capture_phase_valid;
    wire  raw1_capture_time_sync_valid;
    wire  dila1_valid;
    reg  dila1_ready=0;
    wire [31:0] dila1_data;
    wire [3:0] dila1_keep;
    wire  dila1_sof;
    wire  dila1_last;
    wire [15:0] dila1_source_id;
    wire [15:0] dila1_msg_id;
    wire [63:0] dila1_timestamp;
    wire [31:0] dila1_cycle_id;
    wire [31:0] dila1_flags;
    wire [31:0] raw0_sample_rate_hz;
    wire [31:0] raw1_sample_rate_hz;
    wire [31:0] raw0_fifo_level;
    wire [31:0] raw1_fifo_level;
    wire [31:0] dila0_fifo_level;
    wire [31:0] dila1_fifo_level;
    wire  raw0_idle;
    wire  raw1_idle;
    wire  dila0_idle;
    wire  dila1_idle;
    wire [15:0] cfg_error_code;
    wire ar,ae,wr,we;wire [31:0] ad,wd;
    wire [1:0] pm,aborted,tr,drained,ds,ss,sd,dr,dc,dl;
    reg pps=0;reg [31:0] seq=0;reg [63:0] ptick=0;
    assign cfg_ready=ar|wr;assign cfg_error=ae|we;assign cfg_rdata=ad|wd;
    cfg_test_bfm bus(.clk(sys_clk),.rst_n(rst_sys_n),.cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),.cfg_ready(cfg_ready),.cfg_error(cfg_error),.cfg_rdata(cfg_rdata));
    wms_dac_dual wave(.sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.enable(2'b11),.timestamp_now(timestamp_now),.time_sync_valid(1'b1),
        .pps_pulse(pps),.pps_qualified(1'b1),.pps_tick(ptick),.pps_seq(seq),.dlia_trigger_ready(tr),.dlia_scan_drained(drained),.pps_mode(pm),.scan_aborted(aborted),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),.cfg_ready(wr),.cfg_error(we),.cfg_rdata(wd),
        .scan_start({wms1_scan_start,wms0_scan_start}),.phase_valid({wms1_phase_valid,wms0_phase_valid}),.cycle_id({wms1_cycle_id,wms0_cycle_id}),.sine_phase({wms1_sine_phase,wms0_sine_phase}),
        .dac_sclk(ds),.dac_sync_n(ss),.dac_sdin(sd),.dac_sdo(2'b00),.dac_rst_n(dr),.dac_clr_n(dc),.dac_ldac_n(dl));
    always #5 sys_clk=~sys_clk;
    always @(posedge sys_clk)if(rst_sys_n)timestamp_now<=timestamp_now+1'b1;
    member1_adc_dila #(.SIMULATION(1),.DUAL_AD4630(1)) dut(
        .pps_mode(pm),.scan_aborted(aborted),.pps_trigger_ready(tr),.pps_scan_drained(drained),
        .sys_clk(sys_clk),
        .rst_sys_n(rst_sys_n),
        .timestamp_now(timestamp_now),
        .time_sync_valid(time_sync_valid),
        .wms0_scan_start(wms0_scan_start),
        .wms0_cycle_id(wms0_cycle_id),
        .wms0_sine_phase(wms0_sine_phase),
        .wms0_phase_valid(wms0_phase_valid),
        .wms1_scan_start(wms1_scan_start),
        .wms1_cycle_id(wms1_cycle_id),
        .wms1_sine_phase(wms1_sine_phase),
        .wms1_phase_valid(wms1_phase_valid),
        .cfg_valid(cfg_valid),
        .cfg_write(cfg_write),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .cfg_wstrb(cfg_wstrb),
        .cfg_ready(ar),
        .cfg_rdata(ad),
        .cfg_error(ae),
        .ADC_AD4630_SDI(ADC_AD4630_SDI),
        .ADC_AD4630_RSTN(ADC_AD4630_RSTN),
        .ADC_AD4630_CNV(ADC_AD4630_CNV),
        .ADC_AD4630_CSN(ADC_AD4630_CSN),
        .ADC_AD4630_SCK(ADC_AD4630_SCK),
        .ADC_AD4630_BUSY(ADC_AD4630_BUSY),
        .ADC_AD4630_SDO(ADC_AD4630_SDO),
        .ADC_ADC3660_DA5(ADC_ADC3660_DA5),
        .ADC_ADC3660_DA6(ADC_ADC3660_DA6),
        .ADC_ADC3660_DB5(ADC_ADC3660_DB5),
        .ADC_ADC3660_DB6(ADC_ADC3660_DB6),
        .ADC_ADC3660_DCLK(ADC_ADC3660_DCLK),
        .ADC_ADC3660_FCLK(ADC_ADC3660_FCLK),
        .ADC_ADC3660_DCLKIN(ADC_ADC3660_DCLKIN),
        .ADC_ADC3660_CLKP(ADC_ADC3660_CLKP),
        .ADC_ADC3660_CLKN(ADC_ADC3660_CLKN),
        .ADC_ADC3660_SEN(ADC_ADC3660_SEN),
        .ADC_ADC3660_SCLK(ADC_ADC3660_SCLK),
        .ADC_ADC3660_RST(ADC_ADC3660_RST),
        .ADC_ADC3660_SYNC(ADC_ADC3660_SYNC),
        .ADC_ADC3660_SDIO(ADC_ADC3660_SDIO),
        .raw0_valid(raw0_valid),
        .raw0_ready(raw0_ready),
        .raw0_data(raw0_data),
        .raw0_flags(raw0_flags),
        .raw0_capture_cycle_id(raw0_capture_cycle_id),
        .raw0_capture_phase(raw0_capture_phase),
        .raw0_capture_timestamp(raw0_capture_timestamp),
        .raw0_cycle_timestamp(raw0_cycle_timestamp),
        .raw0_capture_phase_valid(raw0_capture_phase_valid),
        .raw0_capture_time_sync_valid(raw0_capture_time_sync_valid),
        .dila0_valid(dila0_valid),
        .dila0_ready(dila0_ready),
        .dila0_data(dila0_data),
        .dila0_keep(dila0_keep),
        .dila0_sof(dila0_sof),
        .dila0_last(dila0_last),
        .dila0_source_id(dila0_source_id),
        .dila0_msg_id(dila0_msg_id),
        .dila0_timestamp(dila0_timestamp),
        .dila0_cycle_id(dila0_cycle_id),
        .dila0_flags(dila0_flags),
        .raw1_valid(raw1_valid),
        .raw1_ready(raw1_ready),
        .raw1_data(raw1_data),
        .raw1_flags(raw1_flags),
        .raw1_capture_cycle_id(raw1_capture_cycle_id),
        .raw1_capture_phase(raw1_capture_phase),
        .raw1_capture_timestamp(raw1_capture_timestamp),
        .raw1_cycle_timestamp(raw1_cycle_timestamp),
        .raw1_capture_phase_valid(raw1_capture_phase_valid),
        .raw1_capture_time_sync_valid(raw1_capture_time_sync_valid),
        .dila1_valid(dila1_valid),
        .dila1_ready(dila1_ready),
        .dila1_data(dila1_data),
        .dila1_keep(dila1_keep),
        .dila1_sof(dila1_sof),
        .dila1_last(dila1_last),
        .dila1_source_id(dila1_source_id),
        .dila1_msg_id(dila1_msg_id),
        .dila1_timestamp(dila1_timestamp),
        .dila1_cycle_id(dila1_cycle_id),
        .dila1_flags(dila1_flags),
        .raw0_sample_rate_hz(raw0_sample_rate_hz),
        .raw1_sample_rate_hz(raw1_sample_rate_hz),
        .raw0_fifo_level(raw0_fifo_level),
        .raw1_fifo_level(raw1_fifo_level),
        .dila0_fifo_level(dila0_fifo_level),
        .dila1_fifo_level(dila1_fifo_level),
        .raw0_idle(raw0_idle),
        .raw1_idle(raw1_idle),
        .dila0_idle(dila0_idle),
        .dila1_idle(dila1_idle),
        .cfg_error_code(cfg_error_code));
    wire configured0,configured1;wire [31:0] conversions,model_samples;
    ad4630_model model0(.rst_n(ADC_AD4630_RSTN),.cnv(ADC_AD4630_CNV),.cs_n(ADC_AD4630_CSN),.sck(ADC_AD4630_SCK),.sdi(ADC_AD4630_SDI),
        .stall_busy(1'b0),.busy(ADC_AD4630_BUSY),.sdo(ADC_AD4630_SDO),.conversions(conversions),.configured(configured0));
    assign {ADC_ADC3660_DA5,ADC_ADC3660_DA6,ADC_ADC3660_DB5,ADC_ADC3660_DB6,ADC_ADC3660_DCLK,ADC_ADC3660_FCLK}=6'd0;
    integer frames0=0,frames1=0,n=0,captured0=0,captured1=0;
    reg [63:0] tstart0=0,tstart1=0,tend0=0,tend1=0;reg pv0=0,pv1=0;
    reg [31:0] value;
    always @(posedge sys_clk)if(rst_sys_n)begin
        pv0<=wms0_phase_valid;pv1<=wms1_phase_valid;
        if(wms0_scan_start)tstart0<=timestamp_now;
        if(wms1_scan_start)tstart1<=timestamp_now;
        if(pv0 && !wms0_phase_valid)tend0<=timestamp_now;
        if(pv1 && !wms1_phase_valid)tend1<=timestamp_now;
        if(seq==1 && raw0_valid && raw0_ready && raw0_capture_phase_valid)begin
            captured0=captured0+1;
            if(raw0_cycle_timestamp!=tstart0 || raw0_capture_timestamp<tstart0 ||
               (tend0!=0 && raw0_capture_timestamp>=tend0))$fatal(1,"CNV tag window0");
        end
        if(seq==1 && raw1_valid && raw1_ready && raw1_capture_phase_valid)begin
            captured1=captured1+1;
            if(raw1_cycle_timestamp!=tstart1 || raw1_capture_timestamp<tstart1 ||
               (tend1!=0 && raw1_capture_timestamp>=tend1))$fatal(1,"CNV tag window1");
        end
        if(seq==1 && dila0_valid && dila0_ready && dila0_last)begin
            if(dila0_timestamp!=tstart0 || dila0_cycle_id!=1)$fatal(1,"DLIA tag0");frames0=frames0+1;
        end
        if(seq==1 && dila1_valid && dila1_ready && dila1_last)begin
            if(dila1_timestamp!=tstart1 || dila1_cycle_id!=1)$fatal(1,"DLIA tag1");frames1=frames1+1;
        end
    end
    initial begin
        repeat(10)@(negedge sys_clk);rst_sys_n=1;time_sync_valid=1;raw0_ready=1;raw1_ready=1;dila0_ready=1;dila1_ready=1;
        for(n=0;n<2;n=n+1)begin
            bus.write32('h403c+n*256,1);bus.write32('h501c+n*256,100000);bus.write32('h5020+n*256,7);bus.write32('h5004+n*256,4);
            bus.write32('h3004+n*256,1);bus.write32('h2010+n*256,n==0?6250000:12500000);
            bus.write32('h201c+n*256,20000000);bus.write32('h204c+n*256,1);bus.write32('h2004+n*256,4);
        end
        wait(dut.g_dual.u_adc_dual.initialized);repeat(200)@(negedge sys_clk);
        bus.write32('h4004,1);bus.write32('h4104,1);bus.write32('h5004,1);bus.write32('h5104,1);
        bus.write32('h2004,1);bus.write32('h2104,1);
        wait(wave.channels[0].channel.wms.armed && wave.channels[1].channel.wms.armed);
        repeat(60000)@(negedge sys_clk);
        if(dut.din0_drops!=0 || dut.din1_drops!=0 || dut.u_dila0.error_status!=0 || dut.u_dila1.error_status!=0)$fatal(1,"idle conversions leaked into DLIA/errors");
        @(negedge sys_clk);seq=1;ptick=timestamp_now;pps=1;@(negedge sys_clk);pps=0;
        wait(frames0==1 && frames1==1);
        wait(wave.channels[0].channel.wms.armed && wave.channels[1].channel.wms.armed);
        if(tstart0!=tstart1 || tend0-tstart0!=16000 || tend1-tstart1!=8000)$fatal(1,"DAC window timing");
        if(captured0!=160 || captured1!=80 || dut.u_dila0.input_count!=160 || dut.u_dila1.input_count!=80)$fatal(1,"actual ADC window counts %d/%d",captured0,captured1);
        if(dut.din0_drops || dut.din1_drops)$fatal(1,"ADC fanout loss");
        // Simultaneously stopping capture and DLIA must still allow WMS drain to finish.
        @(negedge sys_clk);seq=2;ptick=timestamp_now;pps=1;@(negedge sys_clk);pps=0;
        wait(wms0_scan_start);repeat(1500)@(negedge sys_clk);
        bus.write32('h2004,0);bus.write32('h2104,0);
        bus.write32('h4004,0);bus.write32('h4104,0);bus.write32('h5004,0);bus.write32('h5104,0);
        wait(!wave.channels[0].channel.wms.burst_busy && !wave.channels[1].channel.wms.burst_busy);
        bus.write32('h204c,0);bus.write32('h214c,0);
        $display("PPS_ADC_DLIA_PASS actual_SPI_CNV_fifo_tags_two_channels_normal_tail_background_drain_stop");$finish;
    end
    initial begin #3000000;$fatal(1,"PPS ADC timeout");end
endmodule
