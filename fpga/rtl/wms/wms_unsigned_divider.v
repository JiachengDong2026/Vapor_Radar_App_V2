`default_nettype none
// Restoring unsigned division. Configuration only; no combinational divider.
module wms_unsigned_divider #(parameter integer W=96)(
    input wire clk, input wire rst_n, input wire start,
    input wire [W-1:0] numerator, input wire [W-1:0] denominator,
    output reg busy, output reg done, output reg [W-1:0] quotient,
    output reg [W-1:0] remainder
);
    reg [W-1:0] dividend, divisor, q;
    reg [W:0] rem_work;
    reg [7:0] count;
    wire [W:0] trial = {rem_work[W-1:0],dividend[W-1]};
    wire take = trial >= {1'b0,divisor};
    always @(posedge clk) begin
        if (!rst_n) begin
            busy<=0; done<=0; quotient<=0; remainder<=0;
            dividend<=0; divisor<=1; q<=0; rem_work<=0; count<=0;
        end else begin
            done<=0;
            if (start && !busy) begin
                dividend<=numerator; divisor<=denominator; q<=0;
                rem_work<=0; count<=W; busy<=1;
            end else if (busy) begin
                dividend<=dividend<<1;
                q<={q[W-2:0],take};
                rem_work<=take ? trial-{1'b0,divisor} : trial;
                count<=count-1'b1;
                if (count==1) begin
                    quotient<={q[W-2:0],take};
                    remainder<=take ? trial-{1'b0,divisor} : trial;
                    busy<=0; done<=1;
                end
            end
        end
    end
endmodule
`default_nettype wire
