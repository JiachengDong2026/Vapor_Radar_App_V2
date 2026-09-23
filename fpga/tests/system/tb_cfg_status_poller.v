`timescale 1ns/1ps
module tb_cfg_status_poller;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;
    wire v,w;wire [31:0] a,d;wire [3:0] strb;wire [95:0] status,errors;wire [2:0] present;wire [31:0] timeouts;
    wire ready=v && a!='h4008;
    wire [31:0] rd=a[7:0]==8'h08 ? (32'h13+a[15:8]):0;
    cfg_status_poller #(.N(3),.PAGE_MAP(24'h401000),.POLL_INTERVAL_TICKS(20),.TIMEOUT_TICKS(8)) dut(
      .sys_clk(clk),.rst_sys_n(rst),.cfg_valid(v),.cfg_write(w),.cfg_addr(a),.cfg_wdata(d),.cfg_wstrb(strb),
      .cfg_ready(ready),.cfg_error(1'b0),.cfg_rdata(rd),.module_status(status),.module_errors(errors),
      .module_present(present),.timeout_count(timeouts));
    always @(posedge clk)if(rst && v)begin
      if(w || strb!=15 || (a[7:0]!=8'h08 && a[7:0]!=8'h0c))$fatal(1,"unsafe poll");
    end
    initial begin
      repeat(4)@(negedge clk);rst=1;repeat(110)@(negedge clk);
      if(present!=3'b011 || status[31:0]!='h13 || status[63:32]!='h23 || errors[95:64]!=9 || timeouts<2)$fatal(1,"poll outcome present=%b timeouts=%0d",present,timeouts);
      $display("tb_cfg_status_poller_PASS timeouts=%0d",timeouts);$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
