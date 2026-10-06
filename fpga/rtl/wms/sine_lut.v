`default_nettype none
module sine_lut(input wire clk,input wire [31:0] phase,
    output reg signed [31:0] sin_value);
    // 4096 samples, phase truncated to 12 bits. Exact cardinal points.
    (* rom_style="block" *) reg signed [31:0] rom[0:4095];
    initial $readmemh("sine_q31.mem",rom);
    always @(posedge clk) sin_value<=rom[phase[31:20]];
endmodule
`default_nettype wire
