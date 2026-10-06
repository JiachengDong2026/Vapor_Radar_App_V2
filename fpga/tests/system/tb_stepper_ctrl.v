`timescale 1ns/1ps
module tb_stepper_ctrl;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,en=1,v=0,w=0;
    reg [31:0] a=0,d=0;
    reg [3:0] strb=15;
    wire ready,err,pul,dir,ena,busy,done;
    wire [31:0] rd,id,pos,remn,errors;
    wire [3:0] error_code;
    integer cycle=0,rises=0,high_start=0,low_start=0,ena_start=0,last_dir=0;
    integer motion_rises=0,direction_changes=0,ena_stops=0,dir_stops=0,high_stops=0,low_stops=0;
    integer saved_rises,saved_id;
    reg prev_pul=0,prev_ena=0,prev_dir=0,monitor=0;
    reg saved_dir;
    stepper_ctrl dut(
      .sys_clk(clk),.rst_sys_n(rst),.system_enable(en),.cfg_valid(v),.cfg_write(w),
      .cfg_addr(a),.cfg_wdata(d),.cfg_wstrb(strb),.cfg_ready(ready),.cfg_rdata(rd),.cfg_error(err),
      .pul(pul),.dir(dir),.ena(ena),.busy(busy),.done_pulse(done),.motion_id(id),
      .position(pos),.remaining(remn),.error_status(errors),.cfg_error_code(error_code));
    // Actual nominal SYS100MHz; shorten every measured pin interval for the
    // +100ppm oscillator limit and 50ns differential pad/PCB/edge budget.
    function real pin_interval;
        input integer ticks;
        begin pin_interval=ticks*10.0/1.0001-50.0;end
    endfunction
    task write_reg;input [31:0] addr,data;input expected_error;integer timeout;begin
      @(negedge clk);v=1;w=1;a=addr;d=data;timeout=0;
      @(posedge clk);
      while(!ready && timeout<200)begin @(posedge clk);timeout=timeout+1;end
      if(!ready || err!==expected_error)$fatal(1,"cfg write %h data%0d error%b timeout%0d",addr,data,err,timeout);
      if(expected_error && error_code==0)$fatal(1,"missing cfg cause");
      @(negedge clk);v=0;w=0;
    end endtask
    task read_expect;input [31:0] addr,value;begin
      @(negedge clk);v=1;w=0;a=addr;#1;
      if(!ready || err || rd!==value)$fatal(1,"read %h got%0d expected%0d",addr,rd,value);
      @(negedge clk);v=0;
    end endtask
    task start_motion;input [31:0] count;begin
      write_reg('h6710,count,0);write_reg('h672c,1,0);
      if(!busy || !ena || pul)$fatal(1,"START must assert only ENA");
    end endtask
    task finish_stop;input integer expected_rises;begin
      wait(!busy);@(negedge clk);
      if(rises!=expected_rises || pul || ena)$fatal(1,"STOP emitted extra/missing pulse %0d/%0d",rises,expected_rises);
    end endtask
    always @(posedge clk)begin
      #1;cycle=cycle+1;
      if(monitor)begin
        if(ena && !prev_ena)begin ena_start=cycle;motion_rises=0;end
        if(dir!=prev_dir)begin
          if(!ena || pin_interval(cycle-ena_start)<5000000.0)$fatal(1,"ENA must precede DIR by 5ms");
          if(pul)$fatal(1,"DIR changed during pulse");
          last_dir=cycle;direction_changes=direction_changes+1;
        end
        if(pul && !prev_pul)begin
          if(!ena || pin_interval(cycle-last_dir)<5000.0)$fatal(1,"DIR must precede PUL by 5us");
          if(motion_rises==0 && (cycle-ena_start)*10.0/1.0001-100.0<5005000.0)$fatal(1,"independent ENA/DIR guards missing");
          if(motion_rises>0 && pin_interval(cycle-low_start)<2500.0)$fatal(1,"short pin low");
          rises=rises+1;motion_rises=motion_rises+1;high_start=cycle;
        end
        if(!pul && prev_pul)begin
          if(pin_interval(cycle-high_start)<2500.0)$fatal(1,"short pin high");low_start=cycle;
        end
        if(!ena && prev_ena && motion_rises>0 && (pul || pin_interval(cycle-low_start)<2500.0))$fatal(1,"ENA early release");
      end
      prev_pul=pul;prev_ena=ena;prev_dir=dir;
    end
    initial begin
      repeat(4)@(negedge clk);rst=1;monitor=1;
      read_expect('h6718,256);read_expect('h671c,506);
      write_reg('h6714,0,1);write_reg('h6714,195313,1);
      write_reg('h6718,255,1);write_reg('h6718,256,0);
      write_reg('h671c,505,1);write_reg('h671c,506,0);
      write_reg('h6714,195312,0);read_expect('h6714,195312);
      write_reg('h6718,257,1);
      write_reg('h6714,190000,0);read_expect('h6714,190114);
      write_reg('h6718,270,0);write_reg('h6718,271,1);
      write_reg('h6714,195312,1);
      read_expect('h6714,190114);
      write_reg('h6718,256,0);write_reg('h6714,195312,0);
      write_reg('h6720,1,1);write_reg('h672c,1,1);
      write_reg('h6704,1,0);
      start_motion(3);write_reg('h6710,5,1);wait(!busy);@(negedge clk);
      if(rises!=3 || pos!=3 || remn!=0 || id!=1)$fatal(1,"positive count");
      start_motion(-2);wait(!busy);@(negedge clk);
      if(rises!=5 || pos!=1 || remn!=0 || id!=2)$fatal(1,"negative count");
      saved_rises=rises;saved_dir=dir;start_motion(100);
      repeat(20)@(negedge clk);write_reg('h672c,2,0);finish_stop(saved_rises);
      if(dir!=saved_dir)$fatal(1,"ENA-wait STOP changed DIR");ena_stops=ena_stops+1;
      saved_rises=rises;start_motion(100);wait(!dir);write_reg('h672c,2,0);
      finish_stop(saved_rises);dir_stops=dir_stops+1;
      saved_rises=rises;start_motion(-100);wait(pul);write_reg('h672c,2,0);
      finish_stop(saved_rises+1);high_stops=high_stops+1;
      if(remn!=99)$fatal(1,"HIGH STOP remaining");
      saved_rises=rises;start_motion(100);wait(pul);wait(!pul);write_reg('h672c,2,0);
      finish_stop(saved_rises+1);low_stops=low_stops+1;
      if(remn!=99 || pos!=1)$fatal(1,"LOW STOP count");
      saved_rises=rises;saved_dir=dir;start_motion(-100);
      repeat(10)@(negedge clk);en=0;finish_stop(saved_rises);
      if(dir!=saved_dir)$fatal(1,"system disable changed DIR");en=1;
      write_reg('h672c,3,0);if(pos!=0)$fatal(1,"zero");
      saved_id=id;saved_dir=dir;write_reg('h6710,0,0);write_reg('h672c,1,0);
      if(busy || id!=saved_id+1 || dir!=saved_dir || rises!=7)$fatal(1,"zero target");
      write_reg('h6704,0,0);monitor=0;write_reg('h6730,7,0);
      if(pul!=1 || ena!=1)$fatal(1,"polarity");
      @(negedge clk);v=1;a='h6800;#1;if(ready || err)$fatal(1,"foreign page");v=0;
      write_reg('h670c,32'hffffffff,0);if(errors!=0)$fatal(1,"W1C");
      if(direction_changes<4)$fatal(1,"both directions not covered");
      $display("tb_stepper_ctrl_PASS SYS100MHz ppm100 IO_budget50ns ENA500056 DIR506 HIGH_LOW256 max_freq195312 quantized190114 positive_negative STOP_stages=%0d/%0d/%0d/%0d",ena_stops,dir_stops,high_stops,low_stops);$finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
