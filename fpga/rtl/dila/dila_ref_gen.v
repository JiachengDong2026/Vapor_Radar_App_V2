module dila_ref_gen (
    input wire [31:0] phase,
    input wire [31:0] phase_1f,
    input wire [31:0] phase_2f_correction,
    output wire signed [17:0] sin_1f,
    output wire signed [17:0] cos_1f,
    output wire signed [17:0] sin_2f,
    output wire signed [17:0] cos_2f
);
    `include "dila_sine_lut.vh"
    // Keep the existing combinational interface and Q1.17 peak of 131071.
    // Ten address bits plus twelve fractional bits resolve the phase to
    // 2^-22 turns. The final ten phase bits contribute < 0.197 output LSB.
    function signed [17:0] sine_interpolated;
        input [31:0] angle;
        reg [9:0] next_address;
        reg signed [17:0] lower_value;
        reg signed [17:0] upper_value;
        reg signed [17:0] delta;
        reg signed [12:0] fraction;
        reg signed [30:0] product;
        reg signed [30:0] rounded_product;
        reg signed [30:0] result;
        begin
            // Ten-bit addition intentionally wraps cell 1023 to cell 0.
            next_address = angle[31:22] + 10'd1;
            lower_value = sine_lut(angle[31:22]);
            upper_value = sine_lut(next_address);
            // Adjacent entries differ by at most 805, including wrap.
            delta = upper_value - lower_value;
            fraction = $signed({1'b0, angle[21:10]});
            product = delta * fraction;
            // Round to nearest, ties away from zero, for either slope.
            // A negative arithmetic shift floors, hence its bias is 2047.
            if (product < 0)
                rounded_product = product + 31'sd2047;
            else
                rounded_product = product + 31'sd2048;
            result = lower_value + (rounded_product >>> 12);
            sine_interpolated = result[17:0];
        end
    endfunction

    wire [31:0] p1 = phase + phase_1f;
    wire [31:0] p2 = (phase << 1) + phase_2f_correction;
    wire [31:0] c1 = p1 + 32'h40000000;
    wire [31:0] c2 = p2 + 32'h40000000;

    assign sin_1f = sine_interpolated(p1);
    assign cos_1f = sine_interpolated(c1);
    assign sin_2f = sine_interpolated(p2);
    assign cos_2f = sine_interpolated(c2);
endmodule

