`timescale 1ns/1ps
module tb_stepper_ctrl;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,en=1,v=0,w=0;
    reg [31:0] a=0,d=0;reg[3:0] strb=15;
    wire ready,err,pul,dir,ena,busy,done;
    wire [31:0] rd,id,pos,remn,errors;wire [3:0] ec;
    integer rises=0,falls=0,high_cycles=0,last_high=0,saved;
    reg prev=0,allow_truncate=0;
    stepper_ctrl #(.SYS_CLK_HZ(10000)) dut(
        .sys_clk(clk),.rst_sys_n(rst),.system_enable(en),.cfg_valid(v),.cfg_write(w),
        .cfg_addr(a),.cfg_wdata(d),.cfg_wstrb(strb),.cfg_ready(ready),.cfg_rdata(rd),.cfg_error(err),
        .pul(pul),.dir(dir),.ena(ena),.busy(busy),.done_pulse(done),.motion_id(id),
        .position(pos),.remaining(remn),.error_status(errors),.cfg_error_code(ec));
    task wr;input[31:0] addr,data;input[3:0] cause;integer n;begin
        @(negedge clk);v=1;w=1;a=addr;d=data;n=0;#1;
        while(!ready && n<150)begin @(negedge clk);n=n+1;#1;end
        if(!ready || err!==(cause!=0) || (err && ec!=cause))
            $fatal(1,"write %h data%h error%0d expected%0d",addr,data,ec,cause);
        @(negedge clk);v=0;w=0;
    end endtask
    task rd_eq;input[31:0] addr,value;begin
        @(negedge clk);v=1;w=0;a=addr;#1;
        if(!ready || err || rd!==value)$fatal(1,"read %h got%h expected%h",addr,rd,value);
        @(negedge clk);v=0;
    end endtask
    task move;input[31:0] steps;begin wr('h6710,steps,0);wr('h672c,1,0);end endtask
    task idle;integer n;begin n=0;while(busy && n<10000)begin @(negedge clk);n=n+1;end
        if(busy)$fatal(1,"motion timeout");repeat(5)@(negedge clk);end endtask
    always @(negedge clk)begin
        if(pul && !prev)begin rises=rises+1;high_cycles=0;if(ena)$fatal(1,"pulse while disabled");end
        if(pul)high_cycles=high_cycles+1;
        if(!pul && prev)begin
            falls=falls+1;last_high=high_cycles;
            if(!allow_truncate && high_cycles<13)$fatal(1,"short pulse");
        end
        prev=pul;
    end
    initial begin
        repeat(4)@(negedge clk);rst=1;repeat(3)@(negedge clk);
        if(!ena || pul || busy)$fatal(1,"boot must disable DM422");
        rd_eq('h6700,'h00470200);rd_eq('h6730,4);rd_eq('h671c,100);
        wr('h672c,1,11);wr('h6710,0,7);wr('h6710,401,7);wr('h6710,-401,7);
        wr('h6714,19,7);wr('h6714,401,7);wr('h6718,50,6);wr('h671c,100,6);
        wr('h6730,0,7);wr('h6738,0,7);
        wr('h6738,1,0);wr('h6704,1,0);repeat(4)@(negedge clk);
        if(ena)$fatal(1,"enable after real heartbeat");
        wr('h6714,100,0);rd_eq('h6718,50);
        move(3);if(!busy || pul)$fatal(1,"launch/setup");
        wr('h6710,9,8);wr('h6714,200,8);wr('h6730,4,8);
        idle;if(rises!=3 || falls!=3 || pos!=3 || remn!=0 || ena || id!=1)$fatal(1,"finite positive/hold");
        move(-2);idle;if(rises!=5 || pos!=1 || !dir || id!=2)$fatal(1,"reverse accounting");
        wr('h6714,400,0);rd_eq('h6718,13);move(1);idle;
        if(last_high!=13 || rises!=6)$fatal(1,"400Hz ceiling");
        saved=rises;move(10);repeat(8)@(negedge clk);wr('h672c,2,0);idle;
        if(rises!=saved || ena)$fatal(1,"stop during setup holds without pulses");
        move(10);wait(pul);wr('h672c,2,0);idle;
        if(rises!=saved+1 || remn!=9 || ena || last_high!=13)$fatal(1,"normal high stop");
        // A late heartbeat revives liveness but does not clear a latched fault.
        repeat(21000)@(negedge clk);
        if(!ena || busy || pul || !(errors&1))$fatal(1,"watchdog release");
        wr('h6738,1,0);repeat(4)@(negedge clk);if(!ena)$fatal(1,"timeout auto enabled");
        wr('h672c,1,11);wr('h6704,0,0);repeat(4)@(negedge clk);
        wr('h670c,'hffffffff,0);wr('h6704,1,0);repeat(4)@(negedge clk);
        if(ena || busy)$fatal(1,"explicit recovery");
        saved=rises;repeat(100)@(negedge clk);if(rises!=saved)$fatal(1,"replayed move");
        move(10);wait(pul);allow_truncate=1;en=0;repeat(5)@(negedge clk);
        if(!ena || pul || busy)$fatal(1,"global disable immediate");
        en=1;repeat(10)@(negedge clk);if(!ena || busy)$fatal(1,"global reconnect rearmed");
        wr('h672c,3,0);rd_eq('h6724,0);
        $display("tb_stepper_ctrl_PASS register_adapter finite_reverse bounds settle normal_stop watchdog explicit_recovery no_replay EN_high_disable");$finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
