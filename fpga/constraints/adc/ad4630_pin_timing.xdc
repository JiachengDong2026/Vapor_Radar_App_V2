# Reusable AD4630 H=2 capture timing contract, SYS=100 MHz.
# The multi-cycle constraints reflect the real SCK-fall to capture interval.
# Routed end-to-end signoff MUST also run check_ad4630_pin_timing.tcl.
# Input16ns is an implementation allocation, not a substituted ADC tDSDO:
# the checker measures actual outbound SCK/CS and inbound SDO delays.
set ad4630_sys [get_clocks -of_objects [get_pins -hier -filter {NAME =~ */cap_sck_reg/C}]]
set ad4630_outputs [get_ports {ADC_AD4630_SDI ADC_AD4630_RSTN ADC_AD4630_CNV ADC_AD4630_CSN ADC_AD4630_SCK}]
set_output_delay -clock $ad4630_sys -max 0.000 $ad4630_outputs
set_output_delay -clock $ad4630_sys -min 0.000 $ad4630_outputs
set_load 10.000 $ad4630_outputs
set_input_delay -clock $ad4630_sys -max 16.000 [get_ports {ADC_AD4630_SDO[*]}]
set_input_delay -clock $ad4630_sys -min 1.400 [get_ports {ADC_AD4630_SDO[*]}]
set ad4630_sample_regs [get_cells -hier -filter {NAME =~ */shift_word_reg*}]
set ad4630_spi_regs [get_cells -hier -filter {NAME =~ */u_spi/read_data_reg*}]
set_multicycle_path 2 -setup -from [get_ports {ADC_AD4630_SDO[*]}] -to $ad4630_sample_regs
set_multicycle_path 1 -hold -from [get_ports {ADC_AD4630_SDO[*]}] -to $ad4630_sample_regs
set_multicycle_path 10 -setup -from [get_ports {ADC_AD4630_SDO[*]}] -to $ad4630_spi_regs
set_multicycle_path 9 -hold -from [get_ports {ADC_AD4630_SDO[*]}] -to $ad4630_spi_regs
