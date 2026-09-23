`timescale 1ns/1ps
module tb_vapor_clock_integration;
    reg clk=0;always #5 clk=~clk;
    wire rst;wire [31:0] gpif_dq;tri [12:0] ctl;wire pclk,fx3_rst;
    tri1 scl,sda;wire ptb_rx,ptb_tx,hmp_rx,hmp_tx,hmp_de,eps_tx,tfa_hf,tfa_lf,tfa_tx,rd_rx,rd_tx;
    reg eps_rx=1,sync_pulse=0;
    vapor_lidar_top #(.SIMULATION(1),.GPIF_CLK_HZ(50000000),.RAW0_MAX_SAMPLES(32),.RAW1_MAX_SAMPLES(32)) dut(
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
    assign ptb_rx=1'b1;assign hmp_rx=1'b1;assign tfa_hf=1'b1;assign tfa_lf=1'b1;assign rd_rx=1'b1;
    reg [31:0] commands[0:4095];reg [7:0] command_bytes[0:127],frame[0:16383];
    integer cmd_read=0,cmd_write=0,sequence=0,seen_sequence=0,responses=0,frames=0;
    integer space=64,cooldown=0,read_delay=0,tick=0,frame_pos=0,addr_age=0;
    reg [1:0] prev_addr=0;reg [31:0] slave_data=0,pending_data,response_value=0;
    reg [3:0] wf=0,wp=0;reg [2:0] rf=0,rp=0;
    integer x,j,total,payload,seq;reg [31:0] crc;
    reg injection=0;reg [63:0] held_time,previous_time;
    assign ctl[4]=wf[3];assign ctl[6]=wp[3];assign ctl[5]=rf[2];assign ctl[8]=rp[2];
    assign gpif_dq=(!ctl[0]&&!ctl[2])?slave_data:32'bz;
    function [31:0] word_at;input integer a;begin word_at={frame[a+3],frame[a+2],frame[a+1],frame[a]};end endfunction
    function [31:0] crc_byte;input [31:0] a;input [7:0] b;integer z;reg [31:0] v;begin
        v=a^b;for(z=0;z<8;z=z+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;
    end endfunction
    task set_word;input integer a;input [31:0] d;begin
        command_bytes[a]=d[7:0];command_bytes[a+1]=d[15:8];command_bytes[a+2]=d[23:16];command_bytes[a+3]=d[31:24];
    end endtask
    task check_frame;begin
        total=word_at(8);payload=word_at(36);seq=word_at(12);
        if(word_at(0)!==32'h31504c56||frame[4]!=1||frame[7]!=10||total!=44+payload||frame_pos!=((total+3)/4)*4)$fatal(1,"clock recovery VLP header");
        crc=32'hffffffff;for(x=0;x<total-4;x=x+1)crc=crc_byte(crc,frame[x]);
        if(word_at(total-4)!==~crc)$fatal(1,"clock recovery VLP CRC");
        if(frame[6]==2||frame[6]==8'h7f)begin
            if(seq!=sequence||seq<=seen_sequence||word_at(40)!=0)$fatal(1,"clock recovery command seq/status seq=%d current=%d status=%h",seq,sequence,word_at(40));
            if(payload!=4&&payload!=16)$fatal(1,"clock recovery response length");
            if(payload==16)response_value=word_at(52);
            seen_sequence=seq;responses=responses+1;
        end
        frames=frames+1;frame_pos=0;
    end endtask
    always @(posedge pclk)if(fx3_rst)begin
        tick=tick+1;
        if({ctl[11],ctl[12]}!==prev_addr)begin addr_age=0;prev_addr={ctl[11],ctl[12]};end else addr_age=addr_age+1;
        if(!ctl[7]&&ctl[1])$fatal(1,"standalone PKTEND");
        if(!ctl[1]&&!ctl[3])$fatal(1,"GPIF bus contention");
        if(!ctl[0]&&!ctl[1])begin
            if(!ctl[2]||prev_addr!=0||addr_age<3||space==0||cooldown!=0)$fatal(1,"clock GPIF write boundary");
            for(j=0;j<4;j=j+1)frame[frame_pos+j]=gpif_dq[j*8+:8];frame_pos=frame_pos+4;space=space-1;
            if(!ctl[7])begin check_frame;space=0;cooldown=5;end
        end
        if(!ctl[0]&&!ctl[3])begin
            if(ctl[2]||prev_addr!=3||addr_age<3||cmd_read>=cmd_write||read_delay!=0)$fatal(1,"clock GPIF read boundary");
            pending_data=commands[cmd_read];cmd_read=cmd_read+1;read_delay=3;
        end
        if(read_delay!=0)begin read_delay=read_delay-1;if(read_delay==0)slave_data<=#7 pending_data;end
        if(cooldown!=0)begin cooldown=cooldown-1;if(cooldown==0)space=64;end
        else if(tick%397==0)space=64;
        wf<=#8 {wf[2:0],space>0&&cooldown==0};wp<=#8 {wp[2:0],space>8&&cooldown==0};
        rf<=#8 {rf[1:0],cmd_read<cmd_write};rp<=#8 {rp[1:0],cmd_write-cmd_read>11};
    end
    task command;input write;input [31:0] address,data;integer n,b,pbytes,bytes;reg [31:0] c;begin
        @(negedge clk);sequence=sequence+1;pbytes=write?12:8;bytes=44+pbytes;
        for(n=0;n<128;n=n+1)command_bytes[n]=0;
        set_word(0,32'h31504c56);set_word(4,32'h0a010001);set_word(8,bytes);set_word(12,sequence);
        set_word(16,write?32'h00030001:32'h00020001);set_word(36,pbytes);
        set_word(40,address);set_word(44,1);if(write)set_word(48,data);
        c=32'hffffffff;for(n=0;n<bytes-4;n=n+1)c=crc_byte(c,command_bytes[n]);set_word(bytes-4,~c);
        for(n=0;n<bytes;n=n+4)begin commands[cmd_write]={command_bytes[n+3],command_bytes[n+2],command_bytes[n+1],command_bytes[n]};cmd_write=cmd_write+1;end
        wait(seen_sequence==sequence);@(negedge clk);
    end endtask
    task read_expect;input [31:0] address,value;begin
        command(0,address,0);if(response_value!==value)$fatal(1,"GPIF read address=%h got=%h expected=%h",address,response_value,value);
    end endtask
    task pps;begin @(negedge clk);sync_pulse=1;repeat(8)@(negedge clk);sync_pulse=0;repeat(8)@(negedge clk);end endtask
    task lose_clock;input integer fault_number;begin
        wait(dut.gpif_idle&&!dut.packet_busy&&dut.tx_level==0&&frame_pos==0);repeat(20)@(negedge clk);
        wait(dut.gpif_idle&&!dut.packet_busy&&dut.tx_level==0&&frame_pos==0);
        @(negedge clk);injection=1;held_time=dut.timestamp_now;
        force dut.u_clock.clock_locked=1'b0;
        force dut.u_clock.sys_clk=1'b0;
        force dut.u_clock.gpif_clk=1'b0;
        #1;
        if(dut.rst_operational_n||dut.rst_gpif_power_n||dut.rst_control_n||dut.rst_adc_n||dut.rst_wms_n||dut.rst_sensors_n||dut.rst_motor_n||dut.rst_stream_n||dut.rst_transport_n)
            $fatal(1,"clock loss did not asynchronously reset operational groups");
        if(!dut.rst_power_n)$fatal(1,"clock loss erased persistent domain");
        repeat(40)@(negedge clk);
        if(dut.timestamp_now!==held_time||dut.clock_fault_ref!=fault_number)$fatal(1,"stopped clock retention/reference count ticks=%d held=%d faults=%d",dut.timestamp_now,held_time,dut.clock_fault_ref);
        release dut.u_clock.sys_clk;release dut.u_clock.gpif_clk;
        repeat(32)@(negedge clk);
        if(dut.timestamp_now!==held_time||dut.time_sync_valid||!(dut.time_errors&32'h20)||dut.clock_fault_count!=fault_number||!dut.reset_reason[3])
            $fatal(1,"resumed unlocked clock diagnostics time=%d held=%d sync=%b terr=%h count=%d reason=%h",dut.timestamp_now,held_time,dut.time_sync_valid,dut.time_errors,dut.clock_fault_count,dut.reset_reason);
        release dut.u_clock.clock_locked;
        wait(dut.rst_operational_n&&dut.rst_gpif_power_n&&dut.rst_control_n);repeat(80)@(negedge clk);injection=0;
        if(dut.timestamp_now<=held_time||!dut.rst_adc_n||!dut.rst_wms_n||!dut.rst_sensors_n||!dut.rst_motor_n||!dut.rst_stream_n||!dut.rst_transport_n)
            $fatal(1,"clock relock failed operational recovery");
        read_expect(32'h0124,fault_number);read_expect(32'h010c,32'h20);read_expect(32'h003c,9);
        read_expect(32'h7018,512);read_expect(32'h0004,0);read_expect(32'h100c,32'h20);
        command(0,32'h1010,0);if(response_value<held_time[31:0])$fatal(1,"GPIF time read rewound");
        command(1,32'h010c,32'h20);read_expect(32'h010c,0);read_expect(32'h0124,fault_number);
        command(1,32'h003c,8);read_expect(32'h003c,1);
        command(1,32'h100c,32'h20);read_expect(32'h100c,0);
        pps();if(!dut.time_sync_valid)$fatal(1,"PPS did not restore sync validity");
        $display("TOP_CLOCK_LOSS_RECOVERY_PASS faults=%0d responses=%0d persistent_ticks=%0d",fault_number,responses,dut.timestamp_now);
    end endtask
    initial begin
        wait(dut.rst_operational_n&&dut.rst_power_n&&fx3_rst);repeat(100)@(negedge clk);
        read_expect(32'h0124,0);command(1,32'h010c,32'h20);command(1,32'h100c,32'h20);
        command(1,32'h0004,1);command(1,32'h7018,512);pps();
        if(!dut.time_sync_valid)$fatal(1,"initial PPS missing");
        previous_time=dut.timestamp_now;lose_clock(1);
        command(1,32'h0004,1);lose_clock(2);
        if(dut.timestamp_now<=previous_time||dut.clock_fault_ref!=2||dut.protocol_errors!=0||dut.crc_errors!=0)$fatal(1,"final clock integration state");
        $display("tb_vapor_clock_integration_PASS faults=2 responses=%0d CRC_frames=%0d operational_resets=7 stopped_clocks=1 persistent_time=1 GPIF_W1C=1",responses,frames);$finish;
    end
    initial begin #5000000;$fatal(1,"clock integration timeout seq=%d seen=%d read=%d write=%d resets=%b count=%d",sequence,seen_sequence,cmd_read,cmd_write,dut.rst_control_n,dut.clock_fault_count);end
endmodule
