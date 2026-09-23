# OOC integration contract: 100 MHz synchronous cfg/time/reference interfaces.
create_clock -name sys_clk -period 10.000 [get_ports sys_clk]
set_clock_uncertainty -setup 0.200 [get_clocks sys_clk]
# Same sys_clk launch/capture contract: 50 ps differential hold uncertainty.
# Integration must validate this clock relationship; no independent clock is assumed.
set_clock_uncertainty -hold 0.050 [get_clocks sys_clk]
set in_ports [get_ports -filter {DIRECTION == IN && NAME != sys_clk}]
set_input_delay -clock sys_clk -max 1.000 $in_ports
set_input_delay -clock sys_clk -min 0.200 $in_ports
set_output_delay -clock sys_clk -max 1.000 [get_ports -filter {DIRECTION == OUT}]
set_output_delay -clock sys_clk -min 0.200 [get_ports -filter {DIRECTION == OUT}]
# No blanket false paths. SDO is unused because readback is deliberately unsupported.
