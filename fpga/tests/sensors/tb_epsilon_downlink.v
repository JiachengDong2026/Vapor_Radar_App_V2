`timescale 1ns/1ps
module tb_epsilon_downlink;
    reg clk=0;always #250 clk=~clk;
    reg rst=0,rx=1;
    reg [63:0] ticks=0;always @(posedge clk)ticks<=ticks+1;
    wire cv,cw,cr,ce,tx,correction_tx;
    reg observe_secondary=0;wire observed_tx=observe_secondary ? correction_tx : tx;wire [31:0] ca,cd,rd;wire [3:0] strobe;
    reg [31:0] value;integer i,n,base,tx_count=0;
    reg [7:0] sample,wire_bytes[0:4095],rtcm[0:1028],main_expected[0:1068];
    reg [31:0] word_value;
    modbus_cfg_bfm bus(.clk(clk),.rst_n(rst),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strobe),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce));
    epsilon_rs232 #(.SYS_CLK_HZ(2000000),.RECOVERY_ENABLE(0)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx),.uart_txd(tx),.correction_txd(correction_tx),
        .timestamp_now(ticks),.time_sync_valid(1'b0),.time_sync_seq(32'd1),.sync_event_pulse(1'b0),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strobe),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_ready(1'b1));
    initial forever begin
        @(negedge observed_tx);#15000;
        for(n=0;n<8;n=n+1)begin sample[n]=observed_tx;#10000;end
        if(observed_tx!==1)$fatal(1,"EPSILON truncated stop");
        wire_bytes[tx_count]=sample;tx_count=tx_count+1;#2500;
    end
    task send_byte;
        input [7:0] byte_value;integer b;
        begin rx=0;#10000;for(b=0;b<8;b=b+1)begin rx=byte_value[b];#10000;end rx=1;#10000;end
    endtask
    task wait_done;
        begin value=32'h10000;while(value[16])bus.read32('h624c,value);end
    endtask
    task stage_rtcm;
        input corrupt;
        begin
            bus.write32('h6244,1029);bus.write32('h6248,1);
            for(i=0;i<258;i=i+1)begin
                word_value=0;
                if(i*4<1029)word_value[7:0]=rtcm[i*4];
                if(i*4+1<1029)word_value[15:8]=rtcm[i*4+1];
                if(i*4+2<1029)word_value[23:16]=rtcm[i*4+2];
                if(i*4+3<1029)word_value[31:24]=rtcm[i*4+3];
                if(corrupt && i==257)word_value=word_value^1;
                bus.write32('h6268,word_value);
            end
        end
    endtask
    initial begin
        $readmemh("rtcm_max.hex",rtcm);$readmemh("rtcm_main_expected.hex",main_expected);
        repeat(5)@(negedge clk);rst=1;
        bus.write32('h6210,100000);bus.write32('h6270,100);
        bus.write32('h6244,7);bus.write32('h6268,'h736d6623);bus.write32('h6268,'h000a0d67);
        bus.expect_error(1,'h6240,1); // disabled cannot reserve the UART
        bus.write32('h6204,1);bus.write32('h6240,1);bus.expect_error(1,'h6244,7);
        wait(tx_count==7);#20000;send_byte("#");send_byte("O");send_byte("K");send_byte(13);send_byte(10);
        wait_done;if(value[7:0]!=0)$fatal(1,"EPSILON response result %h",value);
        bus.read32('h625c,value);if(value!=5)$fatal(1,"EPSILON response length");
        bus.read32('h6264,value);if(value!='h0d4b4f23)$fatal(1,"EPSILON raw response");
        if(wire_bytes[0]!="#" || wire_bytes[6]!=10)$fatal(1,"EPSILON ASCII wire command");
        bus.write32('h6274,1);bus.write32('h6278,100000);observe_secondary=1;
        stage_rtcm(0);base=tx_count;bus.write32('h6240,1);wait_done;
        if(value[7:0]!=0 || tx_count!=base+1029)$fatal(1,"RTCM full frame transmission %h %0d",value,tx_count-base);
        for(i=0;i<1029;i=i+1)if(wire_bytes[base+i]!=rtcm[i])$fatal(1,"RTCM wire byte %0d",i);
        bus.write32('h6274,0);observe_secondary=0;
        stage_rtcm(0);base=tx_count;bus.write32('h6240,1);wait_done;
        if(value[7:0]!=0 || tx_count!=base+1069)$fatal(1,"MAIN FDILink RTCM framing length");
        for(i=0;i<1069;i=i+1)if(wire_bytes[base+i]!=main_expected[i])$fatal(1,"MAIN FDILink header/CRC/payload byte %0d",i);
        bus.read32('h627c,value);if(value!=2058)$fatal(1,"RTCM payload accounting");
        stage_rtcm(1);base=tx_count;bus.write32('h6240,1);wait_done;
        if(value[7:0]!=3 || tx_count!=base)$fatal(1,"RTCM CRC accepted");
        bus.write32('h6244,1);bus.expect_error(1,'h6240,1); // incomplete staging
        bus.expect_error(1,'h6244,1030);bus.expect_error(1,'h6260,2048);
        bus.write32('h6244,7);bus.write32('h6248,0);bus.write32('h6268,'h736d6623);bus.write32('h6268,'h000a0d67);
        bus.write32('h6240,1);wait_done;if(value[7:0]!=1)$fatal(1,"ASCII response timeout");
        stage_rtcm(0);base=tx_count;bus.write32('h6240,1);
        wait(tx_count>base);bus.expect_error(1,'h6204,3);bus.write32('h6204,0);wait_done;
        if(value[7:0]!=4 || tx_count!=base+1069)$fatal(1,"RTCM disable truncated a frame");
        $display("TEST_PASS tb_epsilon_downlink MAIN UART ASCII response, full 1029-byte RTCM CRC24Q, MAIN FDILink 0x73 five fragments/CRC8/CRC16, secondary UART, no partial/invalid TX, busy/disabled/size rejection, timeout");$finish;
    end
    initial begin #900000000;$fatal(1,"EPSILON downlink timeout");end
endmodule
