// Two parallel non-restoring integer square roots. 33 iterations, exact floor.
module dila_magnitude (
    input wire clk,input wire rst_n,input wire start,
    input wire [127:0] iq,input wire [193:0] tag,
    output reg valid,output wire busy,output reg [191:0] point,
    output reg [193:0] point_tag
);
    reg [1:0] state;
    reg [5:0] count;
    reg [63:0] sq0,sq1,sq2,sq3;
    reg [65:0] bits1,bits2;
    reg [67:0] rem1,rem2;
    reg [32:0] root1,root2;
    reg [127:0] iq_reg;
    reg [193:0] tag_reg;
    wire [67:0] r1={rem1[65:0],bits1[65:64]},r2={rem2[65:0],bits2[65:64]};
    wire [67:0] trial1={33'd0,root1,2'b01},trial2={33'd0,root2,2'b01};
    wire [32:0] next1={root1[31:0],r1>=trial1},next2={root2[31:0],r2>=trial2};
    assign busy=state!=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=0;valid<=0;point<=0;point_tag<=0;count<=0;end
        else begin
            valid<=0;
            case(state)
                0:if(start)begin
                    sq0<=$signed(iq[31:0])*$signed(iq[31:0]);
                    sq1<=$signed(iq[63:32])*$signed(iq[63:32]);
                    sq2<=$signed(iq[95:64])*$signed(iq[95:64]);
                    sq3<=$signed(iq[127:96])*$signed(iq[127:96]);
                    iq_reg<=iq;tag_reg<=tag;state<=1;
                end
                1:begin bits1<={2'd0,sq0}+{2'd0,sq1};bits2<={2'd0,sq2}+{2'd0,sq3};
                    rem1<=0;rem2<=0;root1<=0;root2<=0;count<=0;state<=2;end
                2:begin
                    rem1<=r1>=trial1?r1-trial1:r1;rem2<=r2>=trial2?r2-trial2:r2;
                    root1<=next1;root2<=next2;bits1<=bits1<<2;bits2<=bits2<<2;
                    if(count==32)begin
                        point<={next2>33'h07fffffff ? 32'h7fffffff:next2[31:0],
                                next1>33'h07fffffff ? 32'h7fffffff:next1[31:0],iq_reg};
                        point_tag<=tag_reg;valid<=1;state<=0;
                    end else count<=count+1'b1;
                end
                default:state<=0;
            endcase
        end
    end
endmodule


