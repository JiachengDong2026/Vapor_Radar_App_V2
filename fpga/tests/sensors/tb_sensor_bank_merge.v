`timescale 1ns/1ps
module tb_sensor_bank_merge;
    reg clk=0;always #20 clk=~clk;
    reg rst=0;reg [63:0] now=0;always @(posedge clk)now<=now+1'b1;
    reg cv=0,cw=0;reg [31:0] ca=0,cd=0;wire cr,ce;wire [31:0] rd;
    wire ptb_rx,ptb_tx,bus_rx,bus_tx,bus_de,eps_tx,tfa_hf,tfa_lf,tfa_tx;
    wire [27:0] cfg_codes;
    reg eps_rx=1,sync_pulse=0;
    wire scl_low,sda_low;tri1 scl,sda;assign scl=scl_low?0:1'bz;assign sda=sda_low?0:1'bz;
    wire [6:0] mv,ms,ml,online;reg [6:0] ready=0;
    wire [223:0] data,cycle,flags,errors,drops,levels;
    wire [27:0] keep;wire [111:0] source_id,msg_id;wire [447:0] timestamp;
    wire [63:0] tag;wire tag_valid;
    member3_sensor_bank #(.SYS_CLK_HZ(25000000),.PTB_BOOT_MS(1))dut(
        .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(now),.time_sync_valid(1'b1),.time_sync_seq(32'd42),
        .sync_event_pulse(sync_pulse),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),
        .cfg_ready(cr),.cfg_error(ce),.cfg_rdata(rd),.cfg_error_code(cfg_codes),
        .ptb_rxd(ptb_rx),.ptb_txd(ptb_tx),.rs485_rxd(bus_rx),.rs485_txd(bus_tx),.rs485_de(bus_de),
        .epsilon_rxd(eps_rx),.epsilon_txd(eps_tx),.tfa_hf_rxd(tfa_hf),.tfa_lf_rxd(tfa_lf),.tfa_txd(tfa_tx),
        .scl_i(scl),.sda_i(sda),.bmp_int(1'b0),
        .scl_drive_low(scl_low),.sda_drive_low(sda_low),.gnss_time_tag(tag),.gnss_time_tag_valid(tag_valid),
        .m_valid(mv),.m_ready(ready),.m_data(data),.m_keep(keep),.m_sof(ms),.m_last(ml),
        .m_source_id(source_id),.m_msg_id(msg_id),.m_timestamp(timestamp),.m_cycle_id(cycle),.m_flags(flags),
        .device_online(online),.device_error(errors),.device_drop_count(drops),.device_fifo_level(levels));
    wire [31:0] ptb_polls,ptb_bp;wire form_seen,reset_seen;
    ptb210_model #(.SYS_CLK_HZ(25000000),.REPEAT_VALID(1))ptb(
        .sys_clk(clk),.rst_sys_n(rst),.host_txd(ptb_tx),.host_rxd(ptb_rx),
        .poll_count(ptb_polls),.bp_count(ptb_bp),.form_seen(form_seen),.reset_seen(reset_seen));
    wire [31:0] areq,awrite,averify,hreq,hwrite,pressure_bits;
    wire [15:0] ai8_sp;
    ai8_hmp_bus_bfm #(.ALARM_WORD(0),.HOST_STATUS(0)) bus_model(
        .rst_n(rst),.master_txd(bus_tx),.master_de(bus_de),.slave_txd(bus_rx),
        .fault_mode(4'd0),.hmp_fault(4'd0),.request_count(areq),.write_count(awrite),
        .verify_count(averify),.hmp_count(hreq),.hmp_write_count(hwrite),
        .current_sp(ai8_sp),.pressure_bits(pressure_bits));
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
    task serial;input [7:0] b;integer j;begin eps_rx=0;#1085.069;for(j=0;j<8;j=j+1)begin eps_rx=b[j];#1085.069;end eps_rx=1;#1085.069;end endtask
    initial begin
        for(e=0;e<110;e=e+1)eps_frame[e]=0;
        eps_frame[0]='hfc;eps_frame[1]='h50;eps_frame[2]=102;eps_frame[3]=7;eps_frame[9]=8;
        {eps_frame[16],eps_frame[15],eps_frame[14],eps_frame[13]}=32'd1700000000;
        {eps_frame[20],eps_frame[19],eps_frame[18],eps_frame[17]}=32'd123456;
        h=0;for(e=0;e<4;e=e+1)h=crc8(h,eps_frame[e]);eps_frame[4]=h;
        c=0;for(e=7;e<109;e=e+1)c=crc16(c,eps_frame[e]);eps_frame[5]=c[15:8];eps_frame[6]=c[7:0];eps_frame[109]='hfd;
        wait(run_sources);forever begin for(n=0;n<110;n=n+1)serial(eps_frame[n]);#2800000;end
    end
    task wr;input [31:0] a,d;begin
        @(negedge clk);cv=1;cw=1;ca=a;cd=d;#1;if(!cr||ce)$fatal(1,"cfg write %h error %b",a,ce);
        @(negedge clk);cv=0;cw=0;
    end endtask
    integer packets[0:6],beats[0:6],position[0:6];
    reg [197:0] held[0:6],packet_metadata[0:6];reg [6:0] stalled=0;
    reg [197:0] bundle;integer k;integer tags=0;
    reg [15:0] lfsr=16'hbeef;reg random_ready=1;
    always @(negedge clk)if(rst)begin
        lfsr={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
        if(random_ready)ready=lfsr[6:0];else ready=0;
    end
    always @(posedge clk)if(rst)begin
        if(tag_valid)begin tags=tags+1;if(tag!=64'd1700000000123456)$fatal(1,"UTC tag");end
        for(k=0;k<7;k=k+1)begin
            bundle={flags[k*32+:32],cycle[k*32+:32],timestamp[k*64+:64],msg_id[k*16+:16],source_id[k*16+:16],ml[k],ms[k],keep[k*4+:4],data[k*32+:32]};
            if(stalled[k]&&(!mv[k]||bundle!==held[k]))$fatal(1,"lane %d changed under stall",k);
            stalled[k]=mv[k]&&!ready[k];held[k]=bundle;
            if(mv[k]&&ready[k])begin
                if(source_id[k*16+:16]!=16'h40+k||cycle[k*32+:32]!=32'hffffffff||timestamp[k*64+:64]==0||flags[k*32+:3]!=5)
                    $fatal(1,"lane %d metadata",k);
                if(msg_id[k*16+:16]!=(k==2?16'h1200:16'h1100))$fatal(1,"lane %d message ID",k);
                if(ms[k]!=(position[k]==0))$fatal(1,"lane %d packet boundary",k);
                if(position[k]==0)packet_metadata[k]=bundle;
                else if(bundle[197:38]!=packet_metadata[k][197:38])$fatal(1,"lane %d metadata changes within packet",k);
                if(ml[k])begin packets[k]=packets[k]+1;position[k]=0;end else position[k]=position[k]+1;
                beats[k]=beats[k]+1;
            end
        end
    end
    initial begin
        for(k=0;k<7;k=k+1)begin packets[k]=0;beats[k]=0;position[k]=0;held[k]=0;packet_metadata[k]=0;end
        repeat(20)@(negedge clk);rst=1;
        // Check the actual bank routing and AI8 identity before enable.
        @(negedge clk);cv=1;cw=0;ca='h6600;#1;
        if(!cr||ce||rd!==32'h00460200)$fatal(1,"AI8 identity/routing");
        @(negedge clk);cv=0;
        wr('h6018,10);wr('h6314,100);wr('h6414,20);wr('h662c,20);
        wr('h6004,1);wr('h6204,1);wr('h6304,1);wr('h6404,1);wr('h6504,1);wr('h6604,1);
        #20000000;run_sources=1;
        wait(packets[0]>=2&&packets[2]>=2&&packets[3]>=2&&packets[4]>=2&&packets[5]>=2&&packets[6]>=2);
        random_ready=0;#120000000;random_ready=1;
        wait(drops[5*32+:32]!=0);#5000000;
        if(!form_seen||!reset_seen||tags==0||online!=7'h7d)$fatal(1,"missing independent device activity online=%h",online);
        for(k=0;k<7;k=k+1)if(k!=1 && (packets[k]<2||beats[k]==0))$fatal(1,"starved lane %d",k);
        if(hreq!=0 || hwrite!=0 || packets[1]!=0)$fatal(1,"HMP default disabled");
        if(eps_tx!==1'b1 || dut.u_2.debug_attempts!=0)$fatal(1,"healthy EPS recovery TX");
        wr('h6650,300);wr('h6604,5);
        wait(awrite==1 && averify==1);#10000000;
        @(negedge clk);cv=1;cw=0;ca='h6648;#1;
        if(!cr||ce||rd!=1||ai8_sp!=300)$fatal(1,"AI8 confirmed SET through bank");
        @(negedge clk);cv=0;
        $display("SENSOR_BANK_MERGE_PASS packets=%0d,%0d,%0d,%0d,%0d,%0d,%0d tags=%0d TFA_drop=%0d",
            packets[0],packets[1],packets[2],packets[3],packets[4],packets[5],packets[6],tags,drops[160+:32]);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"watchdog packets=%d,%d,%d,%d,%d,%d,%d",packets[0],packets[1],packets[2],packets[3],packets[4],packets[5],packets[6]);end
endmodule
