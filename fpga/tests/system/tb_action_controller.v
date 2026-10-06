`timescale 1ns/1ps
`default_nettype none
module tb_action_controller;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,av=0;
    reg [15:0] code=0,source=0;reg [127:0] args=0;
    wire ar,bv,bw,ce,running,busy;wire [31:0] status,ba,bd;wire [3:0] bs;wire [1:0] flush;
    reg [1:0] idle=3;reg sensor_idle=1,stall=0,fail_ack=0,inject_error=0;
    integer ticks=0,writes=0,i,p,base,oldwrites,start_tick;
    reg [31:0] memory[0:16383],trace_addr[0:4095],trace_data[0:4095];
    integer pending_timer[0:255];reg ack_pending[0:255];
    wire br=bv && !stall && ticks%3!=0;
    assign ce=inject_error && bw;
    wire [31:0] rd=memory[ba[15:2]];
    reg [3:0] injected_code=5;integer reason_index;
    reg held=0;reg [68:0] held_bus;
    action_controller #(.CFG_TIMEOUT(12),.ACTION_TIMEOUT(5000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.action_valid(av),.action_ready(ar),.action_status(status),.action_code(code),.action_source(source),.action_args(args),
        .cfg_valid(bv),.cfg_write(bw),.cfg_addr(ba),.cfg_wdata(bd),.cfg_wstrb(bs),.cfg_ready(br),.cfg_error(ce),.cfg_error_code(injected_code),.cfg_rdata(rd),
        .channel_datapath_idle(idle),.sensor_datapath_idle(sensor_idle),.stop_flush(flush),.acquisition_running(running),.busy(busy));
    always @(negedge clk)ticks=ticks+1;
    always @(posedge clk)begin
        if(rst)begin
            // The total action deadline legally withdraws an unaccepted request.
            if(held && av && !ar && dut.action_ticks<4999 && (!bv || held_bus!=={bw,ba,bd,bs}))$fatal(1,"cfg operands changed under stall");
            if(dut.action_ticks>=4999 && bv)$fatal(1,"cfg request survives total action deadline");
            held=bv&&!br;held_bus={bw,ba,bd,bs};
            for(p=0;p<256;p=p+1)if(pending_timer[p]>0)begin
                pending_timer[p]=pending_timer[p]-1;
                if(pending_timer[p]==0)begin
                    memory[p*64+2]=(memory[p*64+2]&32'hfffffff3)|
                        ((p==8'h20 || p==8'h21) ? ((memory[1][0] && memory[(p+16)*64+1][0]) ? 2 : 0) : 2);
                    if(ack_pending[p])begin
                        if(!fail_ack)begin
                            memory[p*64+18]=memory[p*64+18]+1;
                            memory[p*64+16]=memory[p*64+(p==8'h61 ? 13 : 8)];
                        end
                        ack_pending[p]=0;
                    end
                end
            end
            if(bv&&br&&bw&&!ce)begin
                if(bs!=15 || ba[1:0]!=0 || ba[31:16]!=0)$fatal(1,"bad bus shape");
                trace_addr[writes]=ba;trace_data[writes]=bd;writes=writes+1;
                if(ba[7:0]==4)begin
                    memory[ba[15:2]]=bd&1;memory[{ba[15:8],6'd2}][0]=bd[0];
                    if(bd[2])begin
                        if(ba==32'h3004 || ba==32'h3104)begin
                            if(memory[(ba-32'h1000)>>2]!=0 || memory[(ba+4)>>2][3])$fatal(1,"DAC commit while WMS active or DAC busy");
                        end
                        if(ba==32'h2004 || ba==32'h2104)begin
                            if(memory[(ba+32'h1004)>>2][2:1]!=1)$fatal(1,"WMS commit before DAC ready");
                        end
                        pending_timer[ba[15:8]]=11;
                        memory[(ba+4)>>2]=(memory[(ba+4)>>2]&32'hfffffffd)|4;
                        if(ba==32'h6104 || ba==32'h6604)ack_pending[ba[15:8]]=1;
                    end
                end else if(ba==32'h672c)begin
                    if(bd==1)begin memory[32'h6708>>2]=9;pending_timer[8'h67]=30;end
                    else if(bd==2)pending_timer[8'h67]=8;
                    else if(bd==3)memory[32'h6724>>2]=0;
                end else if(ba[7:0]==12)memory[ba[15:2]]=memory[ba[15:2]]&~bd;
                else memory[ba[15:2]]=bd;
            end
        end
    end
    task begin_action;
        input [15:0] c,s;input [127:0] a;
        begin @(negedge clk);code=c;source=s;args=a;av=1;end
    endtask
    task end_action;
        input [31:0] expected;
        begin wait(ar);@(negedge clk);if(status!==expected)$fatal(1,"status code=%h source=%h got=%0d exp=%0d pc=%0d",code,source,status,expected,dut.pc);
            av=0;repeat(2)@(negedge clk);end
    endtask
    task action;
        input [15:0] c,s;input [127:0] a;input [31:0] expected;
        begin begin_action(c,s,a);end_action(expected);end
    endtask
    task expect_write;
        input integer n;input [31:0] a,d;
        begin if(trace_addr[n]!==a || trace_data[n]!==d)$fatal(1,"write[%0d] got=%h/%h exp=%h/%h",n,trace_addr[n],trace_data[n],a,d);end
    endtask
    initial begin
        for(i=0;i<16384;i=i+1)memory[i]=0;
        for(i=0;i<256;i=i+1)begin pending_timer[i]=0;ack_pending[i]=0;memory[i*64+2]=2;end
        memory[32'h202c>>2]=100000;memory[32'h212c>>2]=100000;
        repeat(5)@(negedge clk);rst=1;
        // Every preflight runs before any enable write.
        memory[32'h4008>>2]=0;action(6,1,128'h00000000000000000001000000000000,11);
        if(writes!=0)$fatal(1,"preflight wrote before ADC ready");
        memory[32'h4008>>2]=2;memory[32'h202c>>2]=0;
        action(6,1,128'h00000000000000000001000000000000,11);
        if(writes!=0)$fatal(1,"preflight wrote before WMS actual rate");memory[32'h202c>>2]=100000;
        action(6,1,128'h00000000000000000001000000000000,0);
        if(writes!=5||!running)$fatal(1,"START count/running");
        expect_write(0,4,1);expect_write(1,32'h4004,1);expect_write(2,32'h5004,1);expect_write(3,32'h3004,1);expect_write(4,32'h2004,1);
        // Combined commit saves the enabled WMS state and waits out DAC activity.
        base=writes;memory[32'h3008>>2]=10;pending_timer[8'h30]=24;
        action(5,16'h10,128'h00000000000000000000000000010000,0);
        if(writes-base!=4)$fatal(1,"combined commit write count");
        expect_write(base,32'h2004,0);expect_write(base+1,32'h3004,5);expect_write(base+2,32'h2004,4);expect_write(base+3,32'h2004,1);
        // STOP disables WMS before its consumers and waits both timer and idle.
        base=writes;idle=2;start_tick=ticks;
        begin_action(7,1,128'h00000000000000000001000000000000);
        wait(flush==1);repeat(2100)@(negedge clk);
        if(ar)$fatal(1,"STOP ignored datapath busy");idle=3;end_action(0);
        if(ticks-start_tick<2048||running)$fatal(1,"STOP timing/running");
        expect_write(base,32'h2004,0);expect_write(base+1,32'h4004,0);expect_write(base+2,32'h5004,0);expect_write(base+3,32'h3004,0);
        base=writes;action(5,16'h10,128'h00000000000000000000000000010000,0);expect_write(base+3,32'h2004,0);
        base=writes;action(5,1,128'h00000000000000000002000100000000,0);
        expect_write(base,32'h4004,4);expect_write(base+1,32'h5104,4);
        // HMP/RD active values only advance when the device model ACKs the write.
        action(11,16'h41,{64'd0,32'h44812345,32'd16},0);
        if(memory[32'h6140>>2]!=32'h44812345 || memory[32'h6148>>2]!=1)$fatal(1,"HMP ACK contract");
        pending_timer[8'h61]=15;ack_pending[8'h61]=1;memory[32'h6108>>2]=4;
        action(11,16'h41,{64'd0,32'h44823456,32'd16},0);
        if(memory[32'h6140>>2]!=32'h44823456 || memory[32'h6148>>2]!=3)$fatal(1,"queued HMP commit ACK accounting");
        memory[32'h6640>>2]=7;fail_ack=1;action(11,16'h46,{64'd0,32'd25000000,32'd17},14);
        if(memory[32'h6640>>2]!=7 || memory[32'h6648>>2]!=0)$fatal(1,"RD promoted without ACK");fail_ack=0;
        action(11,16'h46,{64'd0,32'd26000000,32'd17},0);
        if(memory[32'h6640>>2]!=26000000)$fatal(1,"RD active value");
        base=writes;action(5,1,128'd2,0);expect_write(base,32'h6104,4);
        action(11,16'h41,{64'd0,32'd1,32'd1},0);
        base=writes;action(11,16'h41,128'd3,0);expect_write(base,32'h6104,9);
        base=writes;action(11,16'h41,128'd4,0);expect_write(base,32'h6104,2);
        base=writes;action(8,2,128'd4,0);expect_write(base,32'h1004,2);
        memory[32'h610c>>2]=32'h55;action(9,16'h41,128'd2,0);
        if(memory[32'h610c>>2]!=0)$fatal(1,"CLEAR_ERROR");
        base=writes;action(10,1,{64'h0000000100000000,64'h0001000000000000},0);
        if(writes-base!=6)$fatal(1,"MASK writes");expect_write(base+4,32'h403c,1);expect_write(base+5,32'h413c,0);
        base=writes;action(11,16'h45,{64'd0,32'd1,32'd32},0);expect_write(base,32'h6514,1);
        base=writes;action(11,16'h45,{64'd0,32'd2,32'd33},0);expect_write(base,32'h6518,2);
        base=writes;action(12,16'h47,{64'd0,32'hffffffef,32'd1},0);
        expect_write(base,32'h6710,32'hffffffef);expect_write(base+3,32'h672c,1);
        if(!memory[32'h6708>>2][3])$fatal(1,"MOVE should acknowledge accepted motion");
        action(12,16'h47,128'd2,0);if(memory[32'h6708>>2][3])$fatal(1,"MOTOR STOP before idle");
        memory[32'h6724>>2]=5;action(12,16'h47,128'd3,0);if(memory[32'h6724>>2]!=0)$fatal(1,"motor zero");
        action(13,2,128'd2,0);if(memory[32'h1004>>2]!=1)$fatal(1,"time rearm enable");
        action(13,2,{64'd0,32'd1,32'd3},0);if(memory[32'h1024>>2]!=1)$fatal(1,"time edge");
        action(13,2,{64'd0,32'd1000,32'd4},0);if(memory[32'h1028>>2]!=1000)$fatal(1,"time timeout");
        // Validation, downstream error, stall timeout and cancellation have no new writes.
        oldwrites=writes;action(5,16'h50,128'h10000,4);action(6,1,{32'd0,32'd1,64'h10000},13);
        action(10,1,{64'd1,64'd0},7);action(11,16'h45,{64'd0,32'd5,32'd33},7);action(16'h99,1,0,1);
        if(writes!=oldwrites)$fatal(1,"invalid action side effects");
        inject_error=1;
        for(reason_index=5;reason_index<=15;reason_index=reason_index+1)begin
            injected_code=reason_index;action(13,2,{64'd0,32'd1,32'd3},reason_index);
        end
        inject_error=0;injected_code=5;
        stall=1;action(13,2,{64'd0,32'd1,32'd3},9);stall=0;
        stall=1;begin_action(13,2,{64'd0,32'd1,32'd3});repeat(5)@(negedge clk);av=0;repeat(3)@(negedge clk);stall=0;
        if(busy||bv||writes!=oldwrites)$fatal(1,"cancellation did not release bus");
        memory[32'h3008>>2]=0;action(5,16'h10,128'h10000,9);
        $display("tb_action_controller_PASS preflight start_stop_order combined_commit ack_gated_active masks sensors motor time timeout cancel");$finish;
    end
    initial begin #2000000;$fatal(1,"test timeout");end
endmodule
`default_nettype wire
