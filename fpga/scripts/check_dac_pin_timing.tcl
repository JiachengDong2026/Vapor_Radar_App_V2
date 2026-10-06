# Source only after route of the current H>=3 AD5791 RTL and dac_pin_timing.xdc.
# Clock-to-pad bounds include register clock insertion, C->Q, routing and OBUF.
# Fast/min vs Slow/max subtraction is deliberately conservative across PVT;
# no common-clock pessimism credit is taken. No false paths are introduced.
set dac_check_root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists dac_check_out]} {set dac_check_out "$dac_check_root/reports/dac_pin_timing"}
file mkdir $dac_check_out
set dac_check_report [open "$dac_check_out/pad_timing.txt" w]
set dac_check_failures 0
set dac_check_worst 1.0e9
set dac_period 10.0
set dac_half 3
set dac_board_skew 1.0
set dac_edge_uncertainty 0.250
set dac_frequency_ppm 100.0
set dac_tick_min [expr {$dac_period/(1.0+$dac_frequency_ppm/1000000.0)}]
puts $dac_check_report "AD5791 Rev F, 1.71..3.3 V; falling-edge capture; current RTL minimum H=3"
puts $dac_check_report "SYS=100MHz, clock tolerance=100ppm, edge interval uncertainty=0.250ns, PCB differential=1.000ns, load>=10pF"
puts $dac_check_report "All bounds are ns. Board load/skew/tolerance are explicit integration budgets, not PCB measurements."
proc dac_bound {port transition delay_type} {
    global dac_check_report
    set pobj [get_ports -quiet $port]
    if {[llength $pobj]!=1} {error "Missing DAC pad $port"}
    if {[get_property LOAD $pobj]<10.0} {error "DAC pad $port load is below the 10pF qualification budget"}
    if {[get_property IOSTANDARD $pobj]!="LVCMOS18"} {error "DAC pad $port must use LVCMOS18"}
    set path [get_timing_paths -delay_type $delay_type -${transition}_to $pobj -max_paths 1]
    if {[llength $path]!=1} {error "Missing timed $transition/$delay_type path to $port"}
    if {[get_property EXCEPTION $path]!=""} {error "DAC pad $port still has an overriding timing exception; remove DAC from slow-GPIO/datapath-only rules"}
    if {[get_property OUTPUT_DELAY $path]!=0} {error "DAC observation output delay must be zero for $port"}
    set cp [get_property STARTPOINT_CLOCK $path]
    if {abs([get_property PERIOD $cp]-10.0)>0.001} {error "DAC launch clock is not 100MHz"}
    if {[get_property STARTPOINT_CLOCK_EDGE $path]!=0} {error "Expected positive-edge SYS launch at $port"}
    set start [get_property STARTPOINT_PIN $path]
    set cell [get_cells -of_objects $start]
    if {![string match FD* [get_property REF_NAME $cell]] || [get_property REF_PIN_NAME $start]!="C"} {error "DAC $port is not driven from an ordinary clocked output register"}
    set output_pins [get_pins -of_objects $cell -filter {DIRECTION == OUT}]
    foreach net [concat [get_nets -of_objects $output_pins] [get_nets -of_objects $pobj]] {
        set route_state [get_property ROUTE_STATUS $net]
        if {$route_state ni {ROUTED INTRASITE}} {error "DAC pad $port has an unrouted output path: $net status=$route_state"}
    }
    if {[get_property UNCERTAINTY $path]>0.2501} {error "Observed uncertainty exceeds declared 0.250ns edge budget at $port"}
    set arrival [expr {[get_property ARRIVAL_TIME $path]-[get_property STARTPOINT_CLOCK_EDGE $path]}]
    puts $dac_check_report "$port $transition $delay_type arrival=$arrival corner=[get_property CORNER $path] start=$start clock_delay=[get_property STARTPOINT_CLOCK_DELAY $path] datapath=[get_property DATAPATH_DELAY $path]"
    return $arrival
}
proc dac_requirement {ch name available required} {
    global dac_check_report dac_check_failures dac_check_worst
    set slack [expr {$available-$required}]
    puts $dac_check_report [format "CH%d %-29s available=%9.3f required=%7.3f margin=%9.3f %s" $ch $name $available $required $slack [expr {$slack>=0?"PASS":"FAIL"}]]
    if {$slack<$dac_check_worst} {set dac_check_worst $slack}
    if {$slack<0} {incr dac_check_failures}
}
foreach ch {0 1} {
    foreach signal {sclk sync_n sdin rst_n clr_n} {
        set port [format {dac_%s[%d]} $signal $ch]
        foreach transition {rise fall} {
            set early($signal,$transition) [dac_bound $port $transition min]
            set late($signal,$transition) [dac_bound $port $transition max]
        }
    }
    set half [expr {$dac_half*$dac_tick_min}]
    set e $dac_edge_uncertainty
    set b $dac_board_skew
    # Same-pin, same-transition periodic delay cancels; only frequency and
    # interval uncertainty shorten the cycle. Do not subtract arbitrary PVT
    # delay differences between two adjacent identical falling transitions.
    dac_requirement $ch t1_sclk_period [expr {2*$half-$e}] 40
    dac_requirement $ch t2_sclk_high [expr {$half+$early(sclk,fall)-$late(sclk,rise)-$b-$e}] 15
    dac_requirement $ch t3_sclk_low [expr {$half+$early(sclk,rise)-$late(sclk,fall)-$b-$e}] 9
    set data_latest [expr {max($late(sdin,rise),$late(sdin,fall))}]
    set data_earliest [expr {min($early(sdin,rise),$early(sdin,fall))}]
    dac_requirement $ch t8_sdin_setup [expr {$half+$early(sclk,fall)-$data_latest-$b-$e}] 9
    dac_requirement $ch t9_sdin_hold [expr {$half+$data_earliest-$late(sclk,fall)-$b-$e}] 12
    dac_requirement $ch t4_sync_setup [expr {$half+$early(sclk,fall)-$late(sync_n,fall)-$b-$e}] 5
    dac_requirement $ch t5_sync_last_fall_hold [expr {($dac_half+1)*$dac_tick_min+$early(sync_n,rise)-$late(sclk,fall)-$b-$e}] 2
    dac_requirement $ch t6_sync_high [expr {6*$dac_tick_min+$early(sync_n,fall)-$late(sync_n,rise)-$b-$e}] 48
    dac_requirement $ch t7_sync_high_to_next_fall [expr {(6+$dac_half)*$dac_tick_min+$early(sclk,fall)-$late(sync_n,rise)-$b-$e}] 8
    dac_requirement $ch t17_sync_fall_to_first_rise [expr {2*$half+$early(sclk,rise)-$late(sync_n,fall)-$b-$e}] 0
    dac_requirement $ch t20_sync_high_to_next_rise [expr {(6+2*$dac_half)*$dac_tick_min+$early(sclk,rise)-$late(sync_n,rise)-$b-$e}] 0
    dac_requirement $ch t15_clear_low [expr {10*$dac_tick_min+$early(clr_n,rise)-$late(clr_n,fall)-$b-$e}] 50
    # t21 is 35ns TYPICAL in Table 4, not a guaranteed minimum. Retain the
    # project's 1.01us reset pulse as engineering evidence, not a false limit.
    puts $dac_check_report [format "CH%d RESET low conservative bound %.3f ns; datasheet t21=35ns TYP, not a specified min" $ch [expr {101*$dac_tick_min+$early(rst_n,rise)-$late(rst_n,fall)-$b-$e}]]
}
puts $dac_check_report "LDAC is statically tied low; pulsed-LDAC t10/t11/t12 not applicable. SDO readback is not implemented."
puts $dac_check_report [format "Overall minimum margin=%.3f ns; failing checks=%d" $dac_check_worst $dac_check_failures]
close $dac_check_report
if {$dac_check_failures} {error "DAC_PIN_TIMING_FAIL checks=$dac_check_failures; see $dac_check_out/pad_timing.txt"}
puts [format "DAC_PIN_TIMING_PASS H=3 actual_SPI=16666666Hz minimum_margin=%.3fns PCB_skew=1ns edge_budget=0.250ns tolerance=100ppm" $dac_check_worst]
