# Timing contract for the complete physical XCKU11P top. Pin locations are in
# board_pins.xdc, generated from the complete original UCF (source is read-only).
if {![llength [get_clocks -quiet board25]]} {create_clock -name board25 -period 40.000 [get_ports CLK_FPGA_25MHZ]}
set_property PHASESHIFT_MODE WAVEFORM [get_cells -hier -filter {REF_NAME =~ MMCME*}]
set sysclock [get_clocks -of_objects [get_pins u_clock/g_hw.u_mmcm/CLKOUT0]]
set gpifclock [get_clocks -of_objects [get_pins u_clock/g_hw.u_mmcm/CLKOUT1]]
set_clock_uncertainty -setup 0.200 [get_clocks {board25}]
set_clock_uncertainty -hold 0.050 [get_clocks {board25}]

# AD4630 H2 capture/config and complete routed round-trip contract is sourced below.
# BUSY remains an asynchronous handshake input.

# Discover the optional legacy ADC3660 PHY. The formal dual-AD4630 build
# has no high-speed capture clock or data-domain CDC endpoints.
set adc3660_rx_pin [get_pins -hier -quiet -filter {NAME =~ */u_adc1/u_rx/g_hw.u_mmcm/CLKOUT0}]
set adc1root ""
if {[llength $adc3660_rx_pin]} {
    if {[llength $adc3660_rx_pin]!=1} {error "Ambiguous ADC3660 PHY"}
    set adc1root [file dirname [file dirname [file dirname [get_property NAME $adc3660_rx_pin]]]]
# ADC3660 two-lane DDR input, 50 MHz DCLK with 90-degree local receive MMCM.
if {![llength [get_clocks -quiet adc_dclk]]} {create_clock -name adc_dclk -period 20.000 [get_ports ADC_ADC3660_DCLK]}
set rxclock [get_clocks -of_objects [get_pins "$adc1root/u_rx/g_hw.u_mmcm/CLKOUT0"]]
set_input_delay -clock adc_dclk -min -0.55 [get_ports {ADC_ADC3660_DA5 ADC_ADC3660_DA6 ADC_ADC3660_FCLK}]
set_input_delay -clock adc_dclk -max 0.35 [get_ports {ADC_ADC3660_DA5 ADC_ADC3660_DA6 ADC_ADC3660_FCLK}]
set_input_delay -clock adc_dclk -clock_fall -add_delay -min -0.55 [get_ports {ADC_ADC3660_DA5 ADC_ADC3660_DA6 ADC_ADC3660_FCLK}]
set_input_delay -clock adc_dclk -clock_fall -add_delay -max 0.35 [get_ports {ADC_ADC3660_DA5 ADC_ADC3660_DA6 ADC_ADC3660_FCLK}]
# The external ADC clock is not guaranteed phase coherent with sys_clk. Bound
# all CDC datapaths; separately waive hold because these clocks are unrelated.
set_max_delay 10 -datapath_only -from $sysclock -to $rxclock
set_max_delay 20 -datapath_only -from $rxclock -to $sysclock
set_false_path -hold -from $sysclock -to $rxclock
set_false_path -hold -from $rxclock -to $sysclock
# FCLK also feeds an independent SYS diagnostic synchronizer. Only its first
# capture is asynchronous; the FCLK-to-IDDRE1 DDR timing above remains active.
set_false_path -from [get_ports ADC_ADC3660_FCLK] -to [get_pins "$adc1root/fc_meta_reg/D"]
}
# MMCM LOCKED is asynchronous status, captured through dedicated two-flop chains.
# Vivado 2020.2 does not allow an MMCM LOCKED output as a -from startpoint.
# These exact first-stage flops capture only the respective asynchronous status.
set locked_endpoints [list u_clock_health/locked_meta_reg/D]
if {$adc1root ne ""} {lappend locked_endpoints "$adc1root/lock_meta_reg/D"}
foreach endpoint $locked_endpoints {
    set capture [get_pins -quiet $endpoint]
    if {[llength $capture]!=1 || ![get_property ASYNC_REG [get_cells -of_objects $capture]]} {error "Missing LOCKED first-stage synchronizer $endpoint"}
    set_false_path -to $capture
}
# Gray MSB may share the identical binary-pointer flop after synthesis.
# Trace each first-stage D instead of dropping that bit through name filtering.
proc gray_actual_launch {label pattern expected_count} {
    set first [get_pins -of_objects [get_cells -hier -filter "NAME =~ $pattern"] -filter {REF_PIN_NAME == D}]
    if {[llength $first]!=$expected_count} {error "$label expected $expected_count first-stage D pins, got [llength $first]"}
    set launch {}
    foreach pin $first {
        set capture [get_cells -of_objects $pin]
        set async [get_property ASYNC_REG $capture]
        if {![string is boolean -strict $async] || !$async} {error "$label missing ASYNC_REG on $pin"}
        set start [all_fanin -flat -startpoints_only -to $pin]
        if {[llength $start]!=1} {error "$label $pin has [llength $start] launch points: $start"}
        set cell [get_cells -of_objects $start]
        if {[get_property REF_PIN_NAME $start] ne "C" || ![string match FD* [get_property REF_NAME $cell]]} {error "$label unexpected launch $start"}
        lappend launch $start
    }
    set launch [lsort -unique $launch]
    if {[llength $launch]!=$expected_count} {error "$label expected $expected_count distinct launches, got [llength $launch]"}
    set_bus_skew 10.000 -from $launch -to $first
    puts "GRAY_SKEW_COVERAGE $label bits=$expected_count launches=$launch"
}
set gray_specs {
    transport_rx_read {u_transport/u_rx/u_fifo/rd_gray_w1_reg*} 12
    transport_rx_write {u_transport/u_rx/u_fifo/wr_gray_r1_reg*} 12
    transport_tx_read {u_transport/u_tx/u_fifo/rd_gray_w1_reg*} 12
    transport_tx_write {u_transport/u_tx/u_fifo/wr_gray_r1_reg*} 12
    transport_rx_level_read {u_transport/u_rx/rd_gray_meta_reg*} 12
    transport_rx_level_write {u_transport/u_rx/wr_gray_meta_reg*} 12
    transport_tx_level_read {u_transport/u_tx/rd_gray_meta_reg*} 12
    transport_tx_level_write {u_transport/u_tx/wr_gray_meta_reg*} 12
    clock_fault {u_clock_fault_cdc/gray_meta_reg*} 32
    usb0 {u_usb_counter0/gray_meta_reg*} 32
    usb1 {u_usb_counter1/gray_meta_reg*} 32
    usb2 {u_usb_counter2/gray_meta_reg*} 32
    usb3 {u_usb_counter3/gray_meta_reg*} 32
    usb4 {u_usb_counter4/gray_meta_reg*} 32
}
if {$adc1root ne ""} {
    lappend gray_specs adc_read "$adc1root/u_word_cdc/rd_gray_w1_reg*" 9
    lappend gray_specs adc_write "$adc1root/u_word_cdc/wr_gray_r1_reg*" 9
}
foreach {label pattern bits} $gray_specs {
    # Occupancy Gray counters are separate from u_fifo pointers. The unused
    # GPIF TX-level view may remove only its write-counter synchronizer.
    if {![llength [get_cells -hier -quiet -filter "NAME =~ $pattern"]] && ([string match usb* $label] || $label eq "transport_tx_level_write")} {
        puts "GRAY_SKEW_COVERAGE $label optimized_away"
    } else {
        gray_actual_launch $label $pattern $bits
    }
}

