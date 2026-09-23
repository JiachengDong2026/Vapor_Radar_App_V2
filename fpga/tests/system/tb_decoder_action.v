`timescale 1ns/1ps
`default_nettype none
// Real decoder/action pair. The cfg model deliberately implements commit
// pending and device ACK separately; receiving a write is not completion.
module tb_decoder_action;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0;reg [15:0] source=1,code=3;
    reg [31:0] sequence=0,length=0,payload[0:1100];
    wire done;wire [31:0] prw;reg [31:0] prd=0;
    wire dv,dw,av,ar,abv,abw;wire [31:0] da,dd,aba,abd,ast;
    wire [3:0] ds,abs;wire [15:0] ac,asrc;wire [127:0] aa;
    wire mv,ms,ml;reg mr=0;wire [31:0] md,mseq;wire [3:0] mk;
    wire [15:0] msrc,mid;wire [63:0] mt;wire [31:0] mc,mf;wire [7:0] ft;wire seqv;
    wire [1:0] flush;wire running,busy;
    wire bv=dv||abv,bw=abv?abw:dw;wire [31:0] ba=abv?aba:da,bd=abv?abd:dd;
    wire [3:0] bs=abv?abs:ds;
    integer ticks=0,writes=0,reads=0,actions=0,replies=0,i,p,start_w,start_r,start_a,expected_status=0;
    reg bus_stall=0,action_stall=0,fail_ack=0,stick_pending=0,inject_error=0;
    reg [31:0] memory[0:16383],trace_addr[0:255],trace_data[0:255];
    integer pending[0:255];reg ack_pending[0:255];
    wire br=bv&&!bus_stall && !(action_stall&&abv) && ticks%3!=0;
    wire be=inject_error && bw;
    wire [31:0] rd=memory[ba[15:2]];
    reg [3:0] injected_code=5;integer reason_index;
    reg held=0;reg [73:0] held_response;
    // Deliberately shorter than the controller to exercise decoder cancellation.
    cmd_decoder #(.CFG_TIMEOUT(12),.ACTION_TIMEOUT(400)) decoder(
      .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(64'h123456789abcdef0),
      .command_valid(cv),.command_done(done),.command_status(32'd0),.command_sequence(sequence),
      .command_payload_bytes(length),.command_source(source),.command_id(code),
      .payload_read_word(prw),.payload_read_data(prd),.cfg_valid(dv),.cfg_write(dw),.cfg_addr(da),
      .cfg_wdata(dd),.cfg_wstrb(ds),.cfg_ready(br&&!abv),.cfg_error(be),.cfg_error_code(injected_code),.cfg_rdata(rd),
      .action_valid(av),.action_ready(ar),.action_status(ast),.action_code(ac),.action_source(asrc),.action_args(aa),
      .m_valid(mv),.m_ready(mr),.m_data(md),.m_keep(mk),.m_sof(ms),.m_last(ml),.m_source_id(msrc),.m_msg_id(mid),
      .m_timestamp(mt),.m_cycle_id(mc),.m_flags(mf),.m_frame_type(ft),.m_sequence(mseq),.m_sequence_valid(seqv));
    action_controller #(.CFG_TIMEOUT(12),.ACTION_TIMEOUT(500),.STOP_DRAIN_TICKS(8)) controller(
      .sys_clk(clk),.rst_sys_n(rst),.action_valid(av),.action_ready(ar),.action_status(ast),
      .action_code(ac),.action_source(asrc),.action_args(aa),.cfg_valid(abv),.cfg_write(abw),.cfg_addr(aba),
      .cfg_wdata(abd),.cfg_wstrb(abs),.cfg_ready(br&&abv),.cfg_error(be),.cfg_error_code(injected_code),.cfg_rdata(rd),
      .channel_datapath_idle(2'b11),.sensor_datapath_idle(1'b1),.stop_flush(flush),.acquisition_running(running),.busy(busy));
    always @(negedge clk)begin ticks=ticks+1;mr=ticks%7<4;end
    always @(posedge clk)begin
        prd<=payload[prw];
        if(rst)begin
            if(dv&&abv)$fatal(1,"decoder/action cfg overlap");
            if(av&&ar)actions=actions+1;
            for(p=0;p<256;p=p+1)if(pending[p]>0&&!stick_pending)begin
                pending[p]<=pending[p]-1;
                if(pending[p]==1)begin
                    memory[p*64+2]<=(memory[p*64+2]&32'hfffffff3)|
                        ((p==8'h20 || p==8'h21) ? ((memory[1][0] && memory[(p+16)*64+1][0]) ? 2 : 0) : 2);
                    if(ack_pending[p])begin
                        if(!fail_ack)begin
                            memory[p*64+18]<=memory[p*64+18]+1;
                            memory[p*64+16]<=memory[p*64+(p==8'h61 ? 13 : 8)];
                        end
                        ack_pending[p]<=0;
                    end
                end
            end
            if(bv&&br)begin
                if(!bw)reads=reads+1;
                else if(!be)begin
                    if(bs!=15 || ba[1:0]!=0 || ba[31:16]!=0)$fatal(1,"bad cfg shape");
                    trace_addr[writes]=ba;trace_data[writes]=bd;writes=writes+1;
                    if(ba[7:0]==4)begin
                        memory[ba[15:2]]<=bd&1;
                        memory[(ba+4)>>2]<=(memory[(ba+4)>>2]&32'hfffffffe)|(bd&1);
                        if(bd[2])begin
                            if(ba==32'h3004 && memory[32'h2004>>2][0])$fatal(1,"DAC commit while WMS enabled");
                            if(ba==32'h2004 && memory[32'h3008>>2][2:1]!=1)$fatal(1,"WMS before DAC ready");
                            pending[ba[15:8]]<=30;
                            memory[(ba+4)>>2]<=4|(bd&1);
                            if(ba==32'h6104 || ba==32'h6604)ack_pending[ba[15:8]]<=1;
                        end
                    end else memory[ba[15:2]]<=bd;
                end
            end
            if(held && (!mv || held_response!=={md,mseq,mk,ms,ml,ft[3:0]}))$fatal(1,"response stall");
            held=mv&&!mr;held_response={md,mseq,mk,ms,ml,ft[3:0]};
            if(mv&&mr)begin
                if(ms && md!==expected_status)$fatal(1,"status seq=%0d got=%0d expected=%0d",sequence,md,expected_status);
                if(mid!=code || msrc!=source || mseq!=sequence || !seqv || ft!=2 || mt!=64'h123456789abcdef0)$fatal(1,"response identity");
                if(ml)replies=replies+1;
            end
        end
    end
    task run_command;
        input [15:0] c,s;input [31:0] n,status_expected;
        integer old_replies;
        begin
            @(negedge clk);code=c;source=s;length=n;expected_status=status_expected;sequence=sequence+1;
            old_replies=replies;cv=1;
            while(!done)@(negedge clk);
            cv=0;repeat(3)@(negedge clk);
            if(replies!=old_replies+1)$fatal(1,"response count");
        end
    endtask
    task auto_write;
        input [15:0] s;input [31:0] a,d,status_expected;
        begin payload[0]=a;payload[1]=32'h10001;payload[2]=d;run_command(3,s,12,status_expected);end
    endtask
    task reject_range;
        input [15:0] c,s;input [31:0] a,count,status_expected;
        begin
            payload[0]=a;payload[1]=count;start_w=writes;start_r=reads;start_a=actions;
            run_command(c,s,c==2?8:8+count[15:0]*4,status_expected);
            if(writes!=start_w || reads!=start_r || actions!=start_a)$fatal(1,"rejected range had side effect");
        end
    endtask
    task check_wms_trace;
        input [31:0] shadow_address;
        begin
            if(writes!=start_w+5 || trace_addr[start_w]!=shadow_address ||
               trace_addr[start_w+1]!=32'h2004 || trace_data[start_w+1]!=0 ||
               trace_addr[start_w+2]!=32'h3004 || !trace_data[start_w+2][2] ||
               trace_addr[start_w+3]!=32'h2004 || !trace_data[start_w+3][2] ||
               trace_addr[start_w+4]!=32'h2004 || trace_data[start_w+4]!=1)$fatal(1,"combined commit trace");
        end
    endtask
    initial begin
        for(i=0;i<16384;i=i+1)memory[i]=0;
        for(i=0;i<256;i=i+1)begin pending[i]=0;ack_pending[i]=0;memory[i*64+2]=2;end
        for(i=0;i<1101;i=i+1)payload[i]=32'h12345678+i;
        repeat(4)@(negedge clk);rst=1;
        memory[32'h2004>>2]=1;memory[32'h2008>>2]=3;
        start_w=writes;auto_write(1,32'h2014,32'h12345678,0);check_wms_trace(32'h2014);
        start_w=writes;auto_write(16'h10,32'h3014,32'h11223344,0);check_wms_trace(32'h3014);
        // Each dedicated ADC/DILA source maps to its own mask bit and page.
        auto_write(16'h20,32'h4014,77,0);auto_write(16'h21,32'h4114,78,0);
        auto_write(16'h30,32'h5014,79,0);auto_write(16'h31,32'h5114,80,0);
        auto_write(16'h41,32'h6134,32'h42c80000,0);
        if(memory[32'h6140>>2]!=32'h42c80000 || memory[32'h6148>>2]!=1)$fatal(1,"HMP ACK completion");
        auto_write(16'h46,32'h6620,50000000,0);
        if(memory[32'h6640>>2]!=50000000 || memory[32'h6648>>2]!=1)$fatal(1,"RD ACK completion");
        fail_ack=1;auto_write(16'h41,32'h6134,32'h43480000,14);fail_ack=0;
        if(memory[32'h6140>>2]!=32'h42c80000 || memory[32'h6148>>2]!=1)$fatal(1,"missing ACK changed active");
        // All pages are validated, including holes between two owned endpoints.
        reject_range(2,16'h10,32'h20fc,962,4);
        reject_range(3,16'h10,32'h20fc,962,4);
        reject_range(2,16'h20,32'h40fc,2,4);
        reject_range(3,16'h20,32'h40fc,2,4);
        reject_range(3,1,32'h20fc,32'h10002,7);
        reject_range(3,1,32'h14,32'h10001,13);
        reject_range(3,1,32'h1014,32'h10001,13);
        reject_range(3,1,32'h6714,32'h10001,13);
        reject_range(3,1,32'h7014,32'h10001,13);
        reject_range(3,1,32'h8014,32'h10001,13);
        reject_range(3,1,32'hfffc,2,7);
        reject_range(2,1,32'hfffc,2,7);
        // Broad source retains ordinary cross-page access and exact end bounds.
        payload[0]=32'h20fc;payload[1]=2;payload[2]=111;payload[3]=222;
        start_w=writes;run_command(3,1,16,0);
        if(writes!=start_w+2 || memory[32'h20fc>>2]!=111 || memory[32'h2100>>2]!=222)$fatal(1,"legal cross-page write");
        run_command(2,1,8,0);
        payload[0]=32'hfffc;payload[1]=1;payload[2]=333;run_command(3,1,12,0);
        // Unsupported action/commit faults preserve WRITE response identity.
        inject_error=1;start_a=actions;
        for(reason_index=5;reason_index<=15;reason_index=reason_index+1)begin
            injected_code=reason_index;auto_write(1,32'h2014,7,reason_index);
        end
        inject_error=0;injected_code=5;
        if(actions!=start_a)$fatal(1,"commit after failed shadow write");
        inject_error=1;
        for(reason_index=5;reason_index<=15;reason_index=reason_index+1)begin
            injected_code=reason_index;payload[0]=3;payload[1]=1;run_command(13,2,8,reason_index);
        end
        inject_error=0;injected_code=5;
        bus_stall=1;start_w=writes;auto_write(1,32'h2014,9,9);bus_stall=0;
        if(writes!=start_w)$fatal(1,"cfg timeout wrote shadow");
        action_stall=1;start_w=writes;auto_write(1,32'h2014,10,9);action_stall=0;
        if(writes!=start_w+1)$fatal(1,"action cfg timeout wrote beyond shadow");
        stick_pending=1;auto_write(16'h46,32'h6620,60000000,9);stick_pending=0;
        if(busy || av || abv)$fatal(1,"decoder timeout did not cancel controller");
        if(memory[32'h6640>>2]!=50000000)$fatal(1,"timed out sensor changed active before ACK");
        $display("tb_decoder_action_PASS replies=%0d actions=%0d coordinated_auto ACK timeout full_range_zero_side_effect",replies,actions);
        $finish;
    end
    initial begin #500000;$fatal(1,"timeout");end
endmodule
`default_nettype wire
