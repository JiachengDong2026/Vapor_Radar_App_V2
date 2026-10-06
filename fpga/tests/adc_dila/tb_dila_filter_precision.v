`timescale 1ns/1ps
// Vectors: fpga/scripts/generate_dlia_precision_vectors.py (external output).
module dila_filter_precision_case #(
    parameter integer RATE=1000000,
    parameter integer COUNT=18000
)(output reg done=0);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,sample_valid=0,cfg_valid=0,cfg_write=0;
    reg [31:0] sample_data=0,cfg_addr=0,cfg_wdata=0;
    reg [193:0] capture_tag=0;
    wire sample_ready,cfg_ready,cfg_error;
    wire [31:0] cfg_rdata;
    reg [193:0] vectors[0:COUNT-1];
    reg [127:0] bypass_expected[0:15];
    integer n,first_count=0,final_count=0,score_mode=0,sat_count=0;
    reg [31:0] rd;
    dila_core #(.INPUT_RATE_HZ(RATE),.USE_CAPTURE_TAGS(1),.OUTPUT_FORMAT(1),.MAX_POINTS(512)) dut(
        .sys_clk(clk),.rst_sys_n(rst_n),.sample_valid(sample_valid),.sample_ready(sample_ready),
        .sample_data(sample_data),.sample_flags(8'd0),.wms_scan_start(1'b0),.wms_cycle_id(32'd1),
        .wms_sine_phase(32'd0),.wms_phase_valid(1'b1),.timestamp_now(64'd0),.time_sync_valid(1'b1),
        .capture_tag(capture_tag),.input_sample_rate_hz(RATE),.expected_per_cycle(32'd0),.input_overflow_pulse(1'b0),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(4'hf),
        .cfg_ready(cfg_ready),.cfg_rdata(cfg_rdata),.cfg_error(cfg_error),.m_ready(1'b1));

    function [193:0] make_tag;
        input integer index;
        input [31:0] phase;
        begin make_tag={2'b11,64'h123456789abcdef0,{32'hfedcba98,index[31:0]},phase,32'd1};end
    endfunction
    function [31:0] mixed_zero;
        input signed [31:0] value;
        reg signed [63:0] product;
        begin
            product=value*64'sd131071;
            mixed_zero=product<0?-(((-product)+64'sd65536)>>>17):((product+64'sd65536)>>>17);
        end
    endfunction
    task write_reg;
        input [7:0] address;
        input [31:0] value;
        begin
            @(negedge clk);cfg_addr=32'h5000+address;cfg_wdata=value;cfg_valid=1;cfg_write=1;
            @(posedge clk);if(!cfg_ready || cfg_error)$fatal(1,"filter cfg RATE=%0d ofs=%h",RATE,address);
            @(negedge clk);cfg_valid=0;cfg_write=0;
        end
    endtask
    task read_reg;
        input [7:0] address;
        output [31:0] value;
        begin
            @(negedge clk);cfg_addr=32'h5000+address;cfg_valid=1;
            @(posedge clk);if(!cfg_ready || cfg_error)$fatal(1,"filter read");value=cfg_rdata;
            @(negedge clk);cfg_valid=0;
        end
    endtask
    task configure;
        input [31:0] mode;
        begin
            write_reg(8'h20,mode);write_reg(8'h04,4);
            repeat(100)@(negedge clk);
            if(dut.pending)$fatal(1,"filter configuration did not apply");
            write_reg(8'h04,1);
        end
    endtask
    task send;
        input integer index;
        input [31:0] value,phase;
        begin
            @(negedge clk);sample_data=value;capture_tag=make_tag(index,phase);sample_valid=1;
            @(posedge clk);if(!sample_ready)$fatal(1,"8-clock throughput lost RATE=%0d idx=%0d",RATE,index);
            @(negedge clk);sample_valid=0;repeat(6)@(negedge clk);
        end
    endtask

    always @(posedge clk)if(rst_n)begin
        if((dut.first_filter_busy || dut.first_filtered_valid) && dut.config_pipeline_idle)
            $fatal(1,"First section incorrectly excluded from pipeline idle");
        if(dut.first_filtered_valid && score_mode==1)begin
            if(dut.first_filtered_tag!==make_tag(first_count,vectors[first_count][63:32]))
                $fatal(1,"First stage tag RATE=%0d idx=%0d",RATE,first_count);
            if(dut.first_filter_sat!==vectors[first_count][192])
                $fatal(1,"First stage saturation RATE=%0d idx=%0d",RATE,first_count);
            sat_count=sat_count+vectors[first_count][192];first_count=first_count+1;
        end
        if(dut.filtered_valid && score_mode!=0)begin
            if(score_mode==1)begin
                if(dut.filtered_iq!==vectors[final_count][191:64])
                    $fatal(1,"Cascade IQ RATE=%0d idx=%0d got=%h expected=%h",RATE,final_count,dut.filtered_iq,vectors[final_count][191:64]);
                if(dut.filtered_tag!==make_tag(final_count,vectors[final_count][63:32]))
                    $fatal(1,"Cascade tag RATE=%0d idx=%0d",RATE,final_count);
                if(dut.filter_sat!==vectors[final_count][193])
                    $fatal(1,"Second stage saturation RATE=%0d idx=%0d",RATE,final_count);
                sat_count=sat_count+vectors[final_count][193];
            end else begin
                if(dut.filtered_tag!==make_tag(final_count,0))$fatal(1,"Bypass/reset tag");
                if(score_mode==2 && dut.filtered_iq!==bypass_expected[final_count])$fatal(1,"Cascade bypass changed IQ");
                if(score_mode==3 && dut.filtered_iq!==128'd0)$fatal(1,"Reset did not clear both section histories");
            end
            final_count=final_count+1;
        end
    end
    initial begin
        if(RATE==1000000)$readmemh("filter_1000000.hex",vectors);
        else $readmemh("filter_12500000.hex",vectors);
        repeat(5)@(negedge clk);rst_n=1;
        read_reg(8'h00,rd);if(rd!=32'h00300101)$fatal(1,"Module version");
        read_reg(8'h24,rd);if(rd!=(RATE==1000000?32'h00040101:32'h00040102))$fatal(1,"Filter profile");
        configure(1);score_mode=1;
        for(n=0;n<COUNT;n=n+1)send(n,vectors[n][31:0],vectors[n][63:32]);
        repeat(20)@(negedge clk);
        if(first_count!=COUNT || final_count!=COUNT)$fatal(1,"Cascade lost samples");
        read_reg(8'h34,rd);if(rd!=sat_count || rd==0)$fatal(1,"Saturation accounting RATE=%0d got=%0d expected=%0d",RATE,rd,sat_count);
        $display("FILTER_BIT_EXACT_PASS RATE=%0d vectors=%0d saturation=%0d",RATE,COUNT,sat_count);
        score_mode=0;write_reg(8'h04,8);configure(5);final_count=0;score_mode=2;
        for(n=0;n<16;n=n+1)begin
            case(n%4)
                0:sample_data=32'h7fffffff;
                1:sample_data=32'h80000000;
                2:sample_data=32'h00000001;
                3:sample_data=32'hffffffff;
            endcase
            bypass_expected[n]={32'd0,mixed_zero(sample_data),32'd0,mixed_zero(sample_data)};
            send(n,sample_data,0);
        end
        repeat(20)@(negedge clk);
        if(final_count!=16)$fatal(1,"Bypass lost samples");
        score_mode=0;write_reg(8'h04,2);configure(1);final_count=0;score_mode=3;
        for(n=0;n<16;n=n+1)send(n,0,0);
        repeat(20)@(negedge clk);
        if(final_count!=16)$fatal(1,"Reset lost samples");
        score_mode=0;
        // Clear while section two is still processing the outstanding sample.
        send(100,32'd1000000,0);write_reg(8'h04,8);
        repeat(20)@(negedge clk);
        if(!dut.config_pipeline_idle || dut.filtered_valid || dut.first_filtered_valid)$fatal(1,"Clear left a pipeline transaction");
        $display("FILTER_BYPASS_RESET_TAG_PASS RATE=%0d",RATE);done=1;
    end
endmodule

module tb_dila_filter_precision;
    wire done0,done1;
    dila_filter_precision_case #(.RATE(1000000),.COUNT(18000)) p0(.done(done0));
    dila_filter_precision_case #(.RATE(12500000),.COUNT(225000)) p1(.done(done1));
    initial begin wait(done0 && done1);$display("DILA_FILTER_PRECISION_PASS");$finish;end
    initial begin #20000000;$fatal(1,"Filter precision watchdog");end
endmodule
