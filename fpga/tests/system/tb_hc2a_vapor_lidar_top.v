`timescale 1ns/1ps
// The shared top regression checks all 73 USB command responses. HC2A mode
// additionally checks the complete 0x00410106 ID, including its version bytes.
module tb_hc2a_vapor_lidar_top;
    tb_vapor_lidar_top #(.HC2A_ENABLE(1)) system_test();
endmodule
