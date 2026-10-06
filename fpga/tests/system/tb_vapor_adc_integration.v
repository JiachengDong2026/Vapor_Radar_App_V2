`timescale 1ns/1ps
module tb_vapor_adc_integration #(parameter integer GPIF_TEST_HZ=50000000);
    reg CLK_FPGA_25MHZ=0;
    wire [31:0] FPGA_GPIF_DQ;
    wire [12:0] FPGA_GPIF_CTL;
    reg FPGA_GPIF_INTN=1;
    wire FPGA_GPIF_PCLK;
    wire CYUSB_RSTN;
    reg FPGA_RS232A_RXD=1;
    reg FPGA_RS485_RXD_L=1;
    reg FPGA_RS422_RXD_L=1;
    reg FPGA_UART_RXD_L=1;
    reg TFA_LF_RXD=1;
    reg FPGA_RS232B_RXD=1;
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
    wire ADC_AD4630_BUSY;
    wire [7:0] ADC_AD4630_SDO;
    wire ADC_ADC3660_DA5;
    wire ADC_ADC3660_DA6;
    wire ADC_ADC3660_DB5;
    wire ADC_ADC3660_DB6;
    wire ADC_ADC3660_DCLK;
    wire ADC_ADC3660_FCLK;
    wire ADC_ADC3660_DCLKIN;
    wire ADC_ADC3660_CLKP;
    wire ADC_ADC3660_CLKN;
    wire ADC_ADC3660_SEN;
    wire ADC_ADC3660_SCLK;
    wire ADC_ADC3660_RST;
    wire ADC_ADC3660_SYNC;
    wire ADC_ADC3660_SDIO;
    vapor_lidar_top #(.SIMULATION(1),.DUAL_AD4630(0),.GPIF_CLK_HZ(GPIF_TEST_HZ),.RAW0_MAX_SAMPLES(512),.RAW1_MAX_SAMPLES(4096)) dut(
        .CLK_FPGA_25MHZ(CLK_FPGA_25MHZ),
        .FPGA_GPIF_DQ(FPGA_GPIF_DQ),
        .FPGA_GPIF_CTL(FPGA_GPIF_CTL),
        .FPGA_GPIF_INTN(FPGA_GPIF_INTN),
        .FPGA_GPIF_PCLK(FPGA_GPIF_PCLK),
        .CYUSB_RSTN(CYUSB_RSTN),
        .FPGA_RS232A_RXD(FPGA_RS232A_RXD),
        .FPGA_RS485_RXD_L(FPGA_RS485_RXD_L),
        .FPGA_RS422_RXD_L(FPGA_RS422_RXD_L),
        .FPGA_UART_RXD_L(FPGA_UART_RXD_L),
        .TFA_LF_RXD(TFA_LF_RXD),
        .FPGA_RS232B_RXD(FPGA_RS232B_RXD),
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
    // SIMULATION uses the input clock directly: 100 MHz is intentional.
    always #5 CLK_FPGA_25MHZ=~CLK_FPGA_25MHZ;
    wire configured0,configured1;wire [31:0] conversions,model_samples;
    ad4630_model model0(.rst_n(ADC_AD4630_RSTN),.cnv(ADC_AD4630_CNV),.cs_n(ADC_AD4630_CSN),.sck(ADC_AD4630_SCK),.sdi(ADC_AD4630_SDI),
        .stall_busy(1'b0),.busy(ADC_AD4630_BUSY),.sdo(ADC_AD4630_SDO),.conversions(conversions),.configured(configured0));
    adc3660_model model1(.rst_n(!ADC_ADC3660_RST),.sample_clk(ADC_ADC3660_CLKP),.dclkin(ADC_ADC3660_DCLKIN),.sen(ADC_ADC3660_SEN),.sclk(ADC_ADC3660_SCLK),.sdio(ADC_ADC3660_SDIO),
        .stop_dclk(1'b0),.slip(1'b0),.dclk(ADC_ADC3660_DCLK),.fclk(ADC_ADC3660_FCLK),.da5(ADC_ADC3660_DA5),.da6(ADC_ADC3660_DA6),.db5(ADC_ADC3660_DB5),.db6(ADC_ADC3660_DB6),
        .configured(configured1),.sample_count(model_samples));
    // Independent host command encoder; every control operation traverses pins,
    // RX FIFO, byte unpacker, VLP CRC parser, decoder and cfg arbitration.
    reg [31:0] commands[0:8191],host_payload[0:15],read_value=0;
    reg [7:0] command_bytes[0:127];
    integer available=0,input_word=0,command_sequence=0,responses=0;
    reg [15:0] expected_command[0:255];
    function [31:0] crc_byte;
        input [31:0] c;input [7:0] b;integer k;reg [31:0] temp;
        begin temp=c^b;for(k=0;k<8;k=k+1)temp=temp[0]?((temp>>1)^32'hedb88320):(temp>>1);crc_byte=temp;end
    endfunction
    task put_word;
        input integer a;input [31:0] d;
        begin command_bytes[a]=d[7:0];command_bytes[a+1]=d[15:8];command_bytes[a+2]=d[23:16];command_bytes[a+3]=d[31:24];end
    endtask
    task command;
        input [15:0] mid;input integer words;
        integer n,bytes,new_end;reg [31:0] c;
        begin
            @(negedge CLK_FPGA_25MHZ);command_sequence=command_sequence+1;expected_command[command_sequence]=mid;
            bytes=44+words*4;for(n=0;n<128;n=n+1)command_bytes[n]=0;
            put_word(0,32'h31504c56);put_word(4,32'h0a010001);put_word(8,bytes);put_word(12,command_sequence);
            put_word(16,{mid,16'h1});put_word(36,words*4);
            for(n=0;n<words;n=n+1)put_word(40+n*4,host_payload[n]);
            c=32'hffffffff;for(n=0;n<bytes-4;n=n+1)c=crc_byte(c,command_bytes[n]);put_word(bytes-4,~c);
            new_end=available+bytes/4;
            for(n=0;n<bytes/4;n=n+1)commands[available+n]={command_bytes[n*4+3],command_bytes[n*4+2],command_bytes[n*4+1],command_bytes[n*4]};
            available=new_end;
            wait(responses==command_sequence);@(negedge CLK_FPGA_25MHZ);
        end
    endtask
    task write_reg;
        input [31:0] a,d;input auto_commit;
        begin host_payload[0]=a;host_payload[1]=auto_commit?32'h10001:1;host_payload[2]=d;command(3,3);end
    endtask
    task read_reg;
        input [31:0] a;
        begin host_payload[0]=a;host_payload[1]=1;command(2,2);end
    endtask
    task acquisition;
        input [15:0] mid;
        begin host_payload[0]=32'h30000;host_payload[1]=0;host_payload[2]=0;host_payload[3]=0;command(mid,4);end
    endtask
    // Observe the real member output boundaries, then compare every byte and
    // metadata field after framing/arbiter/packetizer/CDC/physical GPIF.
    wire [3:0] sv={dut.dila_valid,dut.raw_valid},sr={dut.dila_ready,dut.raw_ready};
    wire [3:0] ss={dut.dila_sof,dut.raw_sof},sl={dut.dila_last,dut.raw_last};
    wire [127:0] sd={dut.dila_data,dut.raw_data},sf={dut.dila_flags,dut.raw_flags},sc={dut.dila_cycle_id,dut.raw_cycle_id};
    wire [255:0] st={dut.dila_timestamp,dut.raw_timestamp};
    reg [31:0] expected_data[0:262143],expected_flags[0:1023],expected_cycle[0:1023];
    reg [63:0] expected_time[0:1023],cycle_tick[0:127];
    integer beat_write[0:3],beat_read[0:3],frame_write[0:3],frame_read[0:3],building[0:3],frame_beats[0:1023];
    integer counts[0:3],partial_count[0:3],fragments[0:3],capture_count[0:1];
    reg [31:0] fragment_cycle[0:3];
    integer next_fragment[0:3],next_point[0:3],cycle_fragments[0:3],cycle_points[0:3];
    reg [31:0] stop_cycle[0:1];reg [3:0] stop_partial=0;
    reg [63:0] last_capture[0:1];reg [31:0] last_data0,last_data1;
    integer lane,slot,fi,k,adc0_pattern_index=0;
    function [31:0] ad4630_pattern;
        input integer index;
        begin case(index%8)
            0:ad4630_pattern=32'h00123456;1:ad4630_pattern=32'hfffedcba;
            2:ad4630_pattern=32'h007fffff;3:ad4630_pattern=32'hff800000;
            4:ad4630_pattern=1;5:ad4630_pattern=32'hffffffff;
            6:ad4630_pattern=32'h00555555;default:ad4630_pattern=32'hffaaaaaa;
        endcase end
    endfunction
    always @(posedge CLK_FPGA_25MHZ)if(dut.rst_adc_n)begin
        for(k=0;k<2;k=k+1)if(dut.wms_scan_start[k])begin
            if(dut.wms_cycle_id[k*32+:32]>=64)$fatal(1,"cycle oracle capacity");
            cycle_tick[k*64+dut.wms_cycle_id[k*32+:32]]=dut.timestamp_now;
        end
        for(k=0;k<2;k=k+1)if(dut.stop_flush[k])stop_cycle[k]=dut.wms_cycle_id[k*32+:32];
        if(dut.raw0_valid&&dut.raw0_ready)begin
            if(dut.raw0_data!==ad4630_pattern(adc0_pattern_index))$fatal(1,"ADC0 pin data order index=%d got=%h",adc0_pattern_index,dut.raw0_data);
            adc0_pattern_index=adc0_pattern_index+1;
            if(capture_count[0]>0 && dut.raw0_capture_timestamp-last_capture[0]!=100)$fatal(1,"ADC0 sample spacing");
            if(dut.raw0_capture_phase_valid && dut.raw0_cycle_timestamp!==cycle_tick[dut.raw0_capture_cycle_id])$fatal(1,"ADC0 cycle tag");
            capture_count[0]=capture_count[0]+1;last_capture[0]=dut.raw0_capture_timestamp;
        end
        if(dut.raw1_valid&&dut.raw1_ready)begin
            if(capture_count[1]>0 && dut.raw1_data[15:0]!==last_data1[15:0]+16'd1)$fatal(1,"ADC1 pin sample order got=%h last=%h",dut.raw1_data,last_data1);
            if(dut.raw1_data[31:16]!=={16{dut.raw1_data[15]}})$fatal(1,"ADC1 sign extension");
            if(capture_count[1]>0 && dut.raw1_capture_timestamp-last_capture[1]!=8)$fatal(1,"ADC1 sample spacing");
            if(dut.raw1_capture_phase_valid && dut.raw1_cycle_timestamp!==cycle_tick[64+dut.raw1_capture_cycle_id])$fatal(1,"ADC1 cycle tag");
            capture_count[1]=capture_count[1]+1;last_capture[1]=dut.raw1_capture_timestamp;last_data1=dut.raw1_data;
        end
        for(k=0;k<4;k=k+1)if(sv[k]&&sr[k])begin
            slot=k*65536+(beat_write[k]%65536);fi=k*256+(frame_write[k]%256);
            if(beat_write[k]-beat_read[k]>=65536 || frame_write[k]-frame_read[k]>=256)$fatal(1,"oracle queue full");
            expected_data[slot]=sd[k*32+:32];
            if(ss[k])begin
                if(building[k]!=0)$fatal(1,"nested source frame");
                expected_flags[fi]=sf[k*32+:32];expected_cycle[fi]=sc[k*32+:32];expected_time[fi]=st[k*64+:64];
                if(sc[k*32+:32]==0 || st[k*64+:64]!==cycle_tick[(k%2)*64+sc[k*32+:32]])$fatal(1,"source cycle/time lane=%d cycle=%d",k,sc[k*32+:32]);
            end
            beat_write[k]=beat_write[k]+1;building[k]=building[k]+1;
            if(sl[k])begin frame_beats[fi]=building[k];building[k]=0;frame_write[k]=frame_write[k]+1;end
        end
    end
    // FX3 finite-buffer model: two PCLK pipeline edges then max 7 ns DQ,
    // flag pipeline then max 8 ns pin delay. Sample actual forwarded PCLK.
    reg [31:0] slave_data=0,pending_data;
    reg [3:0] ready_pipe=0,partial_pipe=0;reg [2:0] rx_pipe=0;
    reg host_stall=0;integer space=256,cooldown=0,tick=0,read_delay=0,stalled_ticks=0;
    reg [7:0] frame[0:8300];integer byte_count=0,frame_count=0,i,total,payload,seq,words,frag_count,frag_index,frag_first,frag_points;
    reg [31:0] crc;reg stop_completed=0;integer stop_sequence=0;
    time last_pclk=0;
    assign FPGA_GPIF_CTL[4]=ready_pipe[3];assign FPGA_GPIF_CTL[6]=partial_pipe[3];
    assign FPGA_GPIF_CTL[5]=rx_pipe[2];assign FPGA_GPIF_CTL[8]=rx_pipe[2];
    assign FPGA_GPIF_DQ=!FPGA_GPIF_CTL[2]?slave_data:32'bz;
    function [31:0] word_at;
        input integer offset;begin word_at={frame[offset+3],frame[offset+2],frame[offset+1],frame[offset]};end
    endfunction
    task check_frame;begin
        frame_count=frame_count+1;total=word_at(8);payload=word_at(36);seq=word_at(12);
        if(word_at(0)!==32'h31504c56 || frame[4]!=1 || frame[7]!=10 || total!=44+payload || (total+3)/4*4!=byte_count)$fatal(1,"VLP header/length");
        crc=32'hffffffff;for(i=0;i<total-4;i=i+1)crc=crc_byte(crc,frame[i]);
        if((crc^32'hffffffff)!==word_at(total-4))$fatal(1,"VLP CRC frame=%d",frame_count);
        for(i=total;i<byte_count;i=i+1)if(frame[i]!=0)$fatal(1,"VLP padding");
        if(frame[6]==2)begin
            if(seq!=responses+1 || {frame[19],frame[18]}!=expected_command[seq] || {frame[17],frame[16]}!=1 || word_at(40)!=0)$fatal(1,"command response seq=%d mid=%h status=%d",seq,word_at(16),word_at(40));
            if(expected_command[seq]==2)begin if(payload!=16)$fatal(1,"READ response length");read_value=word_at(52);end
            else if(payload!=4)$fatal(1,"action/write response length");
            if(seq==stop_sequence)begin
                if(dut.wms_running!=0 || dut.channel_idle!=3 || dut.action_busy)$fatal(1,"STOP responded before complete");
                stop_completed=1;
            end
            responses=responses+1;
        end else if(frame[6]==16 && ({frame[19],frame[18]}==16'h1000 || {frame[19],frame[18]}==16'h1001))begin
            case({frame[17],frame[16]})16'h20:lane=0;16'h21:lane=1;16'h30:lane=2;16'h31:lane=3;default:$fatal(1,"bulk source");endcase
            fi=lane*256+(frame_read[lane]%256);
            if(frame_read[lane]>=frame_write[lane])$fatal(1,"GPIF bulk without source frame");
            if(word_at(20)!==expected_flags[fi] || word_at(32)!==expected_cycle[fi] || {word_at(28),word_at(24)}!==expected_time[fi])$fatal(1,"GPIF cycle/time/flags lane=%d",lane);
            if(payload!=frame_beats[fi]*4)$fatal(1,"bulk payload length");
            for(i=0;i<frame_beats[fi];i=i+1)begin
                slot=lane*65536+(beat_read[lane]%65536);
                if(word_at(40+i*4)!==expected_data[slot])$fatal(1,"bulk data lane=%d word=%d",lane,i);
                beat_read[lane]=beat_read[lane]+1;
            end
            if(lane<2)begin
                if(word_at(44)!==(lane==0?32'd1000000:32'd12500000))$fatal(1,"RAW actual rate");
                if(frame[40]==1)begin
                    if(payload!=20+word_at(48)*4)$fatal(1,"RAW1 size");
                    frag_count=1;frag_index=0;frag_first=0;frag_points=word_at(48);
                end
                else if(frame[40]==2)begin
                    frag_count=word_at(56)>>16;
                    frag_index=word_at(56)&65535;frag_first=word_at(60);frag_points=word_at(64);
                    if(payload!=32+word_at(64)*4 || frag_count<2 || word_at(60)+word_at(64)>word_at(48))$fatal(1,"RAW2 fragment");
                    fragments[lane]=fragments[lane]+1;
                end else $fatal(1,"RAW schema");
            end else begin
                frag_count=word_at(52)>>16;
                frag_index=word_at(52)&65535;frag_first=word_at(56);frag_points=word_at(60);
                if(word_at(40)!=2 || word_at(44)!=100000 || word_at(64)!=8 || payload!=32+word_at(60)*8 || word_at(60)>17)$fatal(1,"DILA schema/fragment");
                if(frag_count>1)fragments[lane]=fragments[lane]+1;
            end
            if(word_at(32)!=fragment_cycle[lane])begin
                if(next_fragment[lane]!=cycle_fragments[lane])$fatal(1,"incomplete previous fragment sequence");
                fragment_cycle[lane]=word_at(32);next_fragment[lane]=0;next_point[lane]=0;
                cycle_fragments[lane]=frag_count;cycle_points[lane]=word_at(48);
            end
            if(frag_index!=next_fragment[lane] || frag_first!=next_point[lane] || frag_count!=cycle_fragments[lane] || word_at(48)!=cycle_points[lane])$fatal(1,"fragment ordering/total lane=%d",lane);
            next_fragment[lane]=next_fragment[lane]+1;next_point[lane]=next_point[lane]+frag_points;
            if(next_fragment[lane]==frag_count && next_point[lane]!=cycle_points[lane])$fatal(1,"fragment sample total");
            if((word_at(20)&32'h20)!=0)partial_count[lane]=partial_count[lane]+1;
            if(word_at(32)==stop_cycle[lane%2] && (word_at(20)&32'h20)!=0)stop_partial[lane]=1;
            frame_read[lane]=frame_read[lane]+1;counts[lane]=counts[lane]+1;
        end
        byte_count=0;
    end endtask
    always @(posedge FPGA_GPIF_PCLK)if(CYUSB_RSTN)begin
        if(last_pclk!=0 && $time-last_pclk!=1000000000/GPIF_TEST_HZ)$fatal(1,"actual PCLK period mismatch");
        last_pclk=$time;
        tick=tick+1;
        if(!FPGA_GPIF_CTL[1]&&!FPGA_GPIF_CTL[3])$fatal(1,"GPIF collision");
        if(!FPGA_GPIF_CTL[0]&&!FPGA_GPIF_CTL[1])begin
            if(space==0 || cooldown!=0 || !FPGA_GPIF_CTL[2])$fatal(1,"FX3 write full/direction");
            for(i=0;i<4;i=i+1)frame[byte_count+i]=FPGA_GPIF_DQ>>(i*8);
            byte_count=byte_count+4;space=space-1;
            if(!FPGA_GPIF_CTL[7])begin check_frame;space=0;cooldown=5;end
        end
        if(!FPGA_GPIF_CTL[0]&&!FPGA_GPIF_CTL[3])begin
            if(input_word>=available || read_delay!=0 || FPGA_GPIF_CTL[2])$fatal(1,"FX3 read empty/direction");
            pending_data=commands[input_word];input_word=input_word+1;read_delay=3;
        end
        if(read_delay!=0)begin read_delay=read_delay-1;if(read_delay==0)slave_data<=#7 pending_data;end
        if(cooldown!=0)begin cooldown=cooldown-1;if(cooldown==0&&!host_stall)space=256;end
        else if(!host_stall&&tick%397==0)space=256;
        if(space==0)stalled_ticks=stalled_ticks+1;
        ready_pipe<=#8 {ready_pipe[2:0],space>0&&cooldown==0};partial_pipe<=#8 {partial_pipe[2:0],space>8&&cooldown==0};
        rx_pipe<=#8 {rx_pipe[1:0],input_word<available};
    end
    integer n,polls;
    initial begin
        for(n=0;n<4;n=n+1)begin
            counts[n]=0;partial_count[n]=0;fragments[n]=0;beat_write[n]=0;beat_read[n]=0;frame_write[n]=0;frame_read[n]=0;building[n]=0;
            fragment_cycle[n]=32'hffffffff;next_fragment[n]=0;next_point[n]=0;cycle_fragments[n]=0;cycle_points[n]=0;
        end
        for(n=0;n<2;n=n+1)begin capture_count[n]=0;last_capture[n]=0;stop_cycle[n]=32'hffffffff;end
        for(n=0;n<128;n=n+1)cycle_tick[n]=0;
        wait(CYUSB_RSTN);repeat(50)@(negedge CLK_FPGA_25MHZ);
        write_reg(32'h002c,0,0);write_reg(32'h0030,32'h00030000,0);write_reg(32'h0050,3,0);
        write_reg(32'h403c,1,0);write_reg(32'h413c,1,0);
        write_reg(32'h2010,1000000,1);write_reg(32'h2110,2000000,1);
        write_reg(32'h501c,100000,0);write_reg(32'h511c,100000,0);
        write_reg(32'h5040,17,0);write_reg(32'h5140,17,0);
        write_reg(32'h5020,7,1);write_reg(32'h5120,7,1);
        polls=0;read_reg(32'h4108);
        while(!read_value[1])begin #10000;read_reg(32'h4108);polls=polls+1;if(polls>50)$fatal(1,"ADC3660 init");end
        read_reg(32'h4008);if(!read_value[1]||!configured0||!configured1)$fatal(1,"pin-model initialization");
        acquisition(6);$display("ADC_TOP_START_PASS time=%t",$time);
        wait(counts[0]>0&&counts[1]>0&&counts[2]>0&&counts[3]>0);
        $display("ADC_TOP_FIRST_FRAMES_PASS time=%t",$time);
        host_stall=1;#1400000;host_stall=0;#850000;
        stop_sequence=command_sequence+1;acquisition(7);
        wait(stop_completed);repeat(50000)@(negedge CLK_FPGA_25MHZ);
        for(n=0;n<4;n=n+1)begin
            if(counts[n]<2 || partial_count[n]==0 || frame_read[n]!=frame_write[n] || beat_read[n]!=beat_write[n] || next_fragment[n]!=cycle_fragments[n])$fatal(1,"incomplete lane=%d frames=%d partial=%d pending=%d",n,counts[n],partial_count[n],frame_write[n]-frame_read[n]);
        end
        if(fragments[1]==0||fragments[2]==0||fragments[3]==0||stalled_ticks==0||dut.raw0_drop_count==0||dut.raw1_drop_count==0)$fatal(1,"missing fragmentation/pressure coverage");
        if(stop_partial!=15)$fatal(1,"STOP final cycle partial missing lanes=%b cycles=%d/%d",stop_partial,stop_cycle[0],stop_cycle[1]);
        if(dut.protocol_errors!=0||dut.crc_errors!=0||dut.packet_errors!=0)$fatal(1,"protocol errors");
        $display("tb_vapor_adc_integration_PASS GPIF_HZ=%d SYS_HZ=100000000 DQ_MAX_NS=7 FLAG_MAX_NS=8 responses=%d frames=%d RAW=%d/%d DILA=%d/%d partial=%d/%d/%d/%d capture=%d/%d CRC_all STOP_idle pin_models pressure",GPIF_TEST_HZ,responses,frame_count,counts[0],counts[1],counts[2],counts[3],partial_count[0],partial_count[1],partial_count[2],partial_count[3],capture_count[0],capture_count[1]);$finish;
    end
    initial begin #15000000;$fatal(1,"ADC top timeout resp=%d seq=%d frames=%d counts=%d/%d/%d/%d state=%d",responses,command_sequence,frame_count,counts[0],counts[1],counts[2],counts[3],dut.u_actions.state);end
endmodule
