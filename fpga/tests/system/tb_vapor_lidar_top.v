`timescale 1ns/1ps
module tb_vapor_lidar_top;
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
    localparam COMMAND_WORDS=987,RESPONSES=73;
    vapor_lidar_top #(.SIMULATION(1),.GPIF_CLK_HZ(50000000),.RAW0_MAX_SAMPLES(64),.RAW1_MAX_SAMPLES(64)) dut(
        .CLK_FPGA_25MHZ(CLK_FPGA_25MHZ),
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
    always #5 CLK_FPGA_25MHZ=~CLK_FPGA_25MHZ;
    always #10 ADC_ADC3660_DCLK=~ADC_ADC3660_DCLK;
    reg [31:0] commands[0:COMMAND_WORDS-1];
    reg [7:0] expected[0:RESPONSES*64-1],masks[0:RESPONSES*64-1],lengths[0:RESPONSES-1];
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
            if(input_word>=COMMAND_WORDS || read_delay!=0)$fatal(1,"top FX3 read empty");
            pending_data=commands[input_word];input_word=input_word+1;read_delay=3;
        end
        if(read_delay!=0)begin read_delay=read_delay-1;if(read_delay==0)slave_data<=#2 pending_data;end
        if(cooldown!=0)begin cooldown=cooldown-1;if(cooldown==0)space=256;end
        else if(tick%500==0)space=256;
        ready_pipe<={ready_pipe[2:0],space>0 && cooldown==0};
        partial_pipe<={partial_pipe[2:0],space>8 && cooldown==0};
        rx_pipe<={rx_pipe[1:0],input_word<COMMAND_WORDS};
    end
    initial begin
        $readmemh("top_commands.hex",commands);
        $readmemh("top_responses.hex",expected);
        $readmemh("top_response_masks.hex",masks);
        $readmemh("top_response_lengths.hex",lengths);
        wait(got==RESPONSES);before_reset=dut.timestamp_now;
        wait(!dut.rst_control_n);
        if(!dut.rst_adc_n || !dut.rst_wms_n || !dut.rst_sensors_n || !CYUSB_RSTN)$fatal(1,"masked stream reset disturbed devices");
        wait(dut.rst_control_n);repeat(20)@(negedge CLK_FPGA_25MHZ);
        if(dut.timestamp_now<=before_reset || !dut.global_enable || dut.raw_stream_mask[33:32]!=3 || !dut.reset_reason[2])
            $fatal(1,"persistent system/time state after software reset");
        $display("tb_vapor_lidar_top_PASS responses=%0d frames=%0d all21pages=1 RO21=1 range9=1 GPIF50=1 CRC_rejection=1 masked_reset=1",got,frame_count);$finish;
    end
    initial begin #5000000;$fatal(1,"top timeout responses=%0d input_word=%0d",got,input_word);end
endmodule
