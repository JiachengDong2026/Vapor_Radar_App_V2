`timescale 1ns/1ps
module tb_dm422_real_sys100;
    reg clk=0,rst_n=0;
    reg [63:0] control=0;
    wire pul,dir,disable_motor;
    wire [31:0] status;
    realtime rise_at,fall_at,command_at;
    integer count=0;
    always #5 clk=~clk;
    dm422_pc_ctrl #(.CLK_HZ(100000000),.WATCHDOG_CYCLES(200000000)) dut(.clk(clk),.rst_n(rst_n),.control(control),
        .motor_pul(pul),.motor_dir(dir),.motor_disable(disable_motor),.status(status));
    always @(posedge pul) begin
        if(count==0 && $realtime-command_at < 10000000.0) begin
            $display("FAIL direction setup below 10ms");$finish;
        end
        if(count>0 && $realtime-rise_at != 10000000.0) begin
            $display("FAIL period is not 10ms");$finish;
        end
        rise_at=$realtime;count=count+1;
    end
    always @(negedge pul) if(rst_n && count>0) begin
        if($realtime-rise_at != 5000000.0) begin
            $display("FAIL pulse width is not 5ms");$finish;
        end
        fall_at=$realtime;
    end
    initial begin
        #100;rst_n=1;#100;control[4]=1;#100;control[0]=1;#100;
        control[63:32]=500000;control[31:16]=2;control[3]=1;control[1]=1;
        command_at=$realtime;
        #100; wait(!status[1]);
        if(count!=2 || status[23:8]!=2 || !status[2] || disable_motor)
            $display("FAIL pulse count or final state");
        else $display("PASS pc real 100MHz: 100Hz, 5ms high/low, >=10ms setup, two pulses");
        $finish;
    end
    initial begin #100000000;$display("FAIL timeout");$finish;end
endmodule
