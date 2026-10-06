module dila_lpf #(
    parameter signed [47:0] B0=48'sd0,
    parameter signed [47:0] B1=48'sd0,
    parameter signed [47:0] B2=48'sd0,
    parameter signed [47:0] A1=48'sd0,
    parameter signed [47:0] A2=48'sd0
)(
    input wire clk,input wire rst_n,input wire clear,
    input wire in_valid,input wire [127:0] in_iq,input wire [193:0] in_tag,
    input wire bypass,
    output reg out_valid,output reg [127:0] out_iq,output reg [193:0] out_tag,
    output reg saturation,output wire busy
);
    reg [1:0] stage;
    reg signed [47:0] x1[0:3],x2[0:3],y1[0:3],y2[0:3];
    reg signed [95:0] p0[0:3],p1[0:3],p2[0:3],p3[0:3],p4[0:3];
    reg signed [99:0] sum[0:3];
    reg [127:0] bypass_iq;
    reg bypass_reg;
    reg [193:0] tag_reg;
    reg signed [100:0] rounded;
    reg signed [47:0] yn;
    reg signed [48:0] output_round;
    integer k;
    assign busy=stage!=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            stage<=0;out_valid<=0;out_iq<=0;out_tag<=0;tag_reg<=0;saturation<=0;bypass_iq<=0;bypass_reg<=0;
            for(k=0;k<4;k=k+1)begin x1[k]<=0;x2[k]<=0;y1[k]<=0;y2[k]<=0;end
        end else begin
            out_valid<=0;saturation<=0;
            if(clear)begin
                stage<=0;
                for(k=0;k<4;k=k+1)begin x1[k]<=0;x2[k]<=0;y1[k]<=0;y2[k]<=0;end
            end else case(stage)
                0:if(in_valid)begin
                    tag_reg<=in_tag;bypass_iq<=in_iq;bypass_reg<=bypass;
                    for(k=0;k<4;k=k+1)begin
                        p0[k]<=$signed({in_iq[k*32+:32],16'd0})*B0;
                        p1[k]<=x1[k]*B1;p2[k]<=x2[k]*B2;
                        p3[k]<=y1[k]*A1;p4[k]<=y2[k]*A2;
                        x2[k]<=x1[k];x1[k]<=$signed({in_iq[k*32+:32],16'd0});
                    end
                    stage<=1;
                end
                1:begin
                    for(k=0;k<4;k=k+1)
                        sum[k]<={{4{p0[k][95]}},p0[k]}+$signed({{4{p1[k][95]}},p1[k]})+
                                $signed({{4{p2[k][95]}},p2[k]})-$signed({{4{p3[k][95]}},p3[k]})-
                                $signed({{4{p4[k][95]}},p4[k]});
                    stage<=2;
                end
                2:begin
                    for(k=0;k<4;k=k+1)begin
                        rounded=sum[k]<0 ? -(((-$signed({sum[k][99],sum[k]}))+101'sd35184372088832)>>>46):
                                            (($signed({sum[k][99],sum[k]})+101'sd35184372088832)>>>46);
                        if(rounded>101'sd140737488355327)begin yn=48'sh7fffffffffff;saturation<=1;end
                        else if(rounded < -101'sd140737488355328)begin yn=48'sh800000000000;saturation<=1;end
                        else yn=rounded[47:0];
                        y2[k]<=y1[k];y1[k]<=yn;
                        output_round=yn<0 ? -(((-$signed({yn[47],yn}))+49'sd32768)>>>16):
                                              (($signed({yn[47],yn})+49'sd32768)>>>16);
                        if(bypass_reg)out_iq[k*32+:32]<=bypass_iq[k*32+:32];
                        else if(output_round>49'sd2147483647)begin out_iq[k*32+:32]<=32'h7fffffff;saturation<=1;end
                        else if(output_round < -49'sd2147483648)begin out_iq[k*32+:32]<=32'h80000000;saturation<=1;end
                        else out_iq[k*32+:32]<=output_round[31:0];
                    end
                    out_tag<=tag_reg;out_valid<=1;stage<=0;
                end
                default:stage<=0;
            endcase
        end
    end
endmodule

