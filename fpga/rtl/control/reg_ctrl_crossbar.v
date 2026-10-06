`default_nettype none
// Slot i owns PAGE_MAP[i*8 +:8]. High address bits never alias a legal page.
module reg_ctrl_crossbar #(
    parameter integer N=21,
    parameter [N*8-1:0] PAGE_MAP=168'h807067666564636261605150414031302120100100,
    parameter integer TIMEOUT_CYCLES=1024
)(
    input wire sys_clk,rst_sys_n,
    input wire cfg_valid,cfg_write,
    input wire [31:0] cfg_addr,cfg_wdata,
    input wire [3:0] cfg_wstrb,
    output reg cfg_ready,cfg_error,
    output reg [31:0] cfg_rdata,
    output reg [N-1:0] slave_valid,
    output wire slave_write,
    output wire [31:0] slave_addr,slave_wdata,
    output wire [3:0] slave_wstrb,
    input wire [N-1:0] slave_ready,slave_error,
    input wire [N*32-1:0] slave_rdata,
    output reg [31:0] timeout_count,
    input wire [N*4-1:0] slave_error_code,
    output reg [3:0] cfg_error_code
);
    localparam [1:0] IDLE=0, ISSUE=1, RESPONSE=2;
    reg [1:0] state;
    reg [31:0] wait_count;
    reg [N-1:0] request_slot;
    reg request_write;
    reg [31:0] request_addr,request_wdata;
    reg [3:0] request_wstrb;
    reg response_error;
    reg [31:0] response_rdata;
    reg [3:0] response_code;
    reg [N-1:0] decoded_slot;
    reg selected_ready,selected_error;
    reg [31:0] selected_rdata;
    reg [3:0] selected_code;
    wire deadline=wait_count>=TIMEOUT_CYCLES-1;
    integer i;
    assign slave_write=request_write;
    assign slave_addr=request_addr;
    assign slave_wdata=request_wdata;
    assign slave_wstrb=request_wstrb;
    always @* begin
        decoded_slot=0;
        selected_ready=0;selected_error=0;selected_rdata=0;selected_code=0;
        for(i=0;i<N;i=i+1)begin
            decoded_slot[i]=cfg_addr[15:8]==PAGE_MAP[i*8 +:8];
            selected_ready=selected_ready | (request_slot[i] & slave_ready[i]);
            selected_error=selected_error | (request_slot[i] & slave_error[i]);
            selected_rdata=selected_rdata | ({32{request_slot[i]}} & slave_rdata[i*32 +:32]);
            selected_code=selected_code | ({4{request_slot[i]}} & slave_error_code[i*4 +:4]);
        end
        slave_valid=0;cfg_ready=0;cfg_error=0;cfg_rdata=0;cfg_error_code=0;
        // Withdrawal cancels an uncompleted request without a late ACK.
        if(cfg_valid && state==ISSUE && !deadline)slave_valid=request_slot;
        if(cfg_valid && state==RESPONSE)begin
            cfg_ready=1;cfg_error=response_error;
            cfg_rdata=response_rdata;cfg_error_code=response_code;
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            state<=IDLE;wait_count<=0;timeout_count<=0;request_slot<=0;
            request_write<=0;request_addr<=0;request_wdata<=0;request_wstrb<=0;
            response_error<=0;response_rdata<=0;response_code<=0;
        end
        else begin
            case(state)
                IDLE:begin
                    wait_count<=0;
                    if(cfg_valid)begin
                        request_slot<=decoded_slot;request_write<=cfg_write;
                        request_addr<=cfg_addr;request_wdata<=cfg_wdata;request_wstrb<=cfg_wstrb;
                        response_error<=0;response_rdata<=0;response_code<=0;
                        if(decoded_slot==0 || cfg_addr[31:16]!=0 || cfg_addr[1:0]!=0)begin
                            response_error<=1;response_code<=5;state<=RESPONSE;
                        end else state<=ISSUE;
                    end
                end
                ISSUE:begin
                    if(!cfg_valid)begin state<=IDLE;wait_count<=0;end
                    else if(deadline)begin
                        response_error<=1;response_rdata<=0;response_code<=9;
                        timeout_count<=timeout_count+1'b1;state<=RESPONSE;
                    end else if(selected_ready)begin
                        response_rdata<=selected_rdata;response_error<=selected_error;
                        response_code<=selected_error ? (selected_code==0 ? 4'd15 : selected_code) : 4'd0;
                        state<=RESPONSE;
                    end else wait_count<=wait_count+1'b1;
                end
                // Completion is consumed at this edge. A continuously valid
                // master may present its next request in the following IDLE.
                RESPONSE:begin state<=IDLE;wait_count<=0;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
