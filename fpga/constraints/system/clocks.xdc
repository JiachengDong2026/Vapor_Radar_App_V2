# Read before synthesis so logic optimization uses the real clock objectives.
create_clock -name board25 -period 40.000 [get_ports CLK_FPGA_25MHZ]
# ADC3660 is inactive in the default dual-AD4630 build. Its optional legacy
# receive clock is created by the post-synthesis physical constraints.
