# AD5791 Rev F, Table 4, 1.71..3.3 V IOVCC. Serial capture is FALLING SCLK.
# SCLK is a stopped FSM output, not a free-running divided clock. Relative
# pad timing is signed off by scripts/check_dac_pin_timing.tcl after route.
# These zero external delays provide a SYS-clock referenced observation path
# and a one-SYS-cycle implementation target, NOT the DAC setup/hold contract.
# Remove DAC pads from any generic slow-GPIO/datapath-only constraint first.
set dac_pads [get_ports {dac_sclk[*] dac_sync_n[*] dac_sdin[*] dac_rst_n[*] dac_clr_n[*]}]
set dac_sys_pin [get_pins -hier -quiet -filter {NAME =~ *u_clock*g_hw*u_mmcm/CLKOUT0}]
set dac_sys_clock [get_clocks -of_objects $dac_sys_pin]
set_output_delay -clock $dac_sys_clock -max 0.000 $dac_pads
set_output_delay -clock $dac_sys_clock -min 0.000 $dac_pads
# 5 pF DAC input is typical; 10 pF total is an explicit integration load budget.
# PCB differential flight/threshold/33-ohm series-R effect is checked separately
# with a 1.0 ns allowance; these are budgets, not extracted board measurements.
set_load 10.000 $dac_pads
set_property IOSTANDARD LVCMOS18 $dac_pads
