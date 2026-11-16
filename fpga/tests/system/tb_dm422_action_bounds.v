`timescale 1ns/1ps
module tb_dm422_action_bounds;
 reg clk=0,rst=0,av=0;always #5 clk=~clk;
 reg [127:0] args=0;
 wire ar,v,w,r,e,busy;wire [31:0] status,a,d,rd;wire [3:0] strb,ec;
 wire motorhit=a[31:8]==24'h67;wire mr,me;wire [31:0] mrd;wire [3:0] mec;
 reg [31:0] global_control=1;
 integer targets=0,starts=0;reg [31:0] last_target;
 assign r=motorhit?mr:v;assign e=motorhit?me:0;assign ec=motorhit?mec:0;assign rd=motorhit?mrd:global_control;
 action_controller dut(.sys_clk(clk),.rst_sys_n(rst),.action_valid(av),.action_ready(ar),.action_status(status),
 .action_code(16'd12),.action_source(16'h47),.action_args(args),.cfg_valid(v),.cfg_write(w),.cfg_addr(a),.cfg_wdata(d),.cfg_wstrb(strb),
 .cfg_ready(r),.cfg_error(e),.cfg_error_code(ec),.cfg_rdata(rd),.channel_datapath_idle(2'b11),.sensor_datapath_idle(1'b1),.stop_flush(),.acquisition_running(),.busy());
 stepper_ctrl #(.SYS_CLK_HZ(10000)) motor(.sys_clk(clk),.rst_sys_n(rst),.system_enable(global_control[0]),
 .cfg_valid(v&&motorhit),.cfg_write(w),.cfg_addr(a),.cfg_wdata(d),.cfg_wstrb(strb),.cfg_ready(mr),.cfg_error(me),.cfg_error_code(mec),.cfg_rdata(mrd),
 .pul(),.dir(),.ena(),.busy(busy),.done_pulse(),.motion_id(),.position(),.remaining(),.error_status());
 always @(posedge clk)if(rst&&v&&r&&w&&!e)begin
 if(a==4)global_control<=d;
 if(a=='h6710)begin targets=targets+1;last_target=d;end
 if(a=='h672c&&d==1)starts=starts+1;
 end
 task act;input [31:0] op,val,expected;begin
 @(negedge clk);args={64'd0,val,op};av=1;
 wait(ar);@(negedge clk);if(status!==expected)$fatal(1,"action status %d expected %d",status,expected);
 av=0;repeat(3)@(negedge clk);
 end endtask
 initial begin
 repeat(5)@(negedge clk);rst=1;
 act(5,0,0);act(4,1,0);
 act(1,5000,0);if(targets!=1||starts!=1||last_target!=5000||!busy)$fatal(1,"positive signed passthrough");
 act(2,0,0);act(1,-5000,0);if(targets!=2||starts!=2||last_target!=-32'd5000||!busy)$fatal(1,"negative signed passthrough");
 act(2,0,0);
 act(1,0,7);act(1,5001,7);act(1,-5001,7);
 if(targets!=2||starts!=2||busy)$fatal(1,"rejected target started motion");
 $display("TEST_PASS tb_dm422_action_bounds real action12 adapter signed boundaries no invalid launch");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
