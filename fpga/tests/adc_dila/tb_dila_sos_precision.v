`timescale 1ns/1ps
// Independent Python integer oracle; 42 profiles, all four I/Q lanes and tags.
module tb_dila_sos_precision;
    localparam CASES=42,COUNT=2048;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,cv=0,cw=0,sv=0,score=0;
    reg [31:0] ca=0,cd=0,sample_data=0,input_rate=1000000;
    reg [193:0] tag=0;
    wire cr,ce,sr;wire [31:0] rd;
    reg [31:0] config_words[0:CASES*33-1],input_words[0:CASES*COUNT-1];
    reg [35:0] expected[0:CASES*COUNT-1];
    integer c,n,s,i,final_count=0,sat_total=0,section_count[0:3];
    reg [31:0] readback;
    dila_core #(.USE_CAPTURE_TAGS(1),.OUTPUT_FORMAT(1),.MAX_POINTS(4096)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.sample_valid(sv),.sample_ready(sr),.sample_data(sample_data),.sample_flags(8'd0),
        .wms_scan_start(1'b0),.wms_cycle_id(32'd1),.wms_sine_phase(32'd0),.wms_phase_valid(1'b1),
        .timestamp_now(64'd1),.time_sync_valid(1'b1),.capture_tag(tag),.input_sample_rate_hz(input_rate),
        .expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),.cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),
        .cfg_wdata(cd),.cfg_wstrb(4'hf),.cfg_ready(cr),.cfg_rdata(rd),.cfg_error(ce),.m_ready(1'b1));
    task write_reg;
        input [7:0] offset;input [31:0] value;
        begin
            @(negedge clk);cv=1;cw=1;ca=32'h5000+offset;cd=value;
            @(posedge clk);if(!cr || ce)$fatal(1,"SOS cfg case=%0d offset=%h",c,offset);
            @(negedge clk);cv=0;cw=0;
        end
    endtask
    function [193:0] make_tag;
        input integer index;
        begin make_tag={2'b11,64'h123456789abcdef0,32'h87654321,index[31:0],32'd0,32'd1};end
    endfunction
    always @(posedge clk)if(rst && score)begin
        if((|dut.section_busy || |dut.section_valid[4:1]) && dut.config_pipeline_idle)
            $fatal(1,"SOS premature idle");
        for(s=0;s<4;s=s+1)begin
            if(dut.section_valid[s+1])begin
                if(dut.section_sat_counted[s]!==expected[c*COUNT+section_count[s]][32+s])
                    $fatal(1,"SOS saturation case=%0d section=%0d sample=%0d",c,s,section_count[s]);
                sat_total=sat_total+dut.section_sat_counted[s];
                section_count[s]=section_count[s]+1;
            end
        end
        if(dut.filtered_valid)begin
            if(dut.filtered_iq!=={32'd0,expected[c*COUNT+final_count][31:0],32'd0,expected[c*COUNT+final_count][31:0]})
                $fatal(1,"SOS mismatch case=%0d sample=%0d got=%h expected=%h",c,final_count,dut.filtered_iq,expected[c*COUNT+final_count]);
            if(dut.filtered_tag!==make_tag(final_count))$fatal(1,"SOS tag mismatch");
            final_count=final_count+1;
        end
    end
    initial begin
        $readmemh("sos_config.hex",config_words);$readmemh("sos_input.hex",input_words);$readmemh("sos_expected.hex",expected);
        repeat(5)@(negedge clk);rst=1;
        for(c=0;c<CASES;c=c+1)begin
            score=0;write_reg(8'h04,2);input_rate=config_words[c*33];
            write_reg(8'h60,config_words[c*33+1]);
            write_reg(8'hE0,input_rate);write_reg(8'hE4,config_words[c*33+2]);
            for(i=0;i<30;i=i+1)write_reg(8'h68+i*4,config_words[c*33+3+i]);
            write_reg(8'h20,1);write_reg(8'h1C,1000);write_reg(8'h04,4);
            repeat(160)@(negedge clk);
            if(dut.pending || !dut.coeff_active_custom)$fatal(1,"SOS not applied");
            final_count=0;sat_total=0;for(i=0;i<4;i=i+1)section_count[i]=0;
            write_reg(8'h04,1);score=1;
            for(n=0;n<COUNT;n=n+1)begin
                @(negedge clk);sv=1;sample_data=input_words[c*COUNT+n];tag=make_tag(n);
                @(posedge clk);if(!sr)$fatal(1,"SOS throughput lost");
                @(negedge clk);sv=0;repeat(6)@(negedge clk);
            end
            repeat(40)@(negedge clk);
            if(final_count!=COUNT)$fatal(1,"SOS lost output samples");
            for(i=0;i<4;i=i+1)if(section_count[i]!=COUNT)$fatal(1,"SOS lost section samples");
            if(dut.lpf_sat_count!=sat_total)$fatal(1,"SOS saturation counter");
            $display("SOS_CASE_PASS case=%0d rate=%0d order=%0d cutoff=%0d samples=%0d",c,input_rate,config_words[c*33+1],config_words[c*33+2],final_count);
        end
        $display("DILA_SOS_PRECISION_PASS cases=42 samples=86016");$finish;
    end
    initial begin #12000000;$fatal(1,"SOS precision timeout");end
endmodule
