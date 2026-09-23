`default_nettype none
// 32-cycle restoring division for infrequent configuration transactions.
module config_divider(
    input wire clk,rst_n,start,
    input wire [31:0] numerator,denominator,
    output reg busy,done,
    output reg [31:0] quotient
);
    reg [31:0] dividend,divisor,result;
    reg [32:0] remainder;
    reg [5:0] count;
    wire [32:0] trial={remainder[31:0],dividend[31]};
    wire take=trial>={1'b0,divisor};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin busy<=0;done<=0;quotient<=0;dividend<=0;divisor<=1;result<=0;remainder<=0;count<=0;end
        else begin
            done<=0;
            if(start && !busy)begin
                dividend<=numerator;divisor<=denominator;result<=0;remainder<=0;count<=32;busy<=1;
            end else if(busy)begin
                dividend<=dividend<<1;result<={result[30:0],take};
                remainder<=take?trial-{1'b0,divisor}:trial;count<=count-1'b1;
                if(count==1)begin quotient<={result[30:0],take};busy<=0;done<=1;end
            end
        end
    end
endmodule
`default_nettype wire
