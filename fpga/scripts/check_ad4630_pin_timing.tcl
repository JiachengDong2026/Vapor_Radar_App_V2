# Source after route; reusable on member1_ad4630 and the complete physical top.
# Bound a full FPGA SCK/CS -> ADC -> FPGA SDO path, not separate pad targets.
if {![info exists ad4630_check_out]} {set ad4630_check_out [file normalize [file join [file dirname [info script]] .. reports ad4630_pin_timing]]}
file mkdir $ad4630_check_out
set ar [open "$ad4630_check_out/pad_timing.txt" w]
set afail 0
set aworst 1e9
set atick [expr {10.0/1.0001}]
set aedge 0.250
set aflight 1.0
set acap [get_cells -hier -filter {NAME =~ */cap_sck_reg}]
if {[llength $acap]!=1} {error "Expected one AD4630 capture serializer"}
set aroot [file dirname [get_property NAME $acap]]
set asys [get_clocks -of_objects [get_pins "$aroot/cap_sck_reg/C"]]
if {[llength $asys]!=1 || abs([get_property PERIOD $asys]-10)>0.001} {error "AD4630 requires SYS100MHz"}
puts $ar "AD4630 Rev0 Tables2/3/4, VIO1.8V, 25MHz capture H2; SYS100MHz +/-100ppm"
puts $ar "Board flight each direction0..1ns; output10pF; return SDO load<=5pF datasheet premise; interval uncertainty0.250ns. Board values are budgets, not measurements."
proc areq {name have need} {
    global ar afail aworst
    set slack [expr {$have-$need}]
    puts $ar [format "%-38s available=%9.3f required=%8.3f margin=%9.3f %s" $name $have $need $slack [expr {$slack>=0?"PASS":"FAIL"}]]
    if {$slack<0} {incr afail}
    if {$slack<$aworst} {set aworst $slack}
}
proc aout {port reg transition type} {
    global ar aroot
    set po [get_ports $port]
    if {[get_property LOAD $po]<10 || [get_property IOSTANDARD $po]!="LVCMOS18"} {error "AD4630 output load/voltage budget missing: $port"}
    set cp [get_pins "$aroot/$reg/C"]
    if {[llength $cp]!=1} {error "Missing AD4630 launch register $reg"}
    set path [get_timing_paths -delay_type $type -from $cp -${transition}_to $po -max_paths 1]
    if {[llength $path]!=1} {error "Missing AD4630 pad path $reg to $port"}
    if {[get_property EXCEPTION $path]!="" || [get_property OUTPUT_DELAY $path]!=0} {error "Remove old AD4630 slow-GPIO exceptions/delays at $port"}
    foreach net [concat [get_nets -of_objects $po] [get_nets -of_objects [get_pins -of_objects [get_cells -of_objects $cp] -filter {DIRECTION == OUT}]]] {
        if {[get_property ROUTE_STATUS $net] ni {ROUTED INTRASITE}} {error "Unrouted AD4630 output net $net"}
    }
    set arrival [expr {[get_property ARRIVAL_TIME $path]-[get_property STARTPOINT_CLOCK_EDGE $path]}]
    puts $ar "$port $reg $transition $type arrival=$arrival clock=[get_property STARTPOINT_CLOCK_DELAY $path] datapath=[get_property DATAPATH_DELAY $path] corner=[get_property CORNER $path]"
    return $arrival
}
foreach {tag port reg} {
    sck ADC_AD4630_SCK cap_sck_reg
    cs ADC_AD4630_CSN cap_cs_reg
    cnv ADC_AD4630_CNV adc_cnv_reg
    rst ADC_AD4630_RSTN adc_rst_n_reg
    cfg_sck ADC_AD4630_SCK u_spi/sck_reg
    cfg_cs ADC_AD4630_CSN u_spi/cs_n_reg
    sdi ADC_AD4630_SDI {u_spi/shift_reg[23]}
} {
    foreach edge {rise fall} {
        set ae($tag,$edge) [aout $port $reg $edge min]
        set al($tag,$edge) [aout $port $reg $edge max]
    }
}
# Exactly the four directly captured nibble bits; SDO0 also has a separate
# configuration read path. Enumerate every endpoint and rise/fall data arc.
foreach mode {sample config} {
    if {$mode=="sample"} {set cells [get_cells "$aroot/shift_word_reg*"];set half 2;set tmax 5.6;set tmin 1.4;set clocktag sck;set lanes {0 1 2 3}}
    if {$mode=="config"} {set cells [get_cells "$aroot/u_spi/read_data_reg*"];set half 10;set tmax 9.4;set tmin 2.1;set clocktag cfg_sck;set lanes {0}}
    set seen 0
    foreach lane $lanes {
        set port [get_ports [format {ADC_AD4630_SDO[%d]} $lane]]
        foreach edge {rise fall} {
            foreach type {max min} {
                set paths [get_timing_paths -delay_type $type -${edge}_from $port -to $cells -max_paths 64 -nworst 64]
                if {![llength $paths]} {error "Missing $mode SDO$lane $edge/$type capture path"}
                foreach path $paths {
                    incr seen
                    set endpoint [get_property ENDPOINT_PIN $path]
                    set pu [get_property -quiet UNCERTAINTY $path]
                    if {$pu==""} {set pu 0.0}
                    if {$pu>$aedge+0.0001} {error "AD4630 observed uncertainty exceeds budget"}
                    # Remove CPPR credit and the STA edge separation/input-delay
                    # allocation. Retain actual capture clock insertion and the
                    # endpoint setup/hold library value; use full pad loop below.
                    # Vivado2020.2 REQUIRED_TIME contains MCP edge movement,
                    # but ENDPOINT_CLOCK_EDGE remains the base 10/0ns edge.
                    # The paired MCP2/1 or10/9 contributes (HALF-1)*10ns to
                    # BOTH setup and hold absolute times. Assert that contract
                    # before removing it; do not silently rely on a new XDC.
                    set ex [get_property EXCEPTION $path]
                    if {![regexp {Setup -end[ ]+([0-9]+)} $ex unused setup_cycles] || $setup_cycles!=$half} {error "Unexpected AD4630 setup MCP: $ex"}
                    if {$type=="min" && (![regexp {Hold[ ]+-start[ ]+([0-9]+)} $ex unused hold_cycles] || $hold_cycles!=$half-1)} {error "Unexpected AD4630 hold MCP: $ex"}
                    set expected_requirement [expr {$type=="max"?$half*10.0:0.0}]
                    if {abs([get_property REQUIREMENT $path]-$expected_requirement)>0.001} {error "Unexpected AD4630 edge requirement"}
                    set bound [expr {[get_property REQUIRED_TIME $path]-[get_property ENDPOINT_CLOCK_EDGE $path]-($half-1)*10.0-[get_property CLOCK_PESSIMISM $path]}]
                    set library_check [expr {$bound-[get_property ENDPOINT_CLOCK_DELAY $path]+($type=="max"?$pu:-$pu)}]
                    if {abs($library_check)>1.0} {error "AD4630 capture time normalization did not isolate setup/hold library value"}
                    set d [get_property DATAPATH_DELAY $path]
                    if {$type=="max"} {
                        set capture [expr {$half*$atick+$bound+$pu-$aedge}]
                        set arrive [expr {$al($clocktag,fall)+2*$aflight+$tmax+$d}]
                        areq "${mode}_SDO${lane}_${edge}_setup" [expr {$capture-$arrive}] 0
                        if {$mode=="sample"} {
                            set first [expr {3*$atick+$bound+$pu-$aedge-$al(cs,fall)-2*$aflight-6.8-$d}]
                            areq "first_CS_SDO${lane}_${edge}_setup" $first 0
                        }
                    } else {
                        set hold [expr {$bound-$pu+$aedge}]
                        # The next real falling SCK edge is HALF ticks AFTER
                        # this sampling edge. Earliest board flight is zero.
                        set next [expr {$half*$atick+$ae($clocktag,fall)+$tmin+$d}]
                        areq "${mode}_SDO${lane}_${edge}_hold" [expr {$next-$hold}] 0
                    }
                    puts $ar "  endpoint=$endpoint type=$type data=$d capture_bound=$bound corner=[get_property CORNER $path]"
                }
            }
        }
    }
    puts $ar "$mode checked_capture_arcs=$seen"
}
foreach {tag half high low csfirst cslast} {sck 2 4.2 4.2 9.8 4.2 cfg_sck 10 5.2 5.2 11.6 5.2} {
    set cstag [expr {$tag=="sck"?"cs":"cfg_cs"}]
    areq "${tag}_period" [expr {2*$half*$atick-$aedge}] [expr {$tag=="sck"?9.8:11.6}]
    areq "${tag}_high" [expr {$half*$atick+$ae($tag,fall)-$al($tag,rise)-$aflight-$aedge}] $high
    areq "${tag}_low" [expr {$half*$atick+$ae($tag,rise)-$al($tag,fall)-$aflight-$aedge}] $low
    set first [expr {$tag=="sck"?3:10}]
    set last [expr {$tag=="sck"?2:2}]
    areq "${tag}_CS_setup" [expr {$first*$atick+$ae($tag,rise)-$al($cstag,fall)-$aflight-$aedge}] $csfirst
    areq "${tag}_CS_hold" [expr {$last*$atick+$ae($cstag,rise)-$al($tag,fall)-$aflight-$aedge}] $cslast
}
areq cfg_SDI_setup [expr {10*$atick+$ae(cfg_sck,rise)-max($al(sdi,rise),$al(sdi,fall))-$aflight-$aedge}] 1.5
areq cfg_SDI_hold [expr {10*$atick+min($ae(sdi,rise),$ae(sdi,fall))-$al(cfg_sck,rise)-$aflight-$aedge}] 1.5
areq cfg_CS_high [expr {4*$atick+$ae(cfg_cs,fall)-$al(cfg_cs,rise)-$aflight-$aedge}] 10
areq CNV_high_min2ticks [expr {2*$atick+$ae(cnv,fall)-$al(cnv,rise)-$aflight-$aedge}] 10
areq CNV_low_max20ticks [expr {80*$atick+$ae(cnv,rise)-$al(cnv,fall)-$aflight-$aedge}] 20
areq CNV_period_min100ticks [expr {100*$atick-$aedge}] 500
areq CNV_to_CS_data_available [expr {31*$atick+$ae(cs,fall)-$al(cnv,rise)-$aflight-$aedge}] 300
foreach tag {cs cfg_cs} {
    areq "quiet_before_CNV_$tag" [expr {5*$atick+$ae(cnv,rise)-$al($tag,rise)-$aflight-$aedge}] 19.6
}
areq quiet_after_CNV [expr {31*$atick+$ae(cs,fall)-$al(cnv,rise)-$aflight-$aedge}] 9.8
areq RESET_low [expr {100*$atick+$ae(rst,rise)-$al(rst,fall)-$aflight-$aedge}] 50
areq RESET_to_SPI [expr {100000*$atick+$ae(cfg_cs,fall)-$al(rst,rise)-$aflight-$aedge}] 750000
puts $ar [format "minimum_margin=%.3fns failing_checks=%d" $aworst $afail]
close $ar
if {$afail} {error "AD4630_PIN_TIMING_FAIL checks=$afail report=$ad4630_check_out/pad_timing.txt"}
puts [format "AD4630_PIN_TIMING_PASS SCK=25MHz min_margin=%.3fns roundtrip_board<=2ns output_load10pF SDO_load<=5pF" $aworst]
