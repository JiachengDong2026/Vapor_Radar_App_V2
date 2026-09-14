`include "register_map.vh"

// Reference synthesizable cfg_bus slave.
// This is not the project-level crossbar. It exists so member modules and the
// common regression use the exact frozen request/response timing.
module cfg_bus_if #(
    parameter [31:0] BASE_ADDR = 32'h0000_9000,
    parameter [15:0] MODULE_ID = 16'h00FE,
    parameter [7:0]  VER_MAJOR = 8'd1,
    parameter [7:0]  VER_MINOR = 8'd2
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,

    input  wire        cfg_valid,
    input  wire        cfg_write,
    input  wire [31:0] cfg_addr,
    input  wire [31:0] cfg_wdata,
    input  wire [3:0]  cfg_wstrb,
    output reg         cfg_ready,
    output reg  [31:0] cfg_rdata,
    output reg         cfg_error,

    output reg  [31:0] control_reg,
    output reg  [31:0] error_reg,
    output reg  [31:0] user_reg0,
    output reg  [31:0] user_reg1
);
    wire page_hit = (cfg_addr[31:8] == BASE_ADDR[31:8]);
    wire [7:0] ofs = cfg_addr[7:0];

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strb;
        begin
            apply_wstrb = old_value;
            if (strb[0]) apply_wstrb[7:0]   = new_value[7:0];
            if (strb[1]) apply_wstrb[15:8]  = new_value[15:8];
            if (strb[2]) apply_wstrb[23:16] = new_value[23:16];
            if (strb[3]) apply_wstrb[31:24] = new_value[31:24];
        end
    endfunction

    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            cfg_ready   <= 1'b0;
            cfg_rdata   <= 32'd0;
            cfg_error   <= 1'b0;
            control_reg <= 32'd0;
            error_reg   <= 32'd0;
            user_reg0   <= 32'd0;
            user_reg1   <= 32'd0;
        end else begin
            cfg_ready <= 1'b0;
            cfg_error <= 1'b0;
            cfg_rdata <= 32'd0;

            if (cfg_valid) begin
                cfg_ready <= 1'b1;

                if (!page_hit) begin
                    cfg_error <= 1'b1;
                end else if (cfg_write) begin
                    case (ofs)
                        `REG_OFS_ID_VERSION,
                        `REG_OFS_STATUS: begin
                            cfg_error <= 1'b1; // read-only
                        end
                        `REG_OFS_CONTROL: begin
                            control_reg <= apply_wstrb(control_reg, cfg_wdata, cfg_wstrb);
                        end
                        `REG_OFS_ERROR: begin
                            // W1C semantics on written byte lanes.
                            error_reg <= error_reg & ~apply_wstrb(32'd0, cfg_wdata, cfg_wstrb);
                        end
                        8'h10: user_reg0 <= apply_wstrb(user_reg0, cfg_wdata, cfg_wstrb);
                        8'h14: user_reg1 <= apply_wstrb(user_reg1, cfg_wdata, cfg_wstrb);
                        default: cfg_error <= 1'b1;
                    endcase
                end else begin
                    case (ofs)
                        `REG_OFS_ID_VERSION: cfg_rdata <= {MODULE_ID, VER_MAJOR, VER_MINOR};
                        `REG_OFS_CONTROL:    cfg_rdata <= control_reg;
                        `REG_OFS_STATUS: begin
                            cfg_rdata <= 32'd0;
                            cfg_rdata[`STATUS_BIT_ENABLED] <= control_reg[`CTRL_BIT_ENABLE];
                            cfg_rdata[`STATUS_BIT_READY]   <= 1'b1;
                            cfg_rdata[`STATUS_BIT_ERROR]   <= |error_reg;
                        end
                        `REG_OFS_ERROR: cfg_rdata <= error_reg;
                        8'h10: cfg_rdata <= user_reg0;
                        8'h14: cfg_rdata <= user_reg1;
                        default: begin
                            cfg_rdata <= 32'hDEAD_BEEF;
                            cfg_error <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end
endmodule
