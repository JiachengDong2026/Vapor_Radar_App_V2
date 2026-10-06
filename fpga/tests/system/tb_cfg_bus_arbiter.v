`timescale 1ns/1ps
module tb_cfg_bus_arbiter;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;reg [2:0] v=0,w=0;reg [95:0] addr=0,wd=0;reg [11:0] strb=12'hfff;
    wire [2:0] ready,err;wire [95:0] rd;
    wire mv,mw;wire [31:0] ma,md;wire [3:0] ms;
    reg mr=0;integer waits=0,i,total=0;integer count[0:2];reg [2:0] fire=0;
    reg stalled=0;reg [68:0] held;
    cfg_bus_arbiter dut(.sys_clk(clk),.rst_sys_n(rst),.s_valid(v),.s_write(w),.s_addr(addr),.s_wdata(wd),.s_wstrb(strb),
      .s_ready(ready),.s_error(err),.s_rdata(rd),.m_valid(mv),.m_write(mw),.m_addr(ma),.m_wdata(md),.m_wstrb(ms),
      .m_ready(mr),.m_error_code(4'd5),.m_error(ma[12]),.m_rdata(ma^32'h55aa));
    always @(negedge clk)if(rst)begin
      for(i=0;i<3;i=i+1)begin
        if(fire[i])count[i]=count[i]+1;
        v[i]=count[i]<16;w[i]=count[i]%2;addr[i*32 +: 32]=i*4096+count[i]*4;wd[i*32 +: 32]=count[i];
      end
      mr=mv && waits==2;
    end
    always @(posedge clk)if(rst)begin
      if(!mv || mr)waits<=0;else waits<=waits+1;
      fire=v & ready;
      if(stalled && (!mv || {mw,ma,md,ms}!==held))$fatal(1,"cfg stall");stalled=mv&&!mr;held={mw,ma,md,ms};
      if(mv && mr)total=total+1;
      for(i=0;i<3;i=i+1)if(fire[i])begin
        if(rd[i*32 +: 32]!=(addr[i*32 +: 32]^32'h55aa) || err[i]!=(i==1))$fatal(1,"cfg route %0d",i);
      end
    end
    initial begin
      for(i=0;i<3;i=i+1)count[i]=0;
      repeat(4)@(negedge clk);rst=1;
      wait(total==48);repeat(3)@(negedge clk);
      for(i=0;i<3;i=i+1)if(count[i]!=16)$fatal(1,"starved master");
      $display("tb_cfg_bus_arbiter_PASS transactions=%0d",total);$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
