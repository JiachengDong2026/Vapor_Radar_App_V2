`timescale 1ns/1ps
module tb_sdfm300_uart;
    reg mready=0;reg clk=0;always #20 clk=~clk;
    reg rst=0;wire rx,tx;
    reg cv=0,cw=1;reg [31:0] ca=0,cd=0;reg [3:0] strb=15;
    wire cr,ce;wire [31:0] rd;wire [3:0] code;
    wire mv,ms,ml;wire [31:0] md,mc,mf;wire [3:0] mk;
    wire [15:0] src,msg;wire [63:0] ts;reg [63:0] now=64'h123456789abcdef0;
    sdfm300_model model(.uart_rxd(rx));
    sdfm300_uart #(.SYS_CLK_HZ(25000000),.FIFO_DEPTH(6)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.uart_rxd(rx),.uart_txd(tx),
        .timestamp_now(now),.time_sync_valid(1'b1),.time_sync_seq(32'd1),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(strb),
        .cfg_ready(cr),.cfg_error(ce),.cfg_error_code(code),.cfg_rdata(rd),
        .m_valid(mv),.m_ready(mready),.m_data(md),.m_keep(mk),.m_sof(ms),.m_last(ml),
        .m_source_id(src),.m_msg_id(msg),.m_timestamp(ts),.m_cycle_id(mc),.m_flags(mf));
    always @(posedge clk)if(rst && tx!==1'b1)$fatal(1,"unsolicited device TX");
    task wr;input [31:0] a,d;input [3:0] expected;begin
        @(negedge clk);cv=1;cw=1;ca=a;cd=d;
        #1;if(!cr||code!==expected||ce!==(expected!=0))$fatal(1,"write %h code=%d expected=%d",a,code,expected);
        @(negedge clk);cv=0;repeat(2)@(negedge clk);
    end endtask
    task read_eq;input [31:0] a,d;begin
        @(negedge clk);cv=1;cw=0;ca=a;
        #1;if(!cr||ce||rd!==d)$fatal(1,"read %h got %h expected %h",a,rd,d);
        @(negedge clk);cv=0;cw=1;
    end endtask
    task hf;input [15:0] cm;input bad;begin
        model.distance_frame(cm,bad);repeat(20)@(negedge clk);
    end endtask
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
    integer j;
    reg [31:0] rates[0:6];
    initial begin
        rates[0]=9600;rates[1]=19200;rates[2]=38400;rates[3]=115200;
        rates[4]=230400;rates[5]=256000;rates[6]=460800;
        repeat(5)@(negedge clk);rst=1;
        read_eq('h6500,'h00450200);read_eq('h6510,460800);
        for(j=0;j<7;j=j+1)begin wr('h6510,rates[j],0);read_eq('h6510,rates[j]);end
        wr('h6510,500000,7);wr('h6514,2,5);wr('h6518,1,5);wr('h6524,0,5);
        wr('h6544,1,5);wr('h654c,10,5);wr('h6550,0,5);wr('h6558,203,5);
        wr('h6504,4,7);wr('h6548,2500,0);wr('h6504,1,0);
        wr('h6510,115200,8);hf(209,0);hf(209,0);hf(209,0);
        read_eq('h6538,1);read_eq('h6534,6);read_eq('h6528,3);
        mready=1;wait(beats==6);repeat(5)@(negedge clk);
        hf(209,1);read_eq('h652c,1);
        hf(16'hffff,0);read_eq('h6530,1);read_eq('h6520,0);
        read_eq('h651c,2090);if(!dut.online)$fatal(1,"noecho remains online");
        hf(209,0);wait(beats==9);
        wr('h653c,2500,0);repeat(2600)@(negedge clk);
        read_eq('h6520,0);read_eq('h6540,1);
        wr('h653c,25000000,0);wr('h6504,0,0);hf(209,0);
        if(beats!=9||dut.online||dut.distance_valid)$fatal(1,"disable");
        wr('h6504,2,0);read_eq('h6528,0);read_eq('h6538,0);read_eq('h6510,460800);
        wr('h6504,1,0);hf(209,0);wait(beats==12);
        $display("TB_SDFM300_UART_PASS baud/retired/cfg/noTX/backpressure/drop/noecho/timeout/disable/reset");$finish;
    end
    initial begin #30000000;$fatal(1,"watchdog");end
endmodule
