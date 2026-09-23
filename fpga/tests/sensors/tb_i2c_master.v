`timescale 1ns/1ps
module tb_i2c_master;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,v=0;wire ready,done,busy;
    reg [6:0] addr=7'h76;reg [5:0] wl=1,rl=6;reg [255:0] wd=4;
    wire [255:0] rd;wire [2:0] error;wire scl_low,sda_low;
    tri1 scl,sda;reg hold_scl=0,hold_sda=0,nack=0;
    assign scl=(scl_low||hold_scl)?0:1'bz;assign sda=(sda_low||hold_sda)?0:1'bz;
    wire [31:0] transactions,measurements;wire [7:0] command;
    i2c_master #(.SYS_CLK_HZ(1000000),.I2C_HZ(100000),.TIMEOUT_TICKS(5000))dut(
        .sys_clk(clk),.rst_sys_n(rst),.req_valid(v),.req_ready(ready),.req_addr(addr),
        .req_write_len(wl),.req_read_len(rl),.req_write_data(wd),.done(done),.error(error),.read_data(rd),
        .scl_i(scl),.sda_i(sda),.scl_drive_low(scl_low),.sda_drive_low(sda_low),.busy(busy));
    i2c_sensor_model #(.ADDRESS(7'h76),.IS_BMP(1))model(.scl(scl),.sda(sda),.rst_n(rst),.inject_nack(nack),
        .inject_bad_crc(1'b0),.transactions(transactions),.measurements(measurements),.last_command(command));
    task request;begin @(negedge clk);wait(ready);v=1;@(negedge clk);v=0;end endtask
    task result;input [2:0] expected;begin wait(done);#1;if(error!==expected)$fatal(1,"error=%d wanted=%d",error,expected);@(negedge clk);end endtask
    integer pulses=0;reg recovery_test=0;
    always @(posedge scl)if(recovery_test)pulses=pulses+1;
    initial begin
        repeat(10)@(negedge clk);rst=1;repeat(10)@(negedge clk);
        request;result(0);if(rd[47:0]!=48'habcdef123456)$fatal(1,"repeated START burst %h",rd);
        nack=1;request;result(1);nack=0;
        // Clock stretch shorter than watchdog must preserve the transaction.
        request;wait(scl_low);hold_scl=1;repeat(100)@(negedge clk);hold_scl=0;result(0);
        // A stuck SDA at START receives nine recovery clocks plus STOP.
        @(negedge clk);hold_sda=1;repeat(10)@(negedge clk);recovery_test=1;request;result(4);
        recovery_test=0;if(pulses<9)$fatal(1,"recovery clocks %d",pulses);hold_sda=0;
        repeat(10)@(negedge clk);request;result(0);
        @(negedge clk);hold_scl=1;repeat(10)@(negedge clk);request;result(2);hold_scl=0;
        repeat(10)@(negedge clk);wl=33;request;result(3);wl=1;
        // Reset abort releases both open-drain outputs.
        request;wait(scl_low);@(negedge clk);rst=0;repeat(3)@(negedge clk);
        if(scl_low||sda_low||busy)$fatal(1,"reset lines");rst=1;
        repeat(10)@(negedge clk);request;result(0);
        $display("I2C_MASTER_REGRESSION_PASS recovery_clocks=%0d",pulses);$finish;
    end
    initial begin #1000000;$fatal(1,"watchdog");end
endmodule
