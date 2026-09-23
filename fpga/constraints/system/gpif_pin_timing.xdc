# Shared GPIF physical fragment. The root must create board25 at 40 ns.
# AN65974 Rev *N Table 3: tCO <=7ns, tCFLG <=8ns, tCDH >=2ns;
# FPGA->FX3 setup 2ns; controls/address hold 0.5ns, DQ hold 0ns.
# Board-flight assumption: each clock/data/flag trace 0..0.5ns, not a PCB
# extraction. Input max adds BOTH clock and return flight; output setup uses
# data max minus clock min, and hold uses clock max minus data min.
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[0]}]
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[11]}]
set_property -dict {PACKAGE_PIN A12 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[20]}]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[29]}]
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[3]}]
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[1]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[27]}]
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[31]}]
set_property -dict {PACKAGE_PIN B12 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[23]}]
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[6]}]
set_property -dict {PACKAGE_PIN D11 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[24]}]
set_property -dict {PACKAGE_PIN E11 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[5]}]
set_property -dict {PACKAGE_PIN F12 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[15]}]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[9]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[8]}]
set_property -dict {PACKAGE_PIN K12 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[1]}]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[7]}]
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[0]}]
set_property -dict {PACKAGE_PIN J11 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[14]}]
set_property -dict {PACKAGE_PIN K11 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[2]}]
set_property -dict {PACKAGE_PIN G12 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[12]}]
set_property -dict {PACKAGE_PIN H12 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[10]}]
set_property -dict {PACKAGE_PIN G11 IOSTANDARD LVCMOS18} [get_ports {CYUSB_RSTN}]
set_property -dict {PACKAGE_PIN H11 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[7]}]
set_property -dict {PACKAGE_PIN G10 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_PCLK}]
set_property -dict {PACKAGE_PIN F9 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[4]}]
set_property -dict {PACKAGE_PIN G9 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[9]}]
set_property -dict {PACKAGE_PIN J10 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[3]}]
set_property -dict {PACKAGE_PIN K10 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[10]}]
set_property -dict {PACKAGE_PIN H8 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[5]}]
set_property -dict {PACKAGE_PIN J8 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[6]}]
set_property -dict {PACKAGE_PIN H9 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[12]}]
set_property -dict {PACKAGE_PIN J9 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[11]}]
set_property -dict {PACKAGE_PIN K8 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[16]}]
set_property -dict {PACKAGE_PIN L8 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[13]}]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[30]}]
set_property -dict {PACKAGE_PIN E10 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[28]}]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[4]}]
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[18]}]
set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[26]}]
set_property -dict {PACKAGE_PIN B10 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[2]}]
set_property -dict {PACKAGE_PIN C8 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[19]}]
set_property -dict {PACKAGE_PIN D8 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[21]}]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[25]}]
set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[22]}]
set_property -dict {PACKAGE_PIN E8 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_DQ[17]}]
set_property -dict {PACKAGE_PIN F8 IOSTANDARD LVCMOS18} [get_ports {FPGA_GPIF_CTL[8]}]
set gpif_clock_pin [get_pins {u_gpif/g_hw.u_pclk/C}]
if {[llength $gpif_clock_pin]!=1} {error "Missing GPIF ODDRE1 clock source"}
create_generated_clock -name gpif_pclk -source $gpif_clock_pin -divide_by 1 [get_ports FPGA_GPIF_PCLK]
set_clock_uncertainty -setup 0.200 [get_clocks gpif_pclk]
set_clock_uncertainty -hold 0.050 [get_clocks gpif_pclk]
set gpif_dq [get_ports {FPGA_GPIF_DQ[*]}]
set gpif_flags [get_ports {FPGA_GPIF_CTL[4] FPGA_GPIF_CTL[5] FPGA_GPIF_CTL[6] FPGA_GPIF_CTL[8]}]
set gpif_controls [get_ports {FPGA_GPIF_CTL[0] FPGA_GPIF_CTL[1] FPGA_GPIF_CTL[2] FPGA_GPIF_CTL[3] FPGA_GPIF_CTL[7] FPGA_GPIF_CTL[11] FPGA_GPIF_CTL[12]}]
set_input_delay -clock gpif_pclk -max 8.000 $gpif_dq
set_input_delay -clock gpif_pclk -min 2.000 $gpif_dq
set_input_delay -clock gpif_pclk -max 9.000 $gpif_flags
# Datasheet does not specify minimum flag tCO: conservative zero.
set_input_delay -clock gpif_pclk -min 0.000 $gpif_flags
set_output_delay -clock gpif_pclk -max 2.500 $gpif_dq
set_output_delay -clock gpif_pclk -min -0.500 $gpif_dq
set_output_delay -clock gpif_pclk -max 2.500 $gpif_controls
set_output_delay -clock gpif_pclk -min -1.000 $gpif_controls
# FX3 RESET_N is asynchronous; bound pad propagation, not a slave-FIFO setup spec.
set_output_delay -clock gpif_pclk -max 5.000 [get_ports CYUSB_RSTN]
set_output_delay -clock gpif_pclk -min 0.000 [get_ports CYUSB_RSTN]
# Keep effective FLAG and DQ capture/launch flops in the I/O banks.
set gpif_ioregs [get_cells -hier -quiet -filter {(NAME =~ u_gpif/u_master/* && (NAME =~ *rx_data_reg* || NAME =~ *tx_room_reg || NAME =~ *rx_present_reg || NAME =~ *tx_margin_reg || NAME =~ *rx_margin_reg)) || (NAME =~ u_gpif/pad_*_reg* && NAME !~ *dq_oe*)}]
set_property IOB TRUE $gpif_ioregs
