`timescale 1ns/1ps
module i2c_shared_test #(parameter integer DEVICES=3);
    reg clk=0;always #5 clk=~clk;
    reg rst=0;reg [63:0] now=0;always @(posedge clk)now<=now+1'b1;
    reg cv=0,cw=0;reg [31:0] ca=0,cd=0;reg [3:0] strb=15;
    wire [1:0] cr,ce,rv,rr,done,mv,ms,ml,online;
    wire [63:0] rd,md,mc,mf,errs,drops,levels;
    wire [7:0] mk;wire [31:0] src,msg;wire [127:0] ts;
    reg [1:0] ready=0;
    wire [13:0] addr;wire [11:0] wl,rl;wire [511:0] wd,rdata;wire [5:0] error;
    wire reqv,reqr,master_done;wire [6:0] ma;wire [5:0] mwl,mrl;
    wire [255:0] mwd,mrd;wire [2:0] me;
    wire scl_low,sda_low,busy;
    tri1 scl,sda;
    reg stuck_scl=0,stuck_sda=0,nack=0,bad_crc=0;
    assign scl=(scl_low||stuck_scl)?1'b0:1'bz;
    assign sda=(sda_low||stuck_sda)?1'b0:1'bz;
    wire [31:0] bmp_transactions,sht_transactions,bmp_samples,sht_samples;
    wire [7:0] bmp_command,sht_command;
    generate if(DEVICES&1)begin:g_bmp
    bmp390_driver #(.SYS_CLK_HZ(1000000)) bmp(
        .sys_clk(clk),.rst_sys_n(rst),.bmp_int(1'b0),.timestamp_now(now),.time_sync_valid(1'b1),.time_sync_seq(32'd3),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strb),.cfg_ready(cr[0]),.cfg_error(ce[0]),.cfg_rdata(rd[31:0]),
        .req_valid(rv[0]),.req_ready(rr[0]),.req_addr(addr[6:0]),.req_write_len(wl[5:0]),.req_read_len(rl[5:0]),
        .req_write_data(wd[255:0]),.done(done[0]),.error(error[2:0]),.read_data(rdata[255:0]),
        .m_valid(mv[0]),.m_ready(ready[0]),.m_data(md[31:0]),.m_keep(mk[3:0]),.m_sof(ms[0]),.m_last(ml[0]),
        .m_source_id(src[15:0]),.m_msg_id(msg[15:0]),.m_timestamp(ts[63:0]),.m_cycle_id(mc[31:0]),.m_flags(mf[31:0]),
        .online(online[0]),.errors(errs[31:0]),.drop_count(drops[31:0]),.fifo_level(levels[31:0]));
    end else begin
    assign {cr[0],ce[0],rv[0],mv[0],ms[0],ml[0],online[0]}=0;
    assign {rd[31:0],md[31:0],mc[31:0],mf[31:0],errs[31:0],drops[31:0],levels[31:0]}=0;
    assign {mk[3:0],src[15:0],msg[15:0],ts[63:0],addr[6:0],wl[5:0],rl[5:0],wd[255:0]}=0;
    end endgenerate
    generate if(DEVICES&2)begin:g_sht
    sht45_driver #(.SYS_CLK_HZ(1000000)) sht(
        .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(now),.time_sync_valid(1'b1),.time_sync_seq(32'd3),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strb),.cfg_ready(cr[1]),.cfg_error(ce[1]),.cfg_rdata(rd[63:32]),
        .req_valid(rv[1]),.req_ready(rr[1]),.req_addr(addr[13:7]),.req_write_len(wl[11:6]),.req_read_len(rl[11:6]),
        .req_write_data(wd[511:256]),.done(done[1]),.error(error[5:3]),.read_data(rdata[511:256]),
        .m_valid(mv[1]),.m_ready(ready[1]),.m_data(md[63:32]),.m_keep(mk[7:4]),.m_sof(ms[1]),.m_last(ml[1]),
        .m_source_id(src[31:16]),.m_msg_id(msg[31:16]),.m_timestamp(ts[127:64]),.m_cycle_id(mc[63:32]),.m_flags(mf[63:32]),
        .online(online[1]),.errors(errs[63:32]),.drop_count(drops[63:32]),.fifo_level(levels[63:32]));
    end else begin
    assign {cr[1],ce[1],rv[1],mv[1],ms[1],ml[1],online[1]}=0;
    assign {rd[63:32],md[63:32],mc[63:32],mf[63:32],errs[63:32],drops[63:32],levels[63:32]}=0;
    assign {mk[7:4],src[31:16],msg[31:16],ts[127:64],addr[13:7],wl[11:6],rl[11:6],wd[511:256]}=0;
    end endgenerate
    i2c_arbiter_2 arb(.sys_clk(clk),.rst_sys_n(rst),.c_valid(rv),.c_ready(rr),.c_addr(addr),.c_write_len(wl),.c_read_len(rl),
        .c_write_data(wd),.c_done(done),.c_error(error),.c_read_data(rdata),.req_valid(reqv),.req_ready(reqr),.req_addr(ma),
        .req_write_len(mwl),.req_read_len(mrl),.req_write_data(mwd),.done(master_done),.error(me),.read_data(mrd));
    i2c_master #(.SYS_CLK_HZ(1000000),.I2C_HZ(100000),.TIMEOUT_TICKS(20000)) bus(
        .sys_clk(clk),.rst_sys_n(rst),.req_valid(reqv),.req_ready(reqr),.req_addr(ma),.req_write_len(mwl),.req_read_len(mrl),
        .req_write_data(mwd),.done(master_done),.error(me),.read_data(mrd),.scl_i(scl),.sda_i(sda),
        .scl_drive_low(scl_low),.sda_drive_low(sda_low),.busy(busy));
    i2c_sensor_model #(.ADDRESS(7'h76),.IS_BMP(1)) bmp_model(.scl(scl),.sda(sda),.rst_n(rst),.inject_nack(nack),.inject_bad_crc(1'b0),
        .transactions(bmp_transactions),.measurements(bmp_samples),.last_command(bmp_command));
    i2c_sensor_model sht_model(.scl(scl),.sda(sda),.rst_n(rst),.inject_nack(nack),.inject_bad_crc(bad_crc),
        .transactions(sht_transactions),.measurements(sht_samples),.last_command(sht_command));
    task wr;input [31:0] a,d;input bad;begin
        @(negedge clk);cv=1;cw=1;ca=a;cd=d;#1;
        if(!(cr[0]||cr[1])||((ce[0]||ce[1])!==bad))$fatal(1,"cfg write %h error %b",a,ce);
        @(negedge clk);cv=0;cw=0;
    end endtask
    task read_eq;input [31:0] a,d;begin
        @(negedge clk);cv=1;cw=0;ca=a;#1;
        if((rd[31:0]|rd[63:32])!==d)$fatal(1,"cfg read %h got %h",a,rd);
        @(negedge clk);cv=0;
    end endtask
    integer bmp_beats=0,sht_beats=0,bmp_records=0,sht_records=0;
    integer expected_heater=0,heater_test;
    integer bpos=0,spos=0,blen=0;
    reg [197:0] held0,held1;
    reg stalled0=0,stalled1=0;
    wire [197:0] bundle0={mf[31:0],mc[31:0],ts[63:0],msg[15:0],src[15:0],ml[0],ms[0],mk[3:0],md[31:0]};
    wire [197:0] bundle1={mf[63:32],mc[63:32],ts[127:64],msg[31:16],src[31:16],ml[1],ms[1],mk[7:4],md[63:32]};
    always @(posedge clk)if(rst)begin
        if(stalled0&&(!mv[0]||bundle0!==held0))$fatal(1,"BMP stall mutation");
        if(stalled1&&(!mv[1]||bundle1!==held1))$fatal(1,"SHT stall mutation");
        stalled0=mv[0]&&!ready[0];held0=bundle0;stalled1=mv[1]&&!ready[1];held1=bundle1;
        if(mv[0]&&ready[0])begin
            if(src[15:0]!='h43||msg[15:0]!='h1100||mk[3:0]!=15||mc[31:0]!=32'hffffffff||mf[2:0]!=5)$fatal(1,"BMP metadata");
            if(bpos==0)begin if(!ms[0])$fatal(1,"BMP SOF");blen=(md[31:0]=='h00010001) ? 8 : 5;end
            if(blen==5)case(bpos)
                0:if(md[31:0]!='h00020001)$fatal(1,"BMP header");
                1:if(md[31:0]!='h04030101)$fatal(1,"BMP pressure tag");
                2:if(md[31:0]!='h123456)$fatal(1,"BMP pressure");
                3:if(md[31:0]!='h04030102)$fatal(1,"BMP temperature tag");
                4:if(md[31:0]!='habcdef)$fatal(1,"BMP temperature");
            endcase
            if(ml[0]!=(bpos==blen-1))$fatal(1,"BMP LAST");
            if(ml[0])begin bpos=0;bmp_records=bmp_records+1;end else bpos=bpos+1;
            bmp_beats=bmp_beats+1;
        end
        if(mv[1]&&ready[1])begin
            if(src[31:16]!='h44||msg[31:16]!='h1100||mk[7:4]!=15||mc[63:32]!=32'hffffffff||mf[34:32]!=5)$fatal(1,"SHT metadata");
            case(spos)
                0:if(md[63:32]!='h00030001||!ms[1])$fatal(1,"SHT header");
                1:if(md[63:32]!='h04070010)$fatal(1,"SHT T tag");
                2:if(md[63:32]!=42501)$fatal(1,"SHT temperature %d",md[63:32]);
                3:if(md[63:32]!='h04030011)$fatal(1,"SHT RH tag");
                4:if(md[63:32]!=56500)$fatal(1,"SHT RH %d",md[63:32]);
                5:if(md[63:32]!='h04030001)$fatal(1,"SHT status tag");
                6:if(md[63:32]!=expected_heater)$fatal(1,"SHT status");
            endcase
            if(ml[1]!=(spos==6))$fatal(1,"SHT LAST");
            if(ml[1])begin spos=0;sht_records=sht_records+1;end else spos=spos+1;
            sht_beats=sht_beats+1;
        end
    end
    integer before_b,before_s;reg [31:0] errors_seen;
    initial begin
        repeat(10)@(negedge clk);rst=1;repeat(10)@(negedge clk);
        if(DEVICES&1)begin wr('h6338,1,1);wr('h631c,18,1);wr('h6314,100,0);end
        if(DEVICES&2)begin wr('h641c,1,1);wr('h6418,3,1);wr('h6414,20,0);end
        if(DEVICES&1)wr('h6304,1,0);if(DEVICES&2)wr('h6404,1,0);
        ready=DEVICES;
        wait((!(DEVICES&1)||bmp_records>=3)&&(!(DEVICES&2)||sht_records>=3));
        if(DEVICES&2)begin
            read_eq('h6430,32'hbeef1234);
            for(heater_test=1;heater_test<=6;heater_test=heater_test+1)begin
                wr('h6404,0,0);repeat(1000)@(negedge clk);wait(levels[63:32]==0);
                expected_heater=heater_test;
                wr('h6414,12000,0);wr('h641c,heater_test,0);wr('h6404,1,0);
                before_s=sht_records;wait(sht_records>before_s);
            end
            wr('h6404,0,0);repeat(1000)@(negedge clk);wait(levels[63:32]==0);
            expected_heater=0;wr('h641c,0,0);wr('h6414,20,0);wr('h6404,1,0);
            bad_crc=1;before_s=sht_samples;
            wait(sht_samples>=before_s+3);wait(errs[33]);bad_crc=0;
        end
        nack=1;repeat(30000)@(negedge clk);nack=0;
        before_b=bmp_records;before_s=sht_records;
        wait((!(DEVICES&1)||bmp_records>before_b)&&(!(DEVICES&2)||sht_records>before_s));
        wait(busy);@(negedge clk);stuck_scl=1;repeat(21000)@(negedge clk);stuck_scl=0;
        before_b=bmp_records;before_s=sht_records;
        wait((!(DEVICES&1)||bmp_records>before_b)&&(!(DEVICES&2)||sht_records>before_s));
        ready=0;
        wait((DEVICES&2)?drops[63:32]>0:drops[31:0]>0);
        ready=DEVICES;repeat(1000)@(negedge clk);
        if(DEVICES&1)wr('h6304,2,0);if(DEVICES&2)wr('h6404,2,0);
        repeat(20)@(negedge clk);
        if(levels!=0||drops!=0)$fatal(1,"reset counters/FIFO");
        $display("I2C_SENSOR_REGRESSION_PASS devices=%0d bmp=%0d sht=%0d",DEVICES,bmp_records,sht_records);$finish;
    end
    initial begin #200000000;$fatal(1,"watchdog rv=%b done=%b err=%h BMP=%d SHT=%d",rv,done,errs,bmp_records,sht_records);end
endmodule
module tb_i2c_shared;i2c_shared_test #(.DEVICES(3))t();endmodule
module tb_bmp390_driver;i2c_shared_test #(.DEVICES(1))t();endmodule
module tb_sht45_driver;i2c_shared_test #(.DEVICES(2))t();endmodule