# Only the FIRST metastability capture flop is excepted for asynchronous pins.
# Zero input delays below identify the nominal bookkeeping clock; these pins
# have no synchronous external launch contract and are explicitly excepted.
foreach {port endpoint} {
    FPGA_RS232A_RXD u_member3/u_0/u_uart_rx/rxd_meta_reg/D
    FPGA_RS485_RXD_L u_member3/u_1/core/transport/rx/rxd_meta_reg/D
    FPGA_RS232B_RXD u_member3/u_2/u_rx/rxd_meta_reg/D
    FPGA_UART_RXD_L u_member3/u_5/u_hf_rx/rxd_meta_reg/D
    TFA_LF_RXD u_member3/u_5/u_lf_rx/rxd_meta_reg/D
    FPGA_RS485_RXD_L u_member3/u_6/core/master/rx/rxd_meta_reg/D
    SYNC_IN u_time/sync_meta_reg/D
    BMP390_INT u_member3/u_3/int_meta_reg/D
    I2C_SCL u_member3/u_i2c_master/scl_meta_reg/D
    I2C_SDA u_member3/u_i2c_master/sda_meta_reg/D
} {
    set_input_delay -clock $sysclock -max 0 [get_ports $port]
    set_input_delay -clock $sysclock -min 0 [get_ports $port]
    set capture [get_pins -quiet $endpoint]
    if {[llength $capture]!=1 || ![get_property ASYNC_REG [get_cells -of_objects $capture]]} {error "Missing expected first-stage synchronizer for $port ($endpoint)"}
    set_false_path -from [get_ports $port] -to $capture
}

