module member1_divider (
    input wire clk, input wire rst_n, input wire start,
    input wire [31:0] numerator, input wire [31:0] denominator,
    output reg busy, output reg done, output reg [31:0] quotient
);
    reg [31:0] bits, divisor, partial;
    reg [5:0] count;
    wire [32:0] trial={partial,bits[31]};
    wire take=trial >= {1'b0,divisor};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin busy<=0;done<=0;quotient<=0;bits<=0;divisor<=1;partial<=0;count<=0;end
        else begin
            done<=0;
            if(start && !busy)begin busy<=1;bits<=numerator;divisor<=denominator;partial<=0;quotient<=0;count<=0;end
            else if(busy) begin
                partial<=take ? trial-divisor:trial;
                bits<={bits[30:0],1'b0};quotient<={quotient[30:0],take};
                if(count==31)begin busy<=0;done<=1;end
                else count<=count+1'b1;
            end
        end
    end
endmodule

