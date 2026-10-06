`timescale 1ns/1ps
// Derived from public cfg_bus_master_bfm: sample handshake ON the clock edge,
// not #1 after it, so a registered/delayed ready cannot finish one edge early.
module modbus_cfg_bfm(
    input wire clk,input wire rst_n,
    output reg cfg_valid=0,output reg cfg_write=0,output reg [31:0] cfg_addr=0,
    output reg [31:0] cfg_wdata=0,output reg [3:0] cfg_wstrb=0,
    input wire cfg_ready,input wire [31:0] cfg_rdata,input wire cfg_error
);
    reg last_error;
    reg [31:0] last_data;
    integer cycles;
    task transfer;
        input wr;input [31:0] addr,data;input [3:0] strb;
        begin
            @(negedge clk);cfg_valid=1;cfg_write=wr;cfg_addr=addr;cfg_wdata=data;cfg_wstrb=strb;
            cycles=0;
            begin:handshake
                forever begin
                    @(posedge clk);
                    if(cfg_ready)begin last_error=cfg_error;last_data=cfg_rdata;disable handshake;end
                    cycles=cycles+1;if(cycles>1000)$fatal(1,"CFG_TIMEOUT %h",addr);
                end
            end
            @(negedge clk);cfg_valid=0;cfg_write=0;cfg_wstrb=0;
        end
    endtask
    task write32;input [31:0] addr,data;begin transfer(1,addr,data,15);if(last_error)$fatal(1,"CFG_WRITE_ERROR %h",addr);end endtask
    task read32;input [31:0] addr;output [31:0] data;begin transfer(0,addr,0,0);data=last_data;if(last_error)$fatal(1,"CFG_READ_ERROR %h",addr);end endtask
    task expect_error;input wr;input [31:0] addr,data;begin transfer(wr,addr,data,15);if(!last_error)$fatal(1,"CFG_EXPECT_ERROR %h",addr);end endtask
    task masked;input [31:0] addr,data;input [3:0] strb;begin transfer(1,addr,data,strb);if(last_error)$fatal(1,"CFG_MASK_ERROR");end endtask
    task outside;input [31:0] addr;begin
        @(negedge clk);cfg_valid=1;cfg_addr=addr;cfg_write=0;
        repeat(3)begin @(posedge clk);if(cfg_ready || cfg_error)$fatal(1,"OUTSIDE_PAGE_RESPONSE");end
        @(negedge clk);cfg_valid=0;
    end endtask
endmodule
