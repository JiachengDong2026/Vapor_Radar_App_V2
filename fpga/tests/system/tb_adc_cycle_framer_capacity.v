`timescale 1ns/1ps
module tb_adc_cycle_framer_capacity;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,v=0,flush=0,hold_tx=1,rdy=0;
    reg [31:0] data=0,cid=10;reg [63:0] ts=10000;
    wire ready,mv,sof,last;wire [31:0] md,mc,mf,drops,cdrops,frames,level;
    wire [63:0] mt;wire [3:0] keep;wire [15:0] source,msg;
    integer cycle,point,tick=0,word_index=0,fragment=0,expect_cycle=10,samples=0;
    integer first,count;reg [31:0] expected;reg [193:0] held;reg stalled=0;
    adc_cycle_framer #(.MAX_SAMPLES(131072),.SOURCE_ID(16'h21),.ADC_BITS(16)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.enable(1'b1),.flush(flush),.sample_rate_hz(32'd12500000),
        .s_valid(v),.s_ready(ready),.s_data(data),.s_flags(8'd0),.s_capture_cycle_id(cid),.s_cycle_timestamp(ts),
        .s_capture_phase_valid(1'b1),.s_capture_time_sync_valid(1'b1),
        .m_valid(mv),.m_ready(rdy),.m_data(md),.m_keep(keep),.m_sof(sof),.m_last(last),
        .m_source_id(source),.m_msg_id(msg),.m_timestamp(mt),.m_cycle_id(mc),.m_flags(mf),
        .drop_count(drops),.cycle_drop_count(cdrops),.frame_count(frames),.buffered_samples(level));
    always @(negedge clk)begin tick=tick+1;rdy=!hold_tx && tick%13<9;end
    always @(posedge clk)if(rst)begin
        if(stalled && (!mv || {last,sof,mt,mc,mf,md}!==held))$fatal(1,"capacity stalled metadata");
        stalled=mv&&!rdy;held={last,sof,mt,mc,mf,md};
        if(v && !ready)$fatal(1,"unthrottled sample refused");
        if(mv && rdy)begin
            first=fragment*2040;count=(125000-first>2040)?2040:125000-first;
            case(word_index)
                0:expected=32'h00100002;
                1:expected=12500000;
                2:expected=125000;
                3:expected=0;
                4:expected=(62<<16)|fragment;
                5:expected=first;
                6:expected=count;
                7:expected=0;
                default:expected=expect_cycle*1000000+first+word_index-8;
            endcase
            if(md!==expected || mc!=expect_cycle || mt!=expect_cycle*1000 || mf!=7 ||
               sof!==(word_index==0) || last!==(word_index==count+7) || keep!=15 || source!='h21 || msg!='h1000)
                $fatal(1,"capacity word cycle=%0d frag=%0d word=%0d got=%h expected=%h",expect_cycle,fragment,word_index,md,expected);
            if(word_index>=8)samples=samples+1;
            if(last)begin
                word_index=0;
                if(fragment==61)begin fragment=0;expect_cycle=expect_cycle+1;end
                else fragment=fragment+1;
            end else word_index=word_index+1;
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        // 12.5 MSPS default: 125000 samples per 100 Hz WMS cycle. A full USB
        // outage fills both physical-size banks; the third cycle is discarded.
        for(cycle=10;cycle<13;cycle=cycle+1)begin
            for(point=0;point<125000;point=point+1)begin
                @(negedge clk);v=1;cid=cycle;ts=cycle*1000;data=cycle*1000000+point;
            end
        end
        @(negedge clk);v=0;flush=1;
        if(level!=250000 || drops!=125000 || cdrops!=1)$fatal(1,"bank pressure level=%0d drop=%0d cycles=%0d",level,drops,cdrops);
        hold_tx=0;wait(frames==124);repeat(5)@(negedge clk);
        if(samples!=250000 || level!=0 || expect_cycle!=12)$fatal(1,"capacity final");
        $display("tb_adc_cycle_framer_capacity_PASS samples=%0d fragments=%0d whole_cycle_drops=%0d",samples,frames,cdrops);$finish;
    end
    initial begin #12000000;$fatal(1,"capacity timeout frames=%0d",frames);end
endmodule