# One physical AD4630 BUSY synchronizer serves both channels in dual mode.
set ad_busy [get_pins -hier -quiet -filter {NAME =~ */busy_meta_reg/D && NAME =~ u_member1/*}]
if {[llength $ad_busy]!=1 || ![get_property ASYNC_REG [get_cells -of_objects $ad_busy]]} {error "Expected one AD4630 BUSY synchronizer"}
set_input_delay -clock $sysclock -max 0 [get_ports ADC_AD4630_BUSY]
set_input_delay -clock $sysclock -min 0 [get_ports ADC_AD4630_BUSY]
set_false_path -from [get_ports ADC_AD4630_BUSY] -to $ad_busy

# Deliberately unused physical inputs: channel-B ADC lanes; ADC SPI readback is
# disabled (read_enable=0), DAC readback unsupported, CTL15 interrupt reserved.
set unused_inputs [get_ports {ADC_ADC3660_DB5 ADC_ADC3660_DB6 ADC_ADC3660_SDIO dac_sdo[*] FPGA_GPIF_INTN FPGA_RS422_RXD_L}]
if {$adc1root eq ""} {set unused_inputs [concat $unused_inputs [get_ports {ADC_ADC3660_DA5 ADC_ADC3660_DA6 ADC_ADC3660_DCLK ADC_ADC3660_FCLK}]]}
set_input_delay -clock $sysclock -max 0 $unused_inputs
set_input_delay -clock $sysclock -min 0 $unused_inputs
set_false_path -from $unused_inputs

# Slow GPIO/UART/ADC configuration pins: bound fabric-to-pad propagation. SPI data has
# >=50 ns half cycles (ADC3660 100 ns); 20 ns bounds preserve setup margins.
set slow_outputs [get_ports {FPGA_RS232A_TXD FPGA_RS485_TXD_L FPGA_RS485_DERE_L FPGA_RS422_TXD_L FPGA_UART_TXD_L FPGA_UART_EN_L RS232_PHY_FORCEON FPGA_RS232B_TXD MOTOR_PUL MOTOR_DIR MOTOR_ENA I2C_SCL I2C_SDA dac_ldac_n[*] ADC_ADC3660_SEN ADC_ADC3660_SCLK ADC_ADC3660_SDIO ADC_ADC3660_RST ADC_ADC3660_SYNC ADC_ADC3660_DCLKIN ADC_ADC3660_CLKP ADC_ADC3660_CLKN CYUSB_RSTN}]
set_output_delay -clock board25 -max 10.000 $slow_outputs
set_output_delay -clock board25 -min -1.000 $slow_outputs
# all_registers -clock_pins also returns INBUF/OSC_EN and ODDRE1/CLKDIV in
# Vivado2020.2, which cause illegal path segmentation. These slow outputs
# originate in ordinary FD* fabric flops, so select only their real C pins.
set slow_launch_clocks [get_pins -of_objects [get_cells -hier -filter {REF_NAME =~ FD*}] -filter {REF_PIN_NAME == C}]
set_max_delay 20 -datapath_only -from $slow_launch_clocks -to $slow_outputs
# Asynchronous assertion is intentional; all receiving clock domains release
# through synchronizers. Recovery/removal on those reset pins is not setup IO.
set_false_path -to [get_pins -hier -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]

# Source-synchronous FX3 timing is validated independently, then reused here.
source [file join [file dirname [info script]] gpif_pin_timing.xdc]
# The separate diagnostic observation of FLAG A crosses into sys_clk through
# link_sync. This exception affects only that synchronizer, not the synchronous
# GPIF transfer flags constrained above.
set link_capture [get_pins -quiet {link_sync_reg[0]/D}]
if {[llength $link_capture]!=1 || ![get_property ASYNC_REG [get_cells -of_objects $link_capture]]} {error "Missing GPIF link first-stage synchronizer"}
set_false_path -from [get_ports {FPGA_GPIF_CTL[4]}] -to $link_capture

# AD5791 stopped-clock SPI is checked using routed pad arrival differences.
source [file join [file dirname [info script]] dac_pin_timing.xdc]

# AD4630 SCK-to-SDO round trip, first word and configuration read are audited
# separately after route; do not replace this with a generic GPIO bound.
source [file normalize [file join [file dirname [info script]] .. adc ad4630_pin_timing.xdc]]

# Apply the same user uncertainty as the independently qualified interface
# projects. A primary-clock setting does not propagate to MMCM output clocks.
# Vivado adds its modeled jitter/phase contribution to this setup allowance.
set_clock_uncertainty -setup 0.200 [get_clocks *]
set_clock_uncertainty -hold 0.050 [get_clocks *]
