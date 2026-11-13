`timescale 1ns/1ps
module tb_gnss_motor_top;
    reg CLK_FPGA_25MHZ=0;
    wire [31:0] FPGA_GPIF_DQ;
    wire [12:0] FPGA_GPIF_CTL;
    reg FPGA_GPIF_INTN=1;
    wire FPGA_GPIF_PCLK;
    wire CYUSB_RSTN;
    reg FPGA_RS232A_RXD=1;
    reg FPGA_RS232B_RXD=1;
    reg FPGA_RS485_RXD_L=1;
    reg FPGA_RS422_RXD_L=1;
    reg FPGA_UART_RXD_L=1;
    reg TFA_LF_RXD=1;
    wire FPGA_RS232A_TXD;
    wire FPGA_RS485_TXD_L;
    wire FPGA_RS485_DERE_L;
    wire FPGA_RS422_TXD_L;
    wire FPGA_UART_TXD_L;
    wire FPGA_UART_EN_L;
    wire RS232_PHY_FORCEON;
    wire FPGA_RS232B_TXD;
    reg SYNC_IN=0;
    reg BMP390_INT=0;
    tri1 I2C_SCL;
    tri1 I2C_SDA;
    wire MOTOR_PUL;
    wire MOTOR_DIR;
    wire MOTOR_ENA;
    wire [1:0] dac_sclk;
    wire [1:0] dac_sync_n;
    wire [1:0] dac_sdin;
    wire [1:0] dac_rst_n;
    wire [1:0] dac_clr_n;
    wire [1:0] dac_ldac_n;
    reg [1:0] dac_sdo=0;
    wire ADC_AD4630_SDI;
    wire ADC_AD4630_RSTN;
    wire ADC_AD4630_CNV;
    wire ADC_AD4630_CSN;
    wire ADC_AD4630_SCK;
    reg ADC_AD4630_BUSY=0;
    reg [7:0] ADC_AD4630_SDO=0;
    reg ADC_ADC3660_DA5=0;
    reg ADC_ADC3660_DA6=0;
    reg ADC_ADC3660_DB5=0;
    reg ADC_ADC3660_DB6=0;
    reg ADC_ADC3660_DCLK=0;
    reg ADC_ADC3660_FCLK=0;
    wire ADC_ADC3660_DCLKIN;
    wire ADC_ADC3660_CLKP;
    wire ADC_ADC3660_CLKN;
    wire ADC_ADC3660_SEN;
    wire ADC_ADC3660_SCLK;
    wire ADC_ADC3660_RST;
    wire ADC_ADC3660_SYNC;
    wire ADC_ADC3660_SDIO;
    `include "gm_top_sizes.vh"
    wire [1:0] lc_lines;
    integer available_words=PHASE_WORDS;
    vapor_lidar_top #(.SIMULATION(1),.GPIF_CLK_HZ(50000000),.RAW0_MAX_SAMPLES(64),.RAW1_MAX_SAMPLES(64)) dut(
        .HC2A_UART_RXD(1'b1),.CLK_FPGA_25MHZ(CLK_FPGA_25MHZ),
        .FPGA_GPIF_DQ(FPGA_GPIF_DQ),
        .FPGA_GPIF_CTL(FPGA_GPIF_CTL),
        .FPGA_GPIF_INTN(FPGA_GPIF_INTN),
        .FPGA_GPIF_PCLK(FPGA_GPIF_PCLK),
        .CYUSB_RSTN(CYUSB_RSTN),
        .FPGA_RS232A_RXD(FPGA_RS232A_RXD),
        .FPGA_RS232B_RXD(FPGA_RS232B_RXD),
        .FPGA_RS485_RXD_L(FPGA_RS485_RXD_L),
        .FPGA_RS422_RXD_L(FPGA_RS422_RXD_L),
        .FPGA_UART_RXD_L(FPGA_UART_RXD_L),
        .TFA_LF_RXD(TFA_LF_RXD),
        .LC_UART_RXD(lc_lines),.LC_UART_TXD(lc_lines),
        .FPGA_RS232A_TXD(FPGA_RS232A_TXD),
        .FPGA_RS485_TXD_L(FPGA_RS485_TXD_L),
        .FPGA_RS485_DERE_L(FPGA_RS485_DERE_L),
        .FPGA_RS422_TXD_L(FPGA_RS422_TXD_L),
        .FPGA_UART_TXD_L(FPGA_UART_TXD_L),
        .FPGA_UART_EN_L(FPGA_UART_EN_L),
        .RS232_PHY_FORCEON(RS232_PHY_FORCEON),
        .FPGA_RS232B_TXD(FPGA_RS232B_TXD),
        .SYNC_IN(SYNC_IN),
        .BMP390_INT(BMP390_INT),
        .I2C_SCL(I2C_SCL),
        .I2C_SDA(I2C_SDA),
        .MOTOR_PUL(MOTOR_PUL),
        .MOTOR_DIR(MOTOR_DIR),
        .MOTOR_ENA(MOTOR_ENA),
        .dac_sclk(dac_sclk),
        .dac_sync_n(dac_sync_n),
        .dac_sdin(dac_sdin),
        .dac_rst_n(dac_rst_n),
        .dac_clr_n(dac_clr_n),
        .dac_ldac_n(dac_ldac_n),
        .dac_sdo(dac_sdo),
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
        .ADC_ADC3660_SDIO(ADC_ADC3660_SDIO)
    );
    // Shorten wall-clock simulation only; the independent real SYS100 test
    // verifies the unscaled motor core. Production parameters are unchanged.
    defparam dut.u_motor.SYS_CLK_HZ=1000000;
    defparam dut.u_time.SYS_CLK_HZ=100000;
    integer motor_rises=0;
    always @(posedge MOTOR_PUL)motor_rises=motor_rises+1;
    task pps;input integer period;begin
        if(dut.sync_seq!=0)wait(dut.timestamp_now>=dut.sync_event_tick+period-2);
        @(negedge CLK_FPGA_25MHZ);SYNC_IN=1;
        repeat(5)@(negedge CLK_FPGA_25MHZ);SYNC_IN=0;
        repeat(2)@(negedge CLK_FPGA_25MHZ);
    end endtask
    always #5 CLK_FPGA_25MHZ=~CLK_FPGA_25MHZ;
    always #10 ADC_ADC3660_DCLK=~ADC_ADC3660_DCLK;
    reg [31:0] commands[0:COMMAND_WORDS-1];
    reg [7:0] expected[0:RESPONSES*64-1],masks[0:RESPONSES*64-1],lengths[0:RESPONSES-1];
    reg [15:0] sources[0:RESPONSES-1];
    reg [7:0] frame[0:8300];reg [RESPONSES-1:0] seen=0;
    reg [31:0] slave_data=0,pending_data;
    reg [3:0] ready_pipe=0,partial_pipe=0;reg [2:0] rx_pipe=0;
    integer input_word=0,read_delay=0,byte_count=0,got=0,frame_count=0,space=256,cooldown=0,tick=0;
    integer i,seq,total,payload;reg [31:0] crc;
    reg [63:0] before_reset;
    assign FPGA_GPIF_CTL[4]=ready_pipe[3];
    assign FPGA_GPIF_CTL[6]=partial_pipe[3];
    assign FPGA_GPIF_CTL[5]=rx_pipe[2];
    assign FPGA_GPIF_CTL[8]=rx_pipe[2];
    assign FPGA_GPIF_DQ=!FPGA_GPIF_CTL[2] ? slave_data : 32'bz;
    function [31:0] word_at;
        input integer offset;
        begin word_at={frame[offset+3],frame[offset+2],frame[offset+1],frame[offset]};end
    endfunction
    function [31:0] crc_byte;
        input [31:0] c;input [7:0] b;integer k;reg [31:0] temp;
        begin temp=c^b;for(k=0;k<8;k=k+1)temp=temp[0]?((temp>>1)^32'hedb88320):(temp>>1);crc_byte=temp;end
    endfunction
    task check_frame;begin
        frame_count=frame_count+1;total=word_at(8);payload=word_at(36);seq=word_at(12);
        if(word_at(0)!==32'h31504c56 || frame[4]!=1 || frame[7]!=10 || total!=44+payload || (total+3)/4*4!=byte_count)
            $fatal(1,"top VLP header/frame boundary count=%0d total=%0d",byte_count,total);
        crc=32'hffffffff;
        for(i=0;i<total-4;i=i+1)crc=crc_byte(crc,frame[i]);
        if((crc^32'hffffffff)!==word_at(total-4))$fatal(1,"top VLP CRC");
        for(i=total;i<byte_count;i=i+1)if(frame[i]!=0)$fatal(1,"top pad");
        if(frame[6]==2 || frame[6]==8'h7f)begin
            if(seq<1 || seq>RESPONSES || seen[seq-1])$fatal(1,"top response seq %0d",seq);
            if(payload!=lengths[seq-1])$fatal(1,"top response length seq=%0d got=%0d expected=%0d status=%0d",seq,payload,lengths[seq-1],word_at(40));
            for(i=0;i<payload;i=i+1)
                if((frame[40+i]&masks[(seq-1)*64+i])!==(expected[(seq-1)*64+i]&masks[(seq-1)*64+i]))
                    $fatal(1,"top response seq=%0d byte=%0d got=%h expected=%h",seq,i,frame[40+i],expected[(seq-1)*64+i]);
            if({frame[17],frame[16]}!==sources[seq-1])$fatal(1,"LC response source");
            seen[seq-1]=1;got=got+1;
        end
        byte_count=0;
    end endtask
    always @(posedge FPGA_GPIF_PCLK)if(dut.rst_power_n)begin
        tick=tick+1;
        if(!FPGA_GPIF_CTL[0] && !FPGA_GPIF_CTL[1])begin
            if(space==0 || cooldown!=0)$fatal(1,"top FX3 write full");
            for(i=0;i<4;i=i+1)frame[byte_count+i]=FPGA_GPIF_DQ>>(i*8);
            byte_count=byte_count+4;space=space-1;
            if(!FPGA_GPIF_CTL[7])begin check_frame;space=0;cooldown=5;end
        end
        if(!FPGA_GPIF_CTL[0] && !FPGA_GPIF_CTL[3])begin
            if(input_word>=available_words || read_delay!=0)$fatal(1,"top FX3 read empty");
            pending_data=commands[input_word];input_word=input_word+1;read_delay=3;
        end
        if(read_delay!=0)begin read_delay=read_delay-1;if(read_delay==0)slave_data<=#2 pending_data;end
        if(cooldown!=0)begin cooldown=cooldown-1;if(cooldown==0)space=256;end
        else if(tick%500==0)space=256;
        ready_pipe<={ready_pipe[2:0],space>0 && cooldown==0};
        partial_pipe<={partial_pipe[2:0],space>8 && cooldown==0};
        rx_pipe<={rx_pipe[1:0],input_word<available_words};
    end
    initial begin
        $readmemh("gm_top_commands.hex",commands);
        // Dual AD4630: vector 46 writes ADC1 rate (0x4110), now READ_ONLY=6.
        $readmemh("gm_top_responses.hex",expected);
        for(i=0;i<RESPONSES*64;i=i+1)masks[i]=255;
        $readmemh("gm_top_response_sources.hex",sources);
        $readmemh("gm_top_response_lengths.hex",lengths);
        wait(dut.rst_motor_n);#100;
        if(!MOTOR_ENA || MOTOR_PUL)$fatal(1,"top boot EN high disable");
        wait(got==PHASE_RESPONSES);
        wait(!dut.motor_busy);#100;
        if(motor_rises!=3 || MOTOR_ENA || dut.motor_position!=3)$fatal(1,"top finite USB motor move/hold");
        // Feed the decoded UTC interface; UART decoding has separate FDILink
        // CRC tests. PPS itself enters through the real top-level SYNC_IN port.
        force dut.gnss_time_tag=64'd1700000000123456;
        force dut.gnss_time_tag_valid=1'b1;
        pps(0);pps(100100);pps(100100);pps(100100);
        if(dut.sync_event_gnss_valid)$fatal(1,"top unverified UTC association");
        available_words=PHASE2_WORDS;
        wait(got==PHASE2_RESPONSES);wait(!dut.motor_busy);#100;
        if(motor_rises!=5 || !MOTOR_DIR || MOTOR_ENA)$fatal(1,"top reverse/hold");
        // Command traffic can take longer than one scaled second. Schedule
        // the next PPS relative to current time and preserve the exact period.
        pps(100100);
        if(!dut.sync_event_gnss_valid || dut.sync_event_gnss_tag!=64'd1700000001000000)
            $fatal(1,"top UTC epoch advance");
        available_words=COMMAND_WORDS;
        wait(got==RESPONSES);#1000;
        if(!MOTOR_ENA || MOTOR_PUL || dut.motor_busy)$fatal(1,"top final disable");
        if(dut.module_present[22:21]!==2'b11)$fatal(1,"retained LC pages");
        release dut.gnss_time_tag;release dut.gnss_time_tag_valid;
        $display("tb_gnss_motor_top_PASS responses=%0d USB_VLP_CRC_register_errors_motor_bidirectional_PPS_snapshot_UTC_LC_retained",got);$finish;
    end
    initial begin #15000000;$fatal(1,"top timeout responses=%0d input_word=%0d",got,input_word);end
endmodule
