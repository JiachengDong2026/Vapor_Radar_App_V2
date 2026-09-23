`timescale 1ns/1ps
module tb_tfa1500_uart;
    reg mready=0;
    reg clk=0; always #20 clk=~clk;
    reg rst=0,hfrx=1,lfrx=1;
    wire tx;
    reg cv=0,cw=1;
    reg [31:0] ca=0,cd=0;reg [3:0] strb=15;
    wire cr,ce;wire [31:0] rd;
    wire mv,ms,ml;wire [31:0] md,mc,mf;wire [3:0] mk;
    wire [15:0] src,msg;wire [63:0] ts;
    reg [63:0] now=64'h123456789abcdef0;
    tfa1500_uart #(.SYS_CLK_HZ(25000000),.FIFO_DEPTH(6)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.hf_rxd(hfrx),.lf_rxd(lfrx),.uart_txd(tx),
        .timestamp_now(now),.time_sync_valid(1'b1),.time_sync_seq(32'd1),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strb),
        .cfg_ready(cr),.cfg_error(ce),.cfg_rdata(rd),
        .m_valid(mv),.m_ready(mready),.m_data(md),.m_keep(mk),.m_sof(ms),.m_last(ml),
        .m_source_id(src),.m_msg_id(msg),.m_timestamp(ts),.m_cycle_id(mc),.m_flags(mf));
    task wr;input [31:0] a,d;input bad;begin
        @(negedge clk);cv=1;cw=1;ca=a;cd=d;
        #1;if(!cr || ce!==bad) $fatal(1,"write %h error=%b expected=%b",a,ce,bad);
        @(negedge clk);cv=0;repeat(2) @(negedge clk);
    end endtask
    task read_eq;input [31:0] a,d;begin
        @(negedge clk);cv=1;cw=0;ca=a;
        #1;if(!cr || ce || rd!==d) $fatal(1,"read %h got %h expected %h",a,rd,d);
        @(negedge clk);cv=0;cw=1;
    end endtask
    task serial;input low;input [7:0] b;integer j;begin
        if(low) lfrx=0;else hfrx=0;#2000;
        for(j=0;j<8;j=j+1) begin if(low) lfrx=b[j];else hfrx=b[j];#2000;end
        if(low) lfrx=1;else hfrx=1;#2000;
    end endtask
    task hf;input [23:0] v;input bad;reg [7:0] sum;begin
        sum=v[7:0]+v[15:8]+v[23:16];
        serial(0,'h5c);serial(0,v[7:0]);serial(0,v[15:8]);serial(0,v[23:16]);serial(0,(~sum)^bad);
        repeat(20) @(negedge clk);
    end endtask
    task lf;begin
        serial(1,'h55);serial(1,2);serial(1,7);serial(1,0);
        serial(1,0);serial(1,0);serial(1,209);serial(1,0);serial(1,80);serial(1,25);
        serial(1,8'h55^2^7^209^80^25);repeat(20) @(negedge clk);
    end endtask
    reg [7:0] commands[0:127];integer ncmd=0,bitno;
    reg [7:0] command_byte;
    initial forever begin
        @(negedge tx);#3000;
        for(bitno=0;bitno<8;bitno=bitno+1) begin command_byte[bitno]=tx;#2000;end
        if(tx!==1) $fatal(1,"command stop");
        commands[ncmd]=command_byte;ncmd=ncmd+1;
    end
    task check_command;input integer first;input [63:0] expected;input integer count;
        integer q;begin
        for(q=0;q<count;q=q+1) if(commands[first+q]!==((expected>>((7-q)*8))&255))
            $fatal(1,"command byte %0d got %h",first+q,commands[first+q]);
    end endtask
    initial begin #30000000;$fatal(1,"watchdog");end

    integer beats=0;
    reg [229:0] held;reg stalled=0;
    wire [229:0] bundle={mf,mc,ts,msg,src,ml,ms,mk,md};
    always @(posedge clk) if(rst) begin
        if(stalled && (!mv || bundle!==held)) $fatal(1,"backpressure mutation");
        stalled=mv&&!mready;held=bundle;
        if(mv&&mready) begin
            if(mk!=15 || src!='h45 || msg!='h1100 || ts!=now || mc!=32'hffffffff)
                $fatal(1,"metadata");
            case(beats%3)
                0:if(md!='h00010001 || !ms || ml) $fatal(1,"record header");
                1:if(md!='h04030013 || ms || ml) $fatal(1,"TLV");
                2:if(md!=2090 || ms || !ml) $fatal(1,"distance");
            endcase
            beats=beats+1;
        end
    end
    initial begin
        repeat(5) @(negedge clk);rst=1;
        read_eq('h6500,'h00450100);
        @(negedge clk);cv=1;ca='h6400;#1;if(cr || ce) $fatal(1,"foreign page");
        @(negedge clk);cv=0;
        wr('h6510,1,1);wr('h651c,0,1);wr('h6580,0,1);wr('h6511,500000,1);
        strb=1;wr('h6558,'he8,0);read_eq('h6558,'he8);strb=15;
        wr('h6544,100,0);wr('h6548,2500,0);
        wr('h6504,1,0);
        wait(ncmd==8);#4000;check_command(0,64'h55aacbccccccccfb,8);
        hf(209,0);hf(209,0);hf(209,0);
        read_eq('h6538,1);read_eq('h6534,6);read_eq('h6528,3);
        mready=1;wait(beats==6);repeat(5) @(negedge clk);
        hf(209,1);read_eq('h652c,1);
        hf('h3fffff,0);read_eq('h6530,1);read_eq('h6520,0);
        hf(209,0);wait(beats==9);
        wr('h653c,2500,0);repeat(2600) @(negedge clk);
        read_eq('h6520,0);read_eq('h6540,1);
        wr('h653c,25000000,0);
        wr('h6514,1,0);
        wait(ncmd==22);#4000;
        check_command(8,64'h55aaccccccccccfc,8);
        check_command(16,64'h5502022000750000,6);
        lf;wait(beats==12);
        wr('h6518,3,0);wait(ncmd==28);#4000;
        check_command(22,64'h5503020000540000,6);
        wr('h6518,4,0);wait(ncmd==34);#4000;
        check_command(28,64'h55e8020000bf0000,6);
        wr('h6504,0,0);wait(ncmd==40);#10000;
        check_command(34,64'h5500020000570000,6);
        wr('h6504,2,0);read_eq('h6528,0);read_eq('h6538,0);
        wr('h6544,100,0);wr('h6504,1,0);wait(ncmd==48);#4000;
        hf(209,0);wait(beats==15);
        $display("TB_TFA1500_UART_PASS");$finish;
    end
endmodule
