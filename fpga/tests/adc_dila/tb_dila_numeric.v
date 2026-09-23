`timescale 1ns/1ps
module tb_dila_numeric;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,valid=0;
    reg [31:0] phase=0,p1=0,p2=0,sample=0;
    reg [193:0] tag=0;
    wire signed [17:0] sin1,cos1,sin2,cos2;
    wire mv,ms;
    wire [127:0] mi;
    wire [193:0] mt;
    wire [1:0] fv,fs,fb,hv,hb;
    wire [127:0] fi0,fi1;
    wire [193:0] ft0,ft1,ht0,ht1;
    wire [191:0] hp0,hp1;
    reg [127:0] inputs[0:10239],expect0[0:10239],expect1[0:10239];
    reg [63:0] mag0[0:10239],mag1[0:10239];
    integer n,count0=0,count1=0,hcount0=0,hcount1=0;
    dila_ref_gen refgen(.phase(phase),.phase_1f(p1),.phase_2f_correction(p2),.sin_1f(sin1),.cos_1f(cos1),.sin_2f(sin2),.cos_2f(cos2));
    dila_mixer mix(.clk(clk),.rst_n(rst_n),.in_valid(valid),.sample(sample),.cos_1f(cos1),.sin_1f(sin1),.cos_2f(cos2),.sin_2f(sin2),
        .in_tag(tag),.out_valid(mv),.out_iq(mi),.out_tag(mt),.saturation(ms));
    dila_lpf #(.B0(48'sd691437427),.B1(48'sd1382874854),.B2(48'sd691437427),.A1(-48'sd140112212256429),.A2(48'sd69746233828473)) f0(
        .clk(clk),.rst_n(rst_n),.clear(1'b0),.in_valid(mv),.in_iq(mi),.in_tag(mt),.bypass(1'b0),
        .out_valid(fv[0]),.out_iq(fi0),.out_tag(ft0),.saturation(fs[0]),.busy(fb[0]));
    dila_lpf #(.B0(48'sd4443295),.B1(48'sd8886591),.B2(48'sd4443295),.A1(-48'sd140687465942571),.A2(48'sd70318739538089)) f1(
        .clk(clk),.rst_n(rst_n),.clear(1'b0),.in_valid(mv),.in_iq(mi),.in_tag(mt),.bypass(1'b0),
        .out_valid(fv[1]),.out_iq(fi1),.out_tag(ft1),.saturation(fs[1]),.busy(fb[1]));
    dila_magnitude h0(.clk(clk),.rst_n(rst_n),.start(fv[0] && ft0[5:0]==0),.iq(fi0),.tag(ft0),.valid(hv[0]),.busy(hb[0]),.point(hp0),.point_tag(ht0));
    dila_magnitude h1(.clk(clk),.rst_n(rst_n),.start(fv[1] && ft1[5:0]==0),.iq(fi1),.tag(ft1),.valid(hv[1]),.busy(hb[1]),.point(hp1),.point_tag(ht1));
    always @(posedge clk)if(rst_n)begin
        if(fv[0])begin
            if(ft0[31:0]!=count0 || fi0!==expect0[count0])$fatal(1,"LPF0 idx=%0d tag=%0d got=%h expected=%h",count0,ft0[31:0],fi0,expect0[count0]);
            count0=count0+1;
        end
        if(fv[1])begin
            if(ft1[31:0]!=count1 || fi1!==expect1[count1])$fatal(1,"LPF1 idx=%0d tag=%0d got=%h expected=%h",count1,ft1[31:0],fi1,expect1[count1]);
            count1=count1+1;
        end
        if(hv[0])begin if(hp0[191:128]!==mag0[ht0[31:0]])$fatal(1,"MAG0 idx=%0d got=%h expected=%h",ht0[31:0],hp0[191:128],mag0[ht0[31:0]]);hcount0=hcount0+1;end
        if(hv[1])begin if(hp1[191:128]!==mag1[ht1[31:0]])$fatal(1,"MAG1 idx=%0d",ht1[31:0]);hcount1=hcount1+1;end
    end
    initial begin #2000000;$fatal(1,"Numeric watchdog");end
    initial begin
        $readmemh("numeric_input.hex",inputs);
        $readmemh("numeric_expected_0.hex",expect0);
        $readmemh("numeric_expected_1.hex",expect1);
        $readmemh("magnitude_expected_0.hex",mag0);
        $readmemh("magnitude_expected_1.hex",mag1);
        repeat(5)@(negedge clk);rst_n=1;
        for(n=0;n<10240;n=n+1)begin
            @(negedge clk);{p2,p1,phase,sample}=inputs[n];tag=n;valid=1;
            @(negedge clk);valid=0;repeat(6)@(negedge clk);
        end
        repeat(80)@(negedge clk);
        if(count0!=10240 || count1!=10240 || hcount0!=160 || hcount1!=160)$fatal(1,"Missing numerical outputs");
        $display("DILA_NUMERIC_PASS vectors=%0d profiles=2 magnitudes=%0d",count0,hcount0+hcount1);$finish;
    end
endmodule
