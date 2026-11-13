`timescale 1ns/1ps
module tb_dm422_pc_ctrl;
    reg clk=0, rst_n=0;
    reg [63:0] control=0;
    wire pul, dir, disable_motor;
    wire [31:0] status;
    integer rises=0, falls=0, n, before_count, high_ticks=0;
    reg previous=0, heartbeat_on=1;
    always #5 clk=~clk;
    dm422_pc_ctrl #(.CLK_HZ(8000),.WATCHDOG_CYCLES(800)) dut
        (.clk(clk),.rst_n(rst_n),.control(control),.motor_pul(pul),
         .motor_dir(dir),.motor_disable(disable_motor),.status(status));
    always @(negedge clk) begin
        if (pul && !previous) rises=rises+1;
        if (!pul && previous) falls=falls+1;
        previous=pul;
    end
    // Independent host heartbeat; suspend to simulate a crashed host.
    initial forever begin
        repeat(100) @(negedge clk);
        if (heartbeat_on) control[4]=~control[4];
    end
    task cycles; input integer count; begin repeat(count) @(negedge clk); #1; end endtask
    task check; input condition; input [639:0] message; begin
        if (!condition) begin $display("FAIL %0s status=%h",message,status); $finish; end
    end endtask
    task move; input integer count; input integer half; input direction; begin
        @(negedge clk); control[31:16]=count; control[63:32]=half;
        control[3]=direction; control[1]=~control[1]; cycles(2);
    end endtask
    task await_idle; begin
        n=0;
        while(status[1] && n<10000) begin cycles(1); n=n+1; end
        check(n<10000,"completion timeout");
    end endtask
    initial begin
        cycles(4); rst_n=1; cycles(110);
        check(disable_motor && !pul && rises==0,"boot disabled");
        control[0]=1; cycles(3); check(!disable_motor,"enable after heartbeat");
        move(4,40,1);
        check(status[1] && dir,"move accepted and direction set");
        cycles(60); check(!pul,"10ms direction setup enforced");
        // Mutating config and a second move while busy must not change trajectory.
        move(1,10,0); check(dir,"direction remains latched while busy");
        await_idle;
        check(rises==4 && falls==4 && status[23:8]==4 && status[2],"exact finite move");
        check(!disable_motor,"normal completion holds motor");
        move(0,40,0); check(status[4] && !status[1],"zero count rejected");
        move(401,40,0); check(status[4] && !status[1],"count over limit rejected");
        move(1,9,0); check(status[4] && !status[1],"speed over limit rejected");
        move(1,201,0); check(status[4] && !status[1],"speed below limit rejected");
        before_count=rises; move(1,10,0); await_idle;
        check(rises==before_count+1 && !dir && !status[4],"400Hz boundary and reverse");
        before_count=rises; move(1,200,1); await_idle;
        check(rises==before_count+1,"20Hz boundary");
        before_count=rises; move(10,40,0); cycles(10);
        control[2]=~control[2]; await_idle;
        check(rises==before_count && status[7] && !disable_motor,"stop during setup");
        move(10,40,1);
        while(!pul) cycles(1);
        high_ticks=0; control[2]=~control[2];
        while(pul) begin cycles(1); high_ticks=high_ticks+1; end
        await_idle; before_count=rises; cycles(100);
        check(high_ticks==40 && rises==before_count && status[7],"stop completes high pulse");
        move(10,40,0); while(!pul) cycles(1);
        control[0]=0; cycles(2);
        check(disable_motor && !pul && !status[1],"disable stops immediately");
        control[0]=1; cycles(2); move(400,40,0);
        heartbeat_on=0; cycles(810);
        check(disable_motor && status[3] && !status[1],"watchdog stops and releases");
        heartbeat_on=1; cycles(110);
        check(disable_motor && status[3],"heartbeat cannot auto restart fault");
        control[0]=0; cycles(3); control[0]=1; cycles(3);
        check(!disable_motor && !status[3] && !status[1],"explicit recovery without movement");
        before_count=rises; cycles(200); check(rises==before_count,"no replay on reconnect");
        $display("PASS dm422_pc_ctrl boot/moves/bounds/latching/stop/disable/watchdog/recovery");
        $finish;
    end
    initial begin #2000000; $display("FAIL global timeout"); $finish; end
endmodule
