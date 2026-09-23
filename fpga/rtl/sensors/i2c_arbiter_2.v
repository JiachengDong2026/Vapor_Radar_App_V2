module i2c_arbiter_2(
    input wire sys_clk,rst_sys_n,
    input wire [1:0] c_valid,output wire [1:0] c_ready,
    input wire [13:0] c_addr,input wire [11:0] c_write_len,c_read_len,
    input wire [511:0] c_write_data,
    output wire [1:0] c_done,output wire [5:0] c_error,
    output wire [511:0] c_read_data,
    output wire req_valid,input wire req_ready,
    output wire [6:0] req_addr,output wire [5:0] req_write_len,req_read_len,
    output wire [255:0] req_write_data,
    input wire done,input wire [2:0] error,input wire [255:0] read_data
);
    reg occupied,owner,turn;
    wire choice=c_valid[turn]?turn:!turn;
    assign req_valid=!occupied&&|c_valid;
    assign req_addr=c_addr[choice*7+:7];
    assign req_write_len=c_write_len[choice*6+:6];
    assign req_read_len=c_read_len[choice*6+:6];
    assign req_write_data=c_write_data[choice*256+:256];
    assign c_ready={2{req_ready&&req_valid}}&(choice?2'b10:2'b01);
    assign c_done={2{occupied&&done}}&(owner?2'b10:2'b01);
    assign c_error={error,error};assign c_read_data={read_data,read_data};
    always @(posedge sys_clk) begin
        if(!rst_sys_n) begin occupied<=0;owner<=0;turn<=0;end
        else begin
            if(req_valid&&req_ready) begin occupied<=1;owner<=choice;end
            if(occupied&&done) begin occupied<=0;turn<=!owner;end
        end
    end
endmodule
