`default_nettype none
module watchdog #(
    parameter integer SYS_CLK_HZ = 100000000
)(
    input wire sys_clk, rst_sys_n,
    input wire [31:0] timeout_ms,
    input wire kick,
    output reg expired_pulse,
    output reg [31:0] expiration_count
);
    localparam integer MS_TICKS = SYS_CLK_HZ / 1000;
    reg [31:0] sub_ms, elapsed_ms, previous_timeout;
    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            sub_ms <= 0; elapsed_ms <= 0; previous_timeout <= 0;
            expired_pulse <= 0; expiration_count <= 0;
        end else begin
            expired_pulse <= 0;
            previous_timeout <= timeout_ms;
            if (kick || timeout_ms == 0 || timeout_ms != previous_timeout) begin
                sub_ms <= 0; elapsed_ms <= 0;
            end else if (sub_ms == MS_TICKS-1) begin
                sub_ms <= 0;
                if (elapsed_ms >= timeout_ms-1) begin
                    elapsed_ms <= 0;
                    expired_pulse <= 1;
                    expiration_count <= expiration_count + 1'b1;
                end else elapsed_ms <= elapsed_ms + 1'b1;
            end else sub_ms <= sub_ms + 1'b1;
        end
    end
endmodule
`default_nettype wire
