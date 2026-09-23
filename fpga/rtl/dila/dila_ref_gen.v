module dila_ref_gen (
    input wire [31:0] phase,input wire [31:0] phase_1f,
    input wire [31:0] phase_2f_correction,
    output wire signed [17:0] sin_1f,cos_1f,sin_2f,cos_2f
);
    `include "dila_sine_lut.vh"
    wire [31:0] p1=phase+phase_1f;
    wire [31:0] p2=(phase<<1)+phase_2f_correction;
    wire [31:0] c1=p1+32'h40000000,c2=p2+32'h40000000;
    assign sin_1f=sine_lut(p1[31:22]);assign cos_1f=sine_lut(c1[31:22]);
    assign sin_2f=sine_lut(p2[31:22]);assign cos_2f=sine_lut(c2[31:22]);
endmodule

