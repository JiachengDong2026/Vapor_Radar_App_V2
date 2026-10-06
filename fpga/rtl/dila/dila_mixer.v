module dila_mixer (
    input wire clk,input wire rst_n,input wire in_valid,
    input wire signed [31:0] sample,
    input wire signed [17:0] cos_1f,sin_1f,cos_2f,sin_2f,
    input wire [193:0] in_tag,
    output reg out_valid,output reg [127:0] out_iq,
    output reg [193:0] out_tag,output reg saturation
);
    reg valid_product;
    reg signed [49:0] product[0:3];
    reg [193:0] product_tag;
    function signed [31:0] quantize;
        input signed [49:0] value;
        reg signed [50:0] rounded;
        begin
            // Nearest, halfway away from zero; full signed product retained first.
            rounded=value<0 ? -(((-$signed({value[49],value}))+51'sd65536)>>>17):
                              (($signed({value[49],value})+51'sd65536)>>>17);
            if(rounded>51'sd2147483647)quantize=32'sh7fffffff;
            else if(rounded < -51'sd2147483648)quantize=32'sh80000000;
            else quantize=rounded[31:0];
        end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin valid_product<=0;out_valid<=0;out_iq<=0;out_tag<=0;product_tag<=0;saturation<=0;end
        else begin
            valid_product<=in_valid;out_valid<=valid_product;saturation<=0;
            if(in_valid)begin
                product[0]<=sample*cos_1f;product[1]<=sample*sin_1f;
                product[2]<=sample*cos_2f;product[3]<=sample*sin_2f;product_tag<=in_tag;
            end
            if(valid_product)begin
                out_iq<={quantize(product[3]),quantize(product[2]),quantize(product[1]),quantize(product[0])};
                out_tag<=product_tag;
            end
        end
    end
endmodule

