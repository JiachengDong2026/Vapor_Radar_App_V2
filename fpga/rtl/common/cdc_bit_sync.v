module cdc_bit_sync #(
    parameter integer STAGES = 2,
    parameter integer INIT_VALUE = 0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire sync_out
);
    reg [STAGES-1:0] sync_ff;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < STAGES; i = i + 1)
                sync_ff[i] <= (INIT_VALUE != 0);
        end else begin
            sync_ff[0] <= async_in;
            for (i = 1; i < STAGES; i = i + 1)
                sync_ff[i] <= sync_ff[i-1];
        end
    end

    assign sync_out = sync_ff[STAGES-1];
endmodule
