`timescale 1ns/1ps

module cfg_bus_master_bfm #(
    parameter integer TIMEOUT_CYCLES = 1000
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg         cfg_valid,
    output reg         cfg_write,
    output reg  [31:0] cfg_addr,
    output reg  [31:0] cfg_wdata,
    output reg  [3:0]  cfg_wstrb,
    input  wire        cfg_ready,
    input  wire [31:0] cfg_rdata,
    input  wire        cfg_error
);
    integer wait_cycles;
    reg last_error;

    initial begin
        cfg_valid = 1'b0;
        cfg_write = 1'b0;
        cfg_addr  = 32'd0;
        cfg_wdata = 32'd0;
        cfg_wstrb = 4'd0;
        last_error = 1'b0;
    end

    task automatic wait_for_ready;
        begin : WAIT_BLOCK
            wait_cycles = 0;
            while (!cfg_ready) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
                if (wait_cycles >= TIMEOUT_CYCLES) begin
                    $display("CFG_BUS_TIMEOUT addr=0x%08h", cfg_addr);
                    $fatal(1);
                    disable WAIT_BLOCK;
                end
            end
            last_error = cfg_error;
        end
    endtask

    task automatic cfg_write32;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            cfg_valid = 1'b1;
            cfg_write = 1'b1;
            cfg_addr  = addr;
            cfg_wdata = data;
            cfg_wstrb = 4'hF;
            wait_for_ready;
            @(negedge clk);
            cfg_valid = 1'b0;
            cfg_write = 1'b0;
            cfg_wstrb = 4'd0;
        end
    endtask

    task automatic cfg_write_masked;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(negedge clk);
            cfg_valid = 1'b1;
            cfg_write = 1'b1;
            cfg_addr  = addr;
            cfg_wdata = data;
            cfg_wstrb = strb;
            wait_for_ready;
            @(negedge clk);
            cfg_valid = 1'b0;
            cfg_write = 1'b0;
            cfg_wstrb = 4'd0;
        end
    endtask

    task automatic cfg_read32;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            cfg_valid = 1'b1;
            cfg_write = 1'b0;
            cfg_addr  = addr;
            cfg_wdata = 32'd0;
            cfg_wstrb = 4'd0;
            wait_for_ready;
            data = cfg_rdata;
            @(negedge clk);
            cfg_valid = 1'b0;
        end
    endtask

    task automatic cfg_expect_error_read;
        input [31:0] addr;
        reg [31:0] unused;
        begin
            cfg_read32(addr, unused);
            if (!last_error)
                $fatal(1, "CFG_EXPECTED_ERROR_NOT_SEEN addr=0x%08h", addr);
        end
    endtask
endmodule
