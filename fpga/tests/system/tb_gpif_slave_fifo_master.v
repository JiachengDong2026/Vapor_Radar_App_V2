`timescale 1ns/1ps
// Independent pin-level model with AN65974 flag/data latency, bounded DMA room,
// descriptor commit delay, host drain stalls and bidirectional traffic.
module tb_gpif_slave_fifo_master;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,tv=0,tl=0,rr=0;
    reg [31:0] td=0;
    wire tr,rv;wire [31:0] rd;
    tri [31:0] dq;tri [12:0] ctl;wire pclk;
    reg [31:0] slave_dq=0;
    reg [3:0] wr_flag_pipe=0,wp_flag_pipe=0;
    reg [2:0] rd_flag_pipe=0,rp_flag_pipe=0;
    wire [31:0] txcount,rxcount,frames,errors;wire idle;
    integer sent=0,received=0,rx_issued=0,rx_consumed=0,tick=0;
    integer space=64,commit_wait=0,frame_expected=0,write_stalls=0;
    integer near_writes=0,rx_delay=0,max_rx_gap=0,last_rx_tick=0;
    reg [31:0] pending_read;
    reg held_valid=0;reg [31:0] held_data;
    reg [1:0] prev_addr=0;
    integer addr_age=0;
    assign ctl[4]=wr_flag_pipe[3];
    assign ctl[5]=rd_flag_pipe[2];
    assign ctl[6]=wp_flag_pipe[3];
    assign ctl[8]=rp_flag_pipe[2];
    assign dq=(!ctl[0] && !ctl[2]) ? slave_dq : 32'bz;
    usb_fx3_gpif_if #(.SIMULATION(1)) dut(.gpif_clk(clk),.rst_gpif_n(rst),
        .usb_dq(dq),.usb_ctl(ctl),.usb_pclk(pclk),
        .tx_valid(tv),.tx_ready(tr),.tx_data(td),.tx_last(tl),
        .rx_valid(rv),.rx_ready(rr),.rx_data(rd),.rx_free(rr?32'd16:32'd2),
        .tx_word_count(txcount),.rx_word_count(rxcount),.tx_frame_count(frames),.error_count(errors),.idle(idle));
    function is_last;
        input integer index;
        begin is_last=(index%173==172 || index==2999);end
    endfunction
    always @(negedge clk)begin
        if(!rst)begin tv=0;rr=0;end
        else begin
            tv=sent<3000;
            td=32'h12340000+sent;tl=is_last(sent);
            rr=tick%91<53;
        end
    end
    always @(posedge clk)begin
        if(!rst) begin
            sent=0;received=0;rx_issued=0;rx_consumed=0;tick=0;
            space=64;commit_wait=0;frame_expected=0;write_stalls=0;near_writes=0;
            wr_flag_pipe=0;wp_flag_pipe=0;rd_flag_pipe=0;rp_flag_pipe=0;
            rx_delay=0;held_valid=0;addr_age=0;prev_addr=0;
            last_rx_tick=0;max_rx_gap=0;
        end else begin
            tick=tick+1;
            if(tv && tr)sent=sent+1;
            if(held_valid && (!rv || rd!==held_data))$fatal(1,"RX unstable under stall");
            held_valid=rv&&!rr;held_data=rd;
            if(rv && rr)begin
                if(rd!==32'hcafe0000+rx_consumed)$fatal(1,"RX data %d got=%h",rx_consumed,rd);
                rx_consumed=rx_consumed+1;
            end
            if({ctl[11],ctl[12]}!==prev_addr)begin addr_age=0;prev_addr={ctl[11],ctl[12]};end
            else addr_age=addr_age+1;
            if(!ctl[7] && ctl[1])$fatal(1,"standalone PKTEND would emit ZLP");
            if(!ctl[1] && !ctl[3])$fatal(1,"read/write contention");
            if(!ctl[0] && !ctl[1])begin
                if(!ctl[2] || prev_addr!=0 || addr_age<3)$fatal(1,"TX bus direction/address setup");
                if(space==0 || commit_wait!=0)$fatal(1,"FX3 full overrun at word %d space=%d commit=%d",received,space,commit_wait);
                if(dq!==32'h12340000+received || (!ctl[7])!==is_last(received))$fatal(1,"TX data/last at %d data=%h",received,dq);
                received=received+1;space=space-1;
                if(!ctl[6])near_writes=near_writes+1;
                if(!ctl[7])begin frame_expected=frame_expected+1;space=0;commit_wait=5;end
            end
            if(!ctl[0] && !ctl[3])begin
                if(ctl[2] || prev_addr!=3 || addr_age<3)$fatal(1,"RX bus direction/address setup");
                if(rx_issued>=500 || rx_delay!=0)$fatal(1,"FX3 empty or overlapping read");
                pending_read=32'hcafe0000+rx_issued;rx_issued=rx_issued+1;rx_delay=3;
                if(tick-last_rx_tick>max_rx_gap)max_rx_gap=tick-last_rx_tick;
                last_rx_tick=tick;
            end
            // Data changes after the second edge following sampled SLRD.
            if(rx_delay!=0)begin
                rx_delay=rx_delay-1;
                if(rx_delay==0)slave_dq<=#2 pending_read;
            end
            if(commit_wait!=0)begin commit_wait=commit_wait-1;if(commit_wait==0)space=64;end
            else if(tick%397==0 && space<64)space=64;
            if(space==0)write_stalls=write_stalls+1;
            wr_flag_pipe<={wr_flag_pipe[2:0],(space>0 && commit_wait==0)};
            wp_flag_pipe<={wp_flag_pipe[2:0],(space>8 && commit_wait==0)};
            rd_flag_pipe<={rd_flag_pipe[1:0],(rx_issued<500)};
            rp_flag_pipe<={rp_flag_pipe[1:0],(rx_issued<489)};
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        // Reset while traffic is pending, then run a complete fresh epoch.
        wait(received>100 && rx_consumed>3);@(negedge clk);rst=0;
        repeat(5)@(negedge clk);rst=1;
        wait(received==3000 && rx_consumed==500);repeat(20)@(negedge clk);
        if(sent!=3000 || txcount!=3000 || rxcount!=500 || frames!=frame_expected || errors!=0)
            $fatal(1,"final counters sent=%d TX=%d RX=%d frames=%d/%d errors=%d",sent,txcount,rxcount,frames,frame_expected,errors);
        if(near_writes==0 || write_stalls==0 || max_rx_gap>700)$fatal(1,"coverage/fairness near=%d stalls=%d maxgap=%d",near_writes,write_stalls,max_rx_gap);
        $display("tb_gpif_slave_fifo_master_PASS TX=%0d RX=%0d frames=%0d near=%0d full_stalls=%0d maxRXgap=%0d",received,rx_consumed,frames,near_writes,write_stalls,max_rx_gap);$finish;
    end
    initial begin #3000000;$fatal(1,"timeout TX=%d RX=%d",received,rx_consumed);end
endmodule
