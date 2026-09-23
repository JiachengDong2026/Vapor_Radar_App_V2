# Read before synthesis so logic optimization uses the real clock objectives.
create_clock -name board25 -period 40.000 [get_ports CLK_FPGA_25MHZ]
create_clock -name adc_dclk -period 20.000 [get_ports ADC_ADC3660_DCLK]
