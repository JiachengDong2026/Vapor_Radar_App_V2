`timescale 1ns/1ps
module tb_vapor_sensor_integration #(parameter integer GPIF_TEST_HZ=50000000);
    reg clk=0;always #5 clk=~clk;
    wire rst;wire [31:0] gpif_dq;tri [12:0] ctl;wire pclk,fx3_rst;
    tri1 scl,sda;wire ptb_rx,ptb_tx,hmp_rx,hmp_tx,hmp_de,eps_tx,tfa_hf,tfa_lf,tfa_tx;
    reg eps_rx=1,sync_pulse=0;
    vapor_lidar_top #(.SIMULATION(1),.GPIF_CLK_HZ(GPIF_TEST_HZ),.RAW0_MAX_SAMPLES(32),.RAW1_MAX_SAMPLES(32)) dut(
        .CLK_FPGA_25MHZ(clk),.FPGA_GPIF_DQ(gpif_dq),.FPGA_GPIF_CTL(ctl),.FPGA_GPIF_INTN(1'b1),
        .FPGA_GPIF_PCLK(pclk),.CYUSB_RSTN(fx3_rst),
        .FPGA_RS232A_RXD(ptb_rx),.FPGA_RS232A_TXD(ptb_tx),
        .FPGA_RS485_RXD_L(hmp_rx),.FPGA_RS485_TXD_L(hmp_tx),.FPGA_RS485_DERE_L(hmp_de),
        .FPGA_RS232B_RXD(eps_rx),.FPGA_RS232B_TXD(eps_tx),.FPGA_RS422_RXD_L(1'b1),
        .FPGA_UART_RXD_L(tfa_hf),.TFA_LF_RXD(tfa_lf),.FPGA_UART_TXD_L(tfa_tx),
        .SYNC_IN(sync_pulse),.BMP390_INT(1'b0),.I2C_SCL(scl),.I2C_SDA(sda),
        .dac_sdo(2'd0),.ADC_AD4630_BUSY(1'b0),.ADC_AD4630_SDO(8'd0),
        .ADC_ADC3660_DA5(1'b0),.ADC_ADC3660_DA6(1'b0),.ADC_ADC3660_DB5(1'b0),.ADC_ADC3660_DB6(1'b0),
        .ADC_ADC3660_DCLK(1'b0),.ADC_ADC3660_FCLK(1'b0));
    assign rst=dut.rst_sensors_n;
    wire [31:0] ptb_polls,ptb_bp;wire form_seen,reset_seen;
    ptb210_model #(.SYS_CLK_HZ(100000000),.REPEAT_VALID(1))ptb(
        .sys_clk(clk),.rst_sys_n(rst),.host_txd(ptb_tx),.host_rxd(ptb_rx),
        .poll_count(ptb_polls),.bp_count(ptb_bp),.form_seen(form_seen),.reset_seen(reset_seen));
    wire [31:0] bus_requests,ai8_writes,ai8_verifies,hmp_requests,hmp_writes,pressure_bits;
    wire [15:0] ai8_sp;
    ai8_hmp_bus_bfm #(.BAUD_HZ(19200),.PARITY_MODE(0),.STOP_BITS(1)) shared_bus(
        .rst_n(rst),.master_txd(hmp_tx),.master_de(hmp_de),.slave_txd(hmp_rx),
        .fault_mode(4'd0),.hmp_fault(4'd0),.request_count(bus_requests),
        .write_count(ai8_writes),.verify_count(ai8_verifies),.hmp_count(hmp_requests),
        .hmp_write_count(hmp_writes),.pressure_bits(pressure_bits),.current_sp(ai8_sp));
    wire [31:0] bt,bs,st,ss;wire [7:0] bc,sc;
    i2c_sensor_model #(.ADDRESS(7'h76),.IS_BMP(1),.NS_PER_LOGICAL_MS(1000000))bmp(
        .scl(scl),.sda(sda),.rst_n(rst),.inject_nack(1'b0),.inject_bad_crc(1'b0),.transactions(bt),.measurements(bs),.last_command(bc));
    i2c_sensor_model #(.NS_PER_LOGICAL_MS(1000000))sht(
        .scl(scl),.sda(sda),.rst_n(rst),.inject_nack(1'b0),.inject_bad_crc(1'b0),.transactions(st),.measurements(ss),.last_command(sc));
    tfa1500_model tfa(.hf_rxd(tfa_hf),.lf_rxd(tfa_lf));
    reg run_sources=0;
    initial begin wait(run_sources);forever begin tfa.high_frame(209,0);#900000;end end
    reg [7:0] eps_frame[0:109];integer e,n;
    reg [7:0] h;reg [15:0] c;
    function [7:0] crc8;input [7:0] a,b;integer j;reg [7:0] v;begin v=a^b;for(j=0;j<8;j=j+1)v=v[0]?(v>>1)^8'h8c:v>>1;crc8=v;end endfunction
    function [15:0] crc16;input [15:0] a;input [7:0] b;integer j;reg [15:0] v;begin v=a^{b,8'd0};for(j=0;j<8;j=j+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc16=v;end endfunction
    task serial;input [7:0] b;integer j;begin eps_rx=0;#1085;for(j=0;j<8;j=j+1)begin eps_rx=b[j];#1085;end eps_rx=1;#1085;end endtask
    initial begin
        for(e=0;e<110;e=e+1)eps_frame[e]=0;
        eps_frame[0]='hfc;eps_frame[1]='h50;eps_frame[2]=102;eps_frame[3]=7;eps_frame[9]=8;
        {eps_frame[16],eps_frame[15],eps_frame[14],eps_frame[13]}=32'd1700000000;
        {eps_frame[20],eps_frame[19],eps_frame[18],eps_frame[17]}=32'd123456;
        h=0;for(e=0;e<4;e=e+1)h=crc8(h,eps_frame[e]);eps_frame[4]=h;
        c=0;for(e=7;e<109;e=e+1)c=crc16(c,eps_frame[e]);eps_frame[5]=c[15:8];eps_frame[6]=c[7:0];eps_frame[109]='hfd;
        wait(run_sources);forever begin for(n=0;n<110;n=n+1)serial(eps_frame[n]);#2800000;end
    end

    // Independent GPIF model: delayed flags, two-edge DQ latency, finite room.
    localparam CMD_WORDS=182;
    reg [31:0] commands[0:CMD_WORDS-1];reg [31:0] slave_dq=0,pending_read;
    reg [3:0] wf=0,wp=0;reg [2:0] rf=0,rp=0;
    assign ctl[4]=wf[3];assign ctl[6]=wp[3];assign ctl[5]=rf[2];assign ctl[8]=rp[2];
    assign gpif_dq=(!ctl[0]&&!ctl[2])?slave_dq:32'bz;
    integer cmd_pos=0,rx_delay=0,space=64,commit_wait=0,tick=0,addr_age=0;
    reg [1:0] prev_addr=0;reg host_stall=0;integer stalled_cycles=0,near_writes=0;
    reg [7:0] frame[0:16383];integer frame_pos=0,total_bytes=0,frames=0,responses=0;
    integer counts[0:6];integer k,j,x,lane,slot,nbytes,nb,fi,bi;
    reg [31:0] calc_crc,got_crc;
    // Per-lane FIFO-boundary scoreboard checks exact payload and metadata through
    // hub, arbiter, packetizer, dual-clock FIFO and physical GPIF pins.
    reg [31:0] expected_data[0:28671];reg [3:0] expected_keep[0:28671];
    reg [31:0] expected_flags[0:7167],expected_cycle[0:7167];
    reg [63:0] expected_time[0:7167];reg [15:0] expected_mid[0:7167];
    integer beat_write[0:6],beat_read[0:6],frame_write[0:6],frame_read[0:6];
    integer frame_beats[0:7167],building_beats[0:6];
    integer gnss_tags=0,pps_events=0,tagged_pps=0,pps_output=0;
    time last_gpif_edge=0;
    function [31:0] u32;input integer off;begin u32={frame[off+3],frame[off+2],frame[off+1],frame[off]};end endfunction
    function [31:0] crc32byte;input [31:0] a;input [7:0] b;integer z;reg [31:0] v;begin
        v=a^b;for(z=0;z<8;z=z+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc32byte=v;
    end endfunction
    task validate_frame;begin
        if(u32(0)!=32'h31504c56||frame[4]!=1||frame[5]!=0||frame[7]!=10)$fatal(1,"VLP header");
        total_bytes=u32(8);nbytes=u32(36);
        if(total_bytes!=44+nbytes||frame_pos!=((total_bytes+3)/4)*4)$fatal(1,"VLP length bytes=%d pos=%d payload=%d",total_bytes,frame_pos,nbytes);
        calc_crc=32'hffffffff;for(x=0;x<total_bytes-4;x=x+1)calc_crc=crc32byte(calc_crc,frame[x]);
        got_crc=u32(total_bytes-4);if(got_crc!==~calc_crc)$fatal(1,"VLP CRC frame=%d source=%h got=%h exp=%h",frames,u32(16),got_crc,~calc_crc);
        for(x=total_bytes;x<frame_pos;x=x+1)if(frame[x]!=0)$fatal(1,"VLP padding");
        if(frame[6]==2)begin
            if(u32(16)!=32'h00030001||nbytes!=4||u32(40)!=0||u32(12)!=responses+1)$fatal(1,"configuration command response seq=%d status=%h",u32(12),u32(40));
            responses=responses+1;
        end else if(frame[6]==16)begin
            lane={frame[17],frame[16]}-16'h40;
            if(lane<0||lane>6)$fatal(1,"unexpected sensor source %h",u32(16));
            if(frame_read[lane]>=frame_write[lane])$fatal(1,"sensor frame not present at source boundary");
            fi=lane*1024+(frame_read[lane]%1024);
            if({frame[19],frame[18]}!==expected_mid[fi]||u32(20)!==expected_flags[fi]||
                {u32(28),u32(24)}!==expected_time[fi]||u32(32)!==expected_cycle[fi])$fatal(1,"sensor metadata lane=%d",lane);
            nb=0;
            for(bi=0;bi<frame_beats[fi];bi=bi+1)begin
                slot=lane*4096+(beat_read[lane]%4096);
                for(j=0;j<4;j=j+1)if(expected_keep[slot][j])begin
                    if(frame[40+nb]!==expected_data[slot][j*8+:8])$fatal(1,"sensor payload lane=%d byte=%d",lane,nb);
                    nb=nb+1;
                end
                beat_read[lane]=beat_read[lane]+1;
            end
            if(nb!=nbytes)$fatal(1,"sensor payload length");
            if(lane==2)begin
                if(nbytes!=110)$fatal(1,"EPS raw length");
                for(j=0;j<110;j=j+1)if(frame[40+j]!==eps_frame[j])$fatal(1,"EPS raw physical byte %d",j);
            end
            if(lane==5&&(nbytes!=12||u32(48)!=2090))$fatal(1,"TFA physical model value mismatch");
            if(lane==6)begin
                if(nbytes!=108||u32(40)!=32'h000d0002||u32(48)!=244||u32(56)!=500||u32(64)!=450||
                    u32(72)!=12800||u32(80)!=21||u32(88)!=1||u32(96)!=32'h301)
                    $fatal(1,"AI8 physical raw/schema mismatch");
            end
            counts[lane]=counts[lane]+1;frame_read[lane]=frame_read[lane]+1;
        end else if(frame[6]==8'h11&&u32(16)==32'h12010002)begin
            if(nbytes!=32||u32(40)!=1||u32(44)==0||u32(64)!=1||{u32(60),u32(56)}!==64'd1700000000123456)
                $fatal(1,"PPS/GNSS VLP event payload");
            pps_output=pps_output+1;
        end else if(frame[6]!=8'h11&&frame[6]!=8'h12)$fatal(1,"unexpected VLP type %h",frame[6]);
        frames=frames+1;frame_pos=0;
    end endtask
    always @(posedge clk)if(rst)begin
        if(dut.gnss_time_tag_valid)begin
            gnss_tags=gnss_tags+1;
            if(dut.gnss_time_tag!==64'd1700000000123456)$fatal(1,"GNSS UTC conversion");
        end
        if(dut.sync_event_pulse)begin
            pps_events=pps_events+1;
            if(dut.sync_event_gnss_valid)begin tagged_pps=tagged_pps+1;
                if(dut.sync_event_gnss_tag!==64'd1700000000123456)$fatal(1,"PPS GNSS association");end
        end
        for(k=0;k<7;k=k+1)if(dut.sensor_valid[k]&&dut.sensor_ready[k])begin
            if(beat_write[k]-beat_read[k]>=4096||frame_write[k]-frame_read[k]>=1024)$fatal(1,"scoreboard capacity");
            slot=k*4096+(beat_write[k]%4096);
            expected_data[slot]=dut.sensor_data[k*32+:32];expected_keep[slot]=dut.sensor_keep[k*4+:4];
            fi=k*1024+(frame_write[k]%1024);
            if(dut.sensor_sof[k])begin
                if(building_beats[k]!=0)$fatal(1,"nested source frame");
                expected_flags[fi]=dut.sensor_flags[k*32+:32];expected_time[fi]=dut.sensor_timestamp[k*64+:64];
                expected_cycle[fi]=dut.sensor_cycle_id[k*32+:32];expected_mid[fi]=dut.sensor_msg_id[k*16+:16];
            end
            building_beats[k]=building_beats[k]+1;beat_write[k]=beat_write[k]+1;
            if(dut.sensor_last[k])begin frame_beats[fi]=building_beats[k];building_beats[k]=0;frame_write[k]=frame_write[k]+1;end
        end
    end
    always @(posedge pclk)begin
        if(last_gpif_edge!=0&&$time-last_gpif_edge!=1000000000/GPIF_TEST_HZ)$fatal(1,"GPIF physical clock rate mismatch");
        last_gpif_edge=$time;
        if(host_stall&&space==0&&tick>1000&&!dut.link_ready)$fatal(1,"FIFO full incorrectly clears firmware readiness");
        if(!fx3_rst)begin wf<=0;wp<=0;rf<=0;rp<=0;end
        else begin
            tick=tick+1;
            if({ctl[11],ctl[12]}!==prev_addr)begin addr_age=0;prev_addr={ctl[11],ctl[12]};end else addr_age=addr_age+1;
            if(!ctl[7]&&ctl[1])$fatal(1,"standalone PKTEND");
            if(!ctl[1]&&!ctl[3])$fatal(1,"GPIF read/write collision");
            if(!ctl[0]&&!ctl[1])begin
                if(!ctl[2]||prev_addr!=0||addr_age<3||space==0||commit_wait!=0)$fatal(1,"GPIF write timing/overflow");
                for(x=0;x<4;x=x+1)frame[frame_pos+x]=gpif_dq[x*8+:8];frame_pos=frame_pos+4;
                space=space-1;if(!ctl[6])near_writes=near_writes+1;
                if(!ctl[7])begin validate_frame;space=0;commit_wait=5;end
            end
            if(!ctl[0]&&!ctl[3])begin
                if(ctl[2]||prev_addr!=3||addr_age<3||cmd_pos>=CMD_WORDS||rx_delay!=0)$fatal(1,"GPIF read timing/underflow");
                pending_read=commands[cmd_pos];cmd_pos=cmd_pos+1;rx_delay=3;
            end
            if(rx_delay!=0)begin rx_delay=rx_delay-1;if(rx_delay==0)slave_dq<=#7 pending_read;end
            if(commit_wait!=0)begin commit_wait=commit_wait-1;if(commit_wait==0&&!host_stall)space=64;end
            else if(!host_stall&&tick%397==0&&space<64)space=64;
            if(space==0)stalled_cycles=stalled_cycles+1;
            wf<=#8 {wf[2:0],(space>0&&commit_wait==0)};wp<=#8 {wp[2:0],(space>8&&commit_wait==0)};
            rf<=#8 {rf[1:0],(cmd_pos<CMD_WORDS)};rp<=#8 {rp[1:0],(cmd_pos<CMD_WORDS-11)};
        end
    end
    initial begin
        $readmemh("sensor_commands.hex",commands);
        for(k=0;k<7;k=k+1)begin counts[k]=0;beat_write[k]=0;beat_read[k]=0;frame_write[k]=0;frame_read[k]=0;building_beats[k]=0;end
        wait(responses==13);$display("TOP_SENSOR_CONFIG_GPIF_PASS");
        #20000000;run_sources=1;
        wait(gnss_tags>=1);#1000;sync_pulse=1;#100;sync_pulse=0;
        wait(counts[0]>=2&&counts[1]>=2&&counts[2]>=2&&counts[3]>=2&&counts[4]>=2&&counts[5]>=2&&counts[6]>=2);
        $display("TOP_SEVEN_FIRST_FRAMES_PASS time=%t",$time);
        host_stall=1;#120000000;host_stall=0;
        #20000000;sync_pulse=1;#100;sync_pulse=0;wait(pps_output>=2);#1000;
        if(gnss_tags==0||tagged_pps<2||dut.device_online!=7'h7f||stalled_cycles==0)$fatal(1,"missing concurrency/PPS/stall coverage");
        wait(counts[0]>=3&&counts[1]>=3&&counts[2]>=3&&counts[3]>=3&&counts[4]>=3&&counts[5]>=3&&counts[6]>=3);
        if(hmp_requests<3 || bus_requests-hmp_requests<21 || ai8_writes!=0 || hmp_writes!=0 || ai8_sp!=500)$fatal(1,"shared bus progress or unrequested write");
        $display("SHARED_RS485_PROGRESS_PASS hmp=%0d ai8=%0d writes=%0d/%0d",hmp_requests,bus_requests-hmp_requests,ai8_writes,hmp_writes);
        for(k=0;k<7;k=k+1)if(counts[k]<3)$fatal(1,"sensor failed recovery lane=%d count=%d",k,counts[k]);
        if(dut.protocol_errors!=0||dut.crc_errors!=0||dut.packet_errors!=0)$fatal(1,"top protocol counters");
        $display("tb_vapor_sensor_integration_PASS frames=%0d counts=%0d,%0d,%0d,%0d,%0d,%0d,%0d CRC=all tags=%0d taggedPPS=%0d stallCycles=%0d nearWrites=%0d",frames,counts[0],counts[1],counts[2],counts[3],counts[4],counts[5],counts[6],gnss_tags,tagged_pps,stalled_cycles,near_writes);$finish;
    end
    initial begin #1500000000;$fatal(1,"integration timeout cmd=%d resp=%d frames=%d lanes=%d,%d,%d,%d,%d,%d,%d",cmd_pos,responses,frames,counts[0],counts[1],counts[2],counts[3],counts[4],counts[5],counts[6]);end
endmodule
