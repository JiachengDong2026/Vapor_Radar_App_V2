`timescale 1ns/1ps
module tb_lc_uart_bridge;
    reg clk=0; always #5 clk=~clk;
    reg rst=0, system_enable=1, rxd=1, cv=0, cw=0;
    reg [31:0] ca=0, cd=0; reg [3:0] cs=15;
    wire cr, ce, txd; wire [3:0] ec; wire [31:0] rd, drops;
    reg [31:0] value;
    integer checked=0, received=0, expected_bits=8, expected_stops=1, expected_parity=0;
    reg [7:0] expected_tx[0:31];
    reg [7:0] observed; reg parity;
    integer j;
    lc_uart_bridge #(.SYS_CLK_HZ(1600000),.FIFO_DEPTH(4)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.system_enable(system_enable),.rxd(rxd),.txd(txd),
        .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(cd),.cfg_wstrb(cs),
        .cfg_ready(cr),.cfg_error(ce),.cfg_error_code(ec),.cfg_rdata(rd),.drop_count(drops));
    // Independent pin-level decoder, deliberately not another uart_rx instance.
    initial forever begin
        @(negedge txd); #160;
        if(txd!==0)$fatal(1,"TX start bit");
        observed=0;parity=0;
        for(j=0;j<expected_bits;j=j+1)begin
            #320;observed[j]=txd;parity=parity^txd;
        end
        if(expected_parity!=0)begin
            #320;if(txd!==(parity^(expected_parity==2)))$fatal(1,"TX parity");
        end
        repeat(expected_stops)begin #320;if(txd!==1)$fatal(1,"TX stop bit");end
        if(observed!==expected_tx[received])$fatal(1,"TX order byte %d got %h expected %h",received,observed,expected_tx[received]);
        received=received+1;
    end
    task access;
        input wr;input [31:0] a,d;input [3:0] strb,code;
        begin
            @(negedge clk);cv=1;cw=wr;ca=a;cd=d;cs=strb;#1;
            if(!cr || ec!==code || ce!==(code!=0))$fatal(1,"cfg %h wr=%b code %d expected %d",a,wr,ec,code);
            value=rd;
            @(negedge clk);cv=0;cw=0;ca=0;cd=0;cs=15;
            checked=checked+1;
        end
    endtask
    task write_reg;input [7:0] a;input [31:0] d;begin access(1,32'h6800+a,d,15,0);end endtask
    task read_reg;input [7:0] a;input [31:0] expected;begin
        access(0,32'h6800+a,0,15,0);
        if(value!==expected)$fatal(1,"read %h got %h expected %h",a,value,expected);
    end endtask
    task inject;
        input [7:0] data; input integer bits,mode,stops;input bad_parity,bad_stop;
        integer b;reg p;
        begin
            @(negedge clk);rxd=0;#320;p=0;
            for(b=0;b<bits;b=b+1)begin rxd=data[b];p=p^data[b];#320;end
            if(mode!=0)begin rxd=p^(mode==2)^bad_parity;#320;end
            repeat(stops)begin rxd=!bad_stop;#320;end
            rxd=1;#640;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;repeat(3)@(negedge clk);
        read_reg(0,32'h00480100);read_reg(4,0);read_reg(16,115200);read_reg(20,32'h108);
        if(txd!==1)$fatal(1,"default idle");
        access(1,32'h6818,8'h42,15,11);access(0,32'h681c,0,15,11);
        access(1,32'h6800,1,15,6);access(1,32'h6808,1,15,6);
        access(1,32'h681c,1,15,6);access(0,32'h687c,0,15,5);
        access(1,32'h6811,1,15,5);access(1,32'h6810,0,15,7);
        access(1,32'h6810,100001,15,7);access(1,32'h6810,50000,1,7);
        access(1,32'h6814,32'h10a,15,7);access(1,32'h6804,4,15,7);
        write_reg(16,50000);write_reg(4,1);
        access(1,32'h6810,40000,15,8);access(1,32'h6818,256,15,7);
        expected_tx[0]=0;expected_tx[1]=8'h55;expected_tx[2]=8'haa;expected_tx[3]=8'hff;
        fork
            begin write_reg(24,0);write_reg(24,8'h55);write_reg(24,8'haa);write_reg(24,8'hff);end
            begin inject(8'h81,8,0,1,0,0);inject(8'h12,8,0,1,0,0);end
        join
        wait(received==4);#500;
        read_reg(40,4);read_reg(44,2);read_reg(36,2);
        read_reg(28,8'h81);read_reg(28,8'h12);read_reg(36,0);
        access(0,32'h681c,0,15,11);
        // RX overflow: oldest bytes retained, new byte dropped and counted.
        inject(1,8,0,1,0,0);inject(2,8,0,1,0,0);inject(3,8,0,1,0,0);
        inject(4,8,0,1,0,0);inject(5,8,0,1,0,0);
        read_reg(36,4);read_reg(48,1);read_reg(12,4);
        read_reg(28,1);read_reg(28,2);read_reg(28,3);read_reg(28,4);
        write_reg(12,4);read_reg(12,0);
        // Full TX FIFO must reject without corrupting queued bytes.
        expected_tx[4]=10;expected_tx[5]=11;expected_tx[6]=12;expected_tx[7]=13;expected_tx[8]=14;
        write_reg(24,10);repeat(3)@(negedge clk);
        write_reg(24,11);write_reg(24,12);write_reg(24,13);write_reg(24,14);
        access(1,32'h6818,15,15,8);
        wait(received==9);#500;
        // Change format only while disabled: 7E2 then 8O1.
        write_reg(4,0);repeat(4)@(negedge clk);write_reg(20,32'h217);
        expected_bits=7;expected_parity=1;expected_stops=2;expected_tx[9]=8'h35;
        write_reg(4,1);write_reg(24,8'h35);inject(8'h45,7,1,2,0,0);
        wait(received==10);#500;read_reg(28,8'h45);
        inject(8'h26,7,1,2,1,0);read_reg(28,32'h126);read_reg(52,1);read_reg(12,128);
        write_reg(4,0);repeat(4)@(negedge clk);write_reg(20,32'h128);
        expected_bits=8;expected_parity=2;expected_stops=1;expected_tx[10]=8'hc3;
        write_reg(4,1);write_reg(24,8'hc3);inject(8'hd4,8,2,1,0,1);
        wait(received==11);#500;read_reg(28,32'h2d4);read_reg(56,1);
        // FIFO clear retains diagnostics and baud; local reset clears diagnostics.
        inject(8'h40,8,2,1,0,0);write_reg(4,9);repeat(4)@(negedge clk);read_reg(36,0);read_reg(48,1);
        write_reg(4,2);repeat(4)@(negedge clk);read_reg(4,0);read_reg(40,0);read_reg(44,0);read_reg(12,0);read_reg(16,50000);
        // Global gate aborts/flushes without changing the configured enable.
        write_reg(4,1);inject(8'h40,8,2,1,0,0);
        system_enable=0;repeat(8)@(negedge clk);
        read_reg(36,0);read_reg(4,1);access(1,32'h6818,1,15,11);
        system_enable=1;repeat(8)@(negedge clk);
        read_reg(4,1);inject(8'h41,8,2,1,0,0);read_reg(28,8'h41);
        // Reset during reception discards a partial frame and restores idle TX.
        write_reg(4,1);@(negedge clk);rxd=0;#700;rst=0;#40;rst=1;rxd=1;#1000;
        read_reg(4,0);read_reg(36,0);read_reg(16,115200);
        if(txd!==1)$fatal(1,"reset TX idle");
        $display("tb_lc_uart_bridge_PASS checked=%0d tx=%0d full_duplex_formats_errors_overflow_reset",checked,received);$finish;
    end
    initial begin #2000000;$fatal(1,"timeout checked=%0d tx=%0d",checked,received);end
endmodule
