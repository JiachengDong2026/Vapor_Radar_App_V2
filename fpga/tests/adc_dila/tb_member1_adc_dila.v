`timescale 1ns/1ps
module tb_member1_adc_dila;
    reg  sys_clk=0;
    reg  rst_sys_n=0;
    reg [63:0] timestamp_now=0;
    reg  time_sync_valid=0;
    reg  wms0_scan_start=0;
    reg [31:0] wms0_cycle_id=0;
    reg [31:0] wms0_sine_phase=0;
    reg  wms0_phase_valid=0;
    reg  wms1_scan_start=0;
    reg [31:0] wms1_cycle_id=0;
    reg [31:0] wms1_sine_phase=0;
    reg  wms1_phase_valid=0;
    reg  cfg_valid=0;
    reg  cfg_write=0;
    reg [31:0] cfg_addr=0;
    reg [31:0] cfg_wdata=0;
    reg [3:0] cfg_wstrb=0;
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
    always #5 sys_clk=~sys_clk;
    always @(posedge sys_clk)if(rst_sys_n)timestamp_now<=timestamp_now+1'b1;
    member1_adc_dila #(.SIMULATION(1)) dut(
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
        .cfg_ready(cfg_ready),
        .cfg_rdata(cfg_rdata),
        .cfg_error(cfg_error),
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
    adc3660_model model1(.rst_n(!ADC_ADC3660_RST),.sample_clk(ADC_ADC3660_CLKP),.dclkin(ADC_ADC3660_DCLKIN),.sen(ADC_ADC3660_SEN),.sclk(ADC_ADC3660_SCLK),.sdio(ADC_ADC3660_SDIO),
        .stop_dclk(1'b0),.slip(1'b0),.dclk(ADC_ADC3660_DCLK),.fclk(ADC_ADC3660_FCLK),.da5(ADC_ADC3660_DA5),.da6(ADC_ADC3660_DA6),.db5(ADC_ADC3660_DB5),.db6(ADC_ADC3660_DB6),
        .configured(configured1),.sample_count(model_samples));
    task write_reg;
        input [31:0] a,d;
        begin @(negedge sys_clk);cfg_valid=1;cfg_write=1;cfg_addr=a;cfg_wdata=d;cfg_wstrb=15;#1;
            if(!cfg_ready||cfg_error)$fatal(1,"wrapper cfg %h",a);
            @(negedge sys_clk);cfg_valid=0;cfg_write=0;
        end
    endtask
    task start_cycle;
        input [31:0] n;
        begin @(negedge sys_clk);wms0_cycle_id=n;wms1_cycle_id=n;wms0_scan_start=1;wms1_scan_start=1;
            wms0_phase_valid=1;wms1_phase_valid=1;
            @(negedge sys_clk);wms0_scan_start=0;wms1_scan_start=0;
        end
    endtask
    integer frames0=0,frames1=0,raw_seen=0;
    reg [31:0] rng=32'h16452983;
    reg hold0=0,hold1=0;
    reg [231:0] held0,held1;
    always @(negedge sys_clk)begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        dila0_ready=rng[0];dila1_ready=rng[1];
    end
    always @(posedge sys_clk)if(rst_sys_n)begin
        if(hold0&&(!dila0_valid||held0!=={dila0_data,dila0_keep,dila0_sof,dila0_last,dila0_source_id,dila0_msg_id,dila0_timestamp,dila0_cycle_id,dila0_flags}))$fatal(1,"wrapper stability0");
        if(hold1&&(!dila1_valid||held1!=={dila1_data,dila1_keep,dila1_sof,dila1_last,dila1_source_id,dila1_msg_id,dila1_timestamp,dila1_cycle_id,dila1_flags}))$fatal(1,"wrapper stability1");
        hold0=dila0_valid&&!dila0_ready;held0={dila0_data,dila0_keep,dila0_sof,dila0_last,dila0_source_id,dila0_msg_id,dila0_timestamp,dila0_cycle_id,dila0_flags};
        hold1=dila1_valid&&!dila1_ready;held1={dila1_data,dila1_keep,dila1_sof,dila1_last,dila1_source_id,dila1_msg_id,dila1_timestamp,dila1_cycle_id,dila1_flags};
        if(dila0_valid&&dila0_ready)begin
            if(dila0_keep!=15||dila0_source_id!=16'h30||dila0_msg_id!=16'h1001||dila0_cycle_id<1||dila0_cycle_id>3)$fatal(1,"wrapper metadata0");
            if(dila0_last)begin frames0=frames0+1;if(dila0_cycle_id==3&&!dila0_flags[5])$fatal(1,"STOP partial0");end
        end
        if(dila1_valid&&dila1_ready)begin
            if(dila1_keep!=15||dila1_source_id!=16'h31||dila1_msg_id!=16'h1001||dila1_cycle_id<1||dila1_cycle_id>3)$fatal(1,"wrapper metadata1");
            if(dila1_last)begin frames1=frames1+1;if(dila1_cycle_id==3&&!dila1_flags[5])$fatal(1,"STOP partial1");end
        end
        if(raw1_valid&&raw1_ready)begin
            raw_seen=raw_seen+1;
            if(raw1_capture_phase_valid&&raw1_capture_phase!=0)$fatal(1,"raw captured phase");
        end
    end
    initial begin
        repeat(10)@(negedge sys_clk);rst_sys_n=1;time_sync_valid=1;raw1_ready=1;
        write_reg(32'h403c,1);write_reg(32'h413c,1);
        write_reg(32'h5020,7);write_reg(32'h5120,7);
        write_reg(32'h501c,100000);write_reg(32'h511c,100000);
        write_reg(32'h5004,4);write_reg(32'h5104,4);
        wait(dut.u_adc0.initialized&&dut.u_adc1.initialized);
        if(raw0_sample_rate_hz!=1000000 || raw1_sample_rate_hz!=12500000)$fatal(1,"sample rate export");
        write_reg(32'h4004,1);write_reg(32'h4104,1);write_reg(32'h5004,1);write_reg(32'h5104,1);
        start_cycle(1);repeat(20000)@(negedge sys_clk);
        start_cycle(2);repeat(20000)@(negedge sys_clk);
        start_cycle(3);repeat(20000)@(negedge sys_clk);
        wms0_phase_valid=0;wms1_phase_valid=0;
        write_reg(32'h4004,0);write_reg(32'h4104,0);write_reg(32'h5004,0);write_reg(32'h5104,0);
        repeat(10000)@(negedge sys_clk);
        if(frames0!=3||frames1!=3||raw_seen<100)$fatal(1,"frame counts %0d %0d raw %0d",frames0,frames1,raw_seen);
        if(dut.raw0_drops==0||dut.din0_drops!=0||dut.din1_drops!=0)$fatal(1,"RAW backpressure leaked into DILA");
        write_reg(32'h4004,8);write_reg(32'h5004,8);repeat(5)@(negedge sys_clk);
        if(raw0_valid||dila0_valid||dut.din0_valid)$fatal(1,"clear left queued data");
        if(!raw0_idle || !raw1_idle || !dila0_idle || !dila1_idle || raw0_fifo_level!=0 || raw1_fifo_level!=0 || dila0_fifo_level!=0 || dila1_fifo_level!=0)$fatal(1,"exported idle/levels after STOP/CLEAR");
        $display("MEMBER1_ADC_DILA_PASS dual_pin_models raw_independence cfg metadata stop frames=%0d/%0d",frames0,frames1);$finish;
    end
    initial begin #3000000;$fatal(1,"wrapper timeout");end
endmodule
