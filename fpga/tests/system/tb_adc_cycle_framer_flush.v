`timescale 1ns/1ps
module tb_adc_cycle_framer_flush;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,v=0,flush=0,rdy=1;
    reg [31:0] data=0,cycle=10;
    wire ready,mv,sof,last;wire [31:0] md,mc,mf,drops,cdrops,frames,level;
    wire [63:0] mt;wire [3:0] keep;wire [15:0] source,msg;
    integer tick=0,last_sample_tick=0,word_index=0,got=0,expected_points=3,i;
    reg [31:0] expected;
    adc_cycle_framer #(.MAX_SAMPLES(16),.FLUSH_IDLE_TICKS(8)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.enable(1'b1),.flush(flush),.sample_rate_hz(32'd1000),
        .s_valid(v),.s_ready(ready),.s_data(data),.s_flags(8'd0),.s_capture_cycle_id(cycle),.s_cycle_timestamp(64'd1000),
        .s_capture_phase_valid(1'b1),.s_capture_time_sync_valid(1'b1),
        .m_valid(mv),.m_ready(rdy),.m_data(md),.m_keep(keep),.m_sof(sof),.m_last(last),
        .m_source_id(source),.m_msg_id(msg),.m_timestamp(mt),.m_cycle_id(mc),.m_flags(mf),
        .drop_count(drops),.cycle_drop_count(cdrops),.frame_count(frames),.buffered_samples(level));
    task sample;input integer x;begin
        @(negedge clk);v=1;data=x;@(negedge clk);v=0;
    end endtask
    task pulse_flush;begin
        @(negedge clk);flush=1;@(negedge clk);flush=0;
    end endtask
    always @(posedge clk)if(rst)begin
        tick=tick+1;if(v)last_sample_tick=tick;
        if(mv && rdy)begin
            case(word_index)
                0:expected=32'h00180001;
                1:expected=1000;
                2:expected=expected_points;
                3,4:expected=0;
                default:expected=got*100+word_index-5;
            endcase
            if(md!==expected || mc!=10+got || mt!=1000 || mf!=32'h27 ||
               sof!==(word_index==0) || last!==(word_index==expected_points+4))
                $fatal(1,"flush frame=%0d word=%0d data=%h expected=%h flags=%h",got,word_index,md,expected,mf);
            if(sof && tick-last_sample_tick<8)$fatal(1,"flush ignored in-flight grace period");
            if(last)begin got=got+1;word_index=0;end else word_index=word_index+1;
        end
    end
    initial begin
        repeat(4)@(negedge clk);rst=1;
        // STOP pulse can precede the very first still-in-flight tagged sample.
        pulse_flush;repeat(3)@(negedge clk);
        for(i=0;i<3;i=i+1)sample(i);
        wait(got==1);@(negedge clk);cycle=11;expected_points=8;
        for(i=0;i<5;i=i+1)sample(100+i);
        pulse_flush;repeat(4)@(negedge clk);
        for(i=5;i<8;i=i+1)sample(100+i);
        wait(got==2);repeat(10)@(negedge clk);
        if(level!=0 || drops!=0 || cdrops!=0)$fatal(1,"flush count/empty");
        // An empty flush expires; it must not seal a future restarted cycle.
        pulse_flush;repeat(12)@(negedge clk);cycle=12;expected_points=1;sample(200);
        repeat(20)@(negedge clk);if(frames!=2)$fatal(1,"stale flush affected restart");
        pulse_flush;wait(got==3);
        $display("tb_adc_cycle_framer_flush_PASS pulse_before_capture=1 in_flight=1 restart=1");$finish;
    end
    initial begin #100000;$fatal(1,"flush timeout frames=%0d level=%0d",frames,level);end
endmodule
