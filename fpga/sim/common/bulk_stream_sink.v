module bulk_stream_sink(input clk,input rst_n,input valid,output ready,input [63:0] data); assign ready=1'b1; always @(posedge clk) if(rst_n&&valid) $display("bulk_stream %h",data); endmodule
