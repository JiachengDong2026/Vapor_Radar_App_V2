`timescale 1ns/1ps
module tb_epsilon_rs232;
    reg clk=0;always #20 clk=~clk;
    reg rst=0,rx=1,cv=0,cw=0,ready=0,sync_pulse=0;
    reg [31:0] ca=0,cd=0;wire cr,ce;wire [31:0] rd;wire [3:0] cfg_code;
    wire nav_valid;wire [815:0] nav_payload;wire [63:0] nav_timestamp;
    reg [815:0] expected_nav;integer nav_count=0,expected_nav_count=0;
    reg [63:0] now=0;always @(posedge clk)now<=now+1'b1;
    wire tx,mv,ms,ml,online,tag_valid;
    wire [31:0] md,mc,mf,errs,drops,level;
    wire [3:0] mk;wire [15:0] src,msg;wire [63:0] ts,tag;
    epsilon_rs232 #(.SYS_CLK_HZ(25000000))dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx),.uart_txd(tx),
        .timestamp_now(now),.time_sync_valid(1'b1),.time_sync_seq(32'd9),.sync_event_pulse(sync_pulse),
        .gnss_time_tag(tag),.gnss_time_tag_valid(tag_valid),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(4'hf),.cfg_ready(cr),.cfg_error(ce),.cfg_rdata(rd),.cfg_error_code(cfg_code),
        .nav_valid(nav_valid),.nav_payload(nav_payload),.nav_timestamp(nav_timestamp),
        .m_valid(mv),.m_ready(ready),.m_data(md),.m_keep(mk),.m_sof(ms),.m_last(ml),
        .m_source_id(src),.m_msg_id(msg),.m_timestamp(ts),.m_cycle_id(mc),.m_flags(mf),
        .online(online),.errors(errs),.drop_count(drops),.fifo_level(level));
    reg [7:0] bytes[0:271],golden[0:55],received[0:271];
    integer i,j,p,packets=0,tags=0,position=0;
    reg [7:0] c8;reg [15:0] c16;
    reg [197:0] held;reg stalled=0;
    wire [197:0] bundle={mf,mc,ts,msg,src,ml,ms,mk,md};
    function [7:0] crc8;input [7:0] c,d;reg [7:0] v;integer n;begin
        v=c^d;for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^8'h8c:v>>1;crc8=v;end endfunction
    function [15:0] crc16;input [15:0] c;input [7:0] d;reg [15:0] v;integer n;begin
        v=c^{d,8'd0};for(n=0;n<8;n=n+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc16=v;end endfunction
    task serial;input [7:0] data;integer n;begin
        rx=0;#2000;for(n=0;n<8;n=n+1)begin rx=data[n];#2000;end rx=1;#2000;
    end endtask
    task wr;input [31:0] a,d;input bad;begin
        @(negedge clk);cv=1;cw=1;ca=a;cd=d;#1;if(!cr||ce!==bad)$fatal(1,"cfg %h",a);
        if(bad)begin
            if(a[1:0]!=0 && cfg_code!=5)$fatal(1,"unaligned cfg code");
            else if(a==32'h6200 && cfg_code!=6)$fatal(1,"readonly cfg code");
            else if(a==32'h6210 && d<9600 && cfg_code!=7)$fatal(1,"range cfg code");
            else if(a==32'h6210 && d>=9600 && cfg_code!=8)$fatal(1,"busy cfg code");
        end
        @(negedge clk);cv=0;cw=0;
    end endtask
    task send_frame;input [7:0] id,len;input corrupt;integer n;reg [7:0] h;reg [15:0] c;begin
        if(id==8'h50 && len==102 && !corrupt)begin
            for(n=0;n<102;n=n+1)expected_nav[n*8+:8]=bytes[7+n];
            expected_nav_count=expected_nav_count+1;
        end
        bytes[0]='hfc;bytes[1]=id;bytes[2]=len;bytes[3]='h19;
        h=0;for(n=0;n<4;n=n+1)h=crc8(h,bytes[n]);bytes[4]=h;
        c=0;for(n=0;n<len;n=n+1)c=crc16(c,bytes[7+n]);bytes[5]=c[15:8];bytes[6]=c[7:0]^corrupt;
        bytes[len+7]='hfd;for(n=0;n<len+8;n=n+1)serial(bytes[n]);
        repeat(10)@(negedge clk);
    end endtask
    always @(posedge clk)if(rst)begin
        if(nav_valid)begin
            nav_count=nav_count+1;
            if(nav_payload!==expected_nav || nav_timestamp==0)$fatal(1,"nav snapshot");
        end
        if(stalled&&(!mv||bundle!==held))$fatal(1,"stall mutation");stalled=mv&&!ready;held=bundle;
        if(tag_valid)begin tags=tags+1;if(tag!=64'd1700000000123456)$fatal(1,"UTC units %d",tag);end
        if(mv&&ready)begin
            if(src!='h42||msg!='h1200||mc!=32'hffffffff||mf[2:0]!=5)$fatal(1,"metadata");
            if(ms!=(position==0))$fatal(1,"SOF");
            for(j=0;j<4;j=j+1)if(mk[j])begin received[position]=md[j*8+:8];position=position+1;end
            if(ml)begin
                if(received[0]!='hfc||received[position-1]!='hfd||position!=received[2]+8)$fatal(1,"frame size");
                c8=0;for(j=0;j<4;j=j+1)c8=crc8(c8,received[j]);if(c8!=received[4])$fatal(1,"header CRC");
                c16=0;for(j=7;j<position-1;j=j+1)c16=crc16(c16,received[j]);if(c16!={received[5],received[6]})$fatal(1,"payload CRC");
                if(packets==0)for(j=0;j<56;j=j+1)if(received[j]!=golden[j])$fatal(1,"manual golden byte %d",j);
                packets=packets+1;position=0;
            end
        end
    end
    initial begin
        // Literal vector from EPSILON manual p191, independent of test CRC builder.
        {golden[0],golden[1],golden[2],golden[3],golden[4],golden[5],golden[6],golden[7],
         golden[8],golden[9],golden[10],golden[11],golden[12],golden[13],golden[14],golden[15],
         golden[16],golden[17],golden[18],golden[19],golden[20],golden[21],golden[22],golden[23],
         golden[24],golden[25],golden[26],golden[27],golden[28],golden[29],golden[30],golden[31],
         golden[32],golden[33],golden[34],golden[35],golden[36],golden[37],golden[38],golden[39],
         golden[40],golden[41],golden[42],golden[43],golden[44],golden[45],golden[46],golden[47],
         golden[48],golden[49],golden[50],golden[51],golden[52],golden[53],golden[54],golden[55]}=
         448'hfc41308da58ff16605cebc3ec117bcf229f73cacd8a8bd0248d4bc84aab5408b10743fc1ea30bd748d70b8bceb98bec2dc4b0100000000fd;
        for(i=0;i<272;i=i+1)bytes[i]=0;
        repeat(10)@(negedge clk);rst=1;
        wr('h6201,0,1);wr('h6200,0,1);wr('h6210,100,1);
        wr('h6210,500000,0);wr('h6204,1,0);wr('h6210,921600,1);
        for(i=0;i<56;i=i+1)serial(golden[i]);repeat(20)@(negedge clk);
        ready=1;wait(packets==1);
        // 0x51 alone has no independent valid bit: reject until initialized status.
        {bytes[10],bytes[9],bytes[8],bytes[7]}=32'd1700000000;
        {bytes[14],bytes[13],bytes[12],bytes[11]}=32'd123456;
        send_frame('h51,8,0);if(tags!=0)$fatal(1,"unqualified UTC");
        for(i=7;i<109;i=i+1)bytes[i]=0;
        bytes[9]=8'h08;
        {bytes[16],bytes[15],bytes[14],bytes[13]}=32'd1700000000;
        {bytes[20],bytes[19],bytes[18],bytes[17]}=32'd123456;
        send_frame('h50,102,0);if(tags!=1)$fatal(1,"UTC status frame not tagged");
        send_frame('h50,102,1);if(tags!=1)$fatal(1,"bad CRC tagged");
        {bytes[20],bytes[19],bytes[18],bytes[17]}=32'd1000000;
        send_frame('h50,102,0);if(tags!=1)$fatal(1,"invalid usec tagged");
        // Maximum payload, raw bytes remain intact across the partial final beat.
        for(i=7;i<262;i=i+1)bytes[i]=i;
        send_frame('h40,255,0);
        repeat(100)@(negedge clk);
        if(packets!=5)$fatal(1,"valid packet count %d",packets);
        ready=0;
        for(p=0;p<6;p=p+1)send_frame('h40,255,0);
        if(drops!=3)$fatal(1,"atomic overflow count %d",drops);
        ready=1;repeat(500)@(negedge clk);
        if(packets!=8)$fatal(1,"truncated overflow record");
        wr('h6214,0,0);wr('h6218,0,0);send_frame('h40,255,0);repeat(100)@(negedge clk);
        if(packets!=8)$fatal(1,"filter");
        wr('h621c,0,0);for(i=7;i<109;i=i+1)bytes[i]=0;bytes[22]=8'h42;
        send_frame('h50,102,0);send_frame('h50,102,1);
        if(nav_count!=expected_nav_count || nav_count!=3 || packets!=8)$fatal(1,"nav independent mask/forward/CRC");
        @(negedge clk);sync_pulse=1;@(negedge clk);sync_pulse=0;
        serial('hfc);serial('h41);repeat(260000)@(negedge clk);if(!errs[0])$fatal(1,"gap timeout");
        wr('h6204,2,0);repeat(10)@(negedge clk);if(level||drops||tag_valid)$fatal(1,"reset");
        $display("EPSILON_FDILINK_REGRESSION_PASS packets=%0d UTC=%0d",packets,tags);$finish;
    end
    initial begin #100000000;$fatal(1,"watchdog packets=%d errors=%h",packets,errs);end
endmodule
