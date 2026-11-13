# Continue the SAME build after residual setup failure, without RTL edits.
# vivado -mode batch -source close_routed_timing.tcl -tclargs input.dcp output_dir
source [file join [file dirname [info script]] full_sources.tcl]
set_param general.maxThreads 8
set checkpoint [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {[file exists $out]} {error "Use a new timing-closure output directory"}
file mkdir $out
set python python
if {[info exists ::env(VAPOR_PYTHON)]} {set python $::env(VAPOR_PYTHON)}
proc full_route_complete {report_path} {
    report_route_status -file $report_path
    set handle [open $report_path r]
    set text [read $handle]
    close $handle
    foreach {name pattern} {
        routable {# of routable nets\.+\s*:\s*(\d+)}
        fully {# of fully routed nets\.+\s*:\s*(\d+)}
        errors {# of nets with routing errors\.+\s*:\s*(\d+)}
    } {
        if {![regexp $pattern $text match value]} {error "Missing route count: $name"}
        set counts($name) $value
    }
    return [expr {$counts(routable)>0 && $counts(fully)==$counts(routable) && $counts(errors)==0}]
}
proc full_hold_pin_repair {out exact_scope} {
    set paths [get_timing_paths -delay_type min -slack_lesser_than 0 -max_paths 100 -nworst 1]
    if {![llength $paths] || [llength $paths]>=100} {error "Hold repair requires 1..99 bounded endpoints"}
    if {$exact_scope && [llength $paths]!=46} {error "Resumed hold scope differs from the recorded 46 endpoints"}
    set target_pins {}
    set group_counts [dict create usb0 0 usb1 0 usb3 0 usb4 0 tx 0 rx 0 tx_fifo 0 rx_fifo 0]
    set detail [open "$out/hold_repair_endpoints.tsv" w]
    foreach path $paths {
        set start [get_property STARTPOINT_PIN $path]
        set destination [get_property ENDPOINT_PIN $path]
        set pin [get_pins -quiet $destination]
        if {[llength $pin]!=1 || [get_property REF_PIN_NAME $pin] ne "D"} {error "Not a unique hold destination D: $destination"}
        set cell [get_cells -of_objects $pin]
        set async [string tolower [string trim [get_property -quiet ASYNC_REG $cell]]]
        if {$async ni {1 true yes on}} {error "Hold destination lacks ASYNC_REG: $destination"}
        set dest_clock [get_clocks -of_objects [get_pins -of_objects $cell -filter {REF_PIN_NAME == C}]]
        set source_clock [get_clocks -of_objects [get_pins $start]]
        set fanin [all_fanin -flat -startpoints_only -to $pin]
        if {[llength $fanin]!=1 || $fanin ne $start || [get_property REF_PIN_NAME $fanin] ne "C" || ![string match FD* [get_property REF_NAME [get_cells -of_objects $fanin]]]} {error "Unexpected hold launch for $destination"}
        if {$dest_clock ne "sys_raw" || $source_clock ni {gpif_raw board25}} {error "Unexpected hold clock pair: $source_clock -> $dest_clock"}
        if {$source_clock eq "board25" && ![string match {u_clock_fault_cdc/gray_meta_reg*} $destination]} {error "Unreviewed board25 hold endpoint"}
        if {[regexp {^u_clock_fault_cdc/gray_meta_reg\[([0-9]+)\]/D$} $destination match bit] && $bit<32} {
            set expected_start [format {u_clock_fault_cdc/src_gray_reg[%d]/C} $bit]
            set second [get_cells -quiet [format {u_clock_fault_cdc/gray_sync_reg[%d]} $bit]]
            if {$source_clock ne "board25" || $start ne $expected_start || [llength $second]!=1 || ![get_property ASYNC_REG $second]} {error "Unexpected clock-fault Gray synchronizer"}
            set second_d [get_pins -of_objects $second -filter {REF_PIN_NAME == D}]
            set driver [get_pins -of_objects [get_nets -of_objects $second_d] -filter {DIRECTION == OUT}]
            set expected_driver [format {u_clock_fault_cdc/gray_meta_reg[%d]/Q} $bit]
            if {[llength $driver]!=1 || [get_property NAME $driver] ne $expected_driver} {error "Clock-fault second stage is not direct"}
            if {[get_clocks -of_objects [get_pins -of_objects $second -filter {REF_PIN_NAME == C}]] ne "sys_raw"} {error "Clock-fault second stage clock changed"}
            set timed [get_timing_paths -from [get_pins [string range $destination 0 end-1]C] -to $second_d -delay_type max -max_paths 1]
            if {[llength $timed]!=1 || [get_property SLACK $timed]<0 || [get_property EXCEPTION $timed] ne ""} {error "Clock-fault second stage is failing or excepted"}
            dict incr group_counts clock_fault
        } elseif {[regexp {^u_usb_counter(0|1|3|4)/gray_meta_reg\[([0-9]+)\]/D$} $destination match instance bit] && $bit<32} {
            dict incr group_counts usb$instance
        } elseif {[regexp {^u_transport/u_(tx|rx)/(rd|wr)_gray_meta_reg\[([0-9]+)\]/D$} $destination match fifo pointer bit] && $bit<12} {
            if {!(($fifo eq "tx" && $pointer eq "rd") || ($fifo eq "rx" && $pointer eq "wr"))} {error "Unexpected USB occupancy crossing direction"}
            set base u_transport/u_$fifo
            set expected_start [format {%s/%s_gray_reg[%d]/C} $base $pointer $bit]
            set expected_msb [format {%s/%s_count_reg[%d]/C} $base $pointer $bit]
            set second [get_cells -quiet [format {%s/%s_gray_sync_reg[%d]} $base $pointer $bit]]
            if {($start ne $expected_start && !($bit==11 && $start eq $expected_msb)) || [llength $second]!=1 || ![get_property ASYNC_REG $second]} {error "Unexpected USB occupancy Gray synchronizer"}
            set second_d [get_pins -of_objects $second -filter {REF_PIN_NAME == D}]
            set second_driver [get_pins -of_objects [get_nets -of_objects $second_d] -filter {DIRECTION == OUT}]
            if {[llength $second_driver]!=1 || [get_property NAME $second_driver] ne [format {%s/%s_gray_meta_reg[%d]/Q} $base $pointer $bit]} {error "USB occupancy second stage is not direct"}
            if {[get_clocks -of_objects [get_pins -of_objects $second -filter {REF_PIN_NAME == C}]] ne "sys_raw"} {error "USB occupancy second stage clock changed"}
            set second_path [get_timing_paths -from [get_pins [string range $destination 0 end-1]C] -to $second_d -delay_type max -max_paths 1]
            if {[llength $second_path]!=1 || [get_property SLACK $second_path]<0 || [get_property EXCEPTION $second_path] ne ""} {error "USB occupancy second stage is failing or excepted"}
            dict incr group_counts $fifo
        } elseif {[regexp {^u_transport/u_(tx|rx)/u_fifo/(rd_gray_w1|wr_gray_r1)_reg\[([0-9]+)\]/D$} $destination match fifo first bit] && $bit<12} {
            # Existing 2048-entry USB FIFO Gray synchronizers. Only the
            # GPIF50 -> SYS100 direction is eligible; validate both stages
            # and the direct registered Gray source before changing routing.
            if {$fifo eq "tx" && $first eq "rd_gray_w1"} {
                set pointer rd;set stage2 rd_gray_w2
            } elseif {$fifo eq "rx" && $first eq "wr_gray_r1"} {
                set pointer wr;set stage2 wr_gray_r2
            } else {error "Unexpected USB FIFO crossing direction"}
            set base u_transport/u_$fifo/u_fifo
            set expected_start [format {%s/%s_gray_reg[%d]/C} $base $pointer $bit]
            set expected_msb [format {%s/%s_bin_reg[%d]/C} $base $pointer $bit]
            set second [get_cells -quiet [format {%s/%s_reg[%d]} $base $stage2 $bit]]
            if {($start ne $expected_start && !($bit==11 && $start eq $expected_msb)) || [llength $second]!=1 || ![get_property ASYNC_REG $second]} {error "Unexpected USB FIFO Gray synchronizer"}
            set second_d [get_pins -of_objects $second -filter {REF_PIN_NAME == D}]
            set second_net [get_nets -of_objects $second_d]
            set second_driver [get_pins -of_objects $second_net -filter {DIRECTION == OUT}]
            set expected_driver [format {%s/%s_reg[%d]/Q} $base $first $bit]
            if {[llength $second_driver]!=1 || [get_property NAME $second_driver] ne $expected_driver} {error "USB FIFO Gray second stage is not direct"}
            if {[get_clocks -of_objects [get_pins -of_objects $second -filter {REF_PIN_NAME == C}]] ne "sys_raw"} {error "USB FIFO Gray second stage clock changed"}
            set second_path [get_timing_paths -from [get_pins [string range $destination 0 end-1]C] -to $second_d -delay_type max -max_paths 1]
            if {[llength $second_path]!=1 || [get_property SLACK $second_path]<0 || [get_property EXCEPTION $second_path] ne ""} {error "USB FIFO Gray second stage is failing or excepted"}
            dict incr group_counts ${fifo}_fifo
        } else {error "Hold endpoint outside reviewed repair scope: $destination"}
        set slack [get_property SLACK $path]
        if {$slack>=0} {error "Hold endpoint is no longer negative: $destination"}
        puts $detail "$slack\t$start\t$destination\t$source_clock\t$dest_clock"
        lappend target_pins $destination
    }
    close $detail
    set target_pins [lsort -unique $target_pins]
    if {[llength $target_pins]!=[llength $paths]} {error "Duplicate hold endpoints"}
    if {$exact_scope && $group_counts ne [dict create usb0 14 usb1 13 usb3 3 usb4 14 tx 2 rx 0 tx_fifo 0 rx_fifo 0]} {error "Resumed hold endpoint groups changed: $group_counts"}
    puts "POST_ROUTE_HOLD_PIN_SCOPE_VERIFIED $group_counts"
    set target_count [llength $target_pins]
    set before_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    set corner_data [dict create]
    foreach destination $target_pins {
     set pin [get_pins $destination]
     set net [get_nets -of_objects $pin]
     if {[llength $net]!=1} {error "Nonunique net: $destination"}
     set delays [get_net_delays -of_objects $net -to $pin -interconnect_only]
     if {[llength $delays]!=1} {error "Nonunique interconnect delay: $destination"}
     foreach property {FAST_MIN FAST_MAX SLOW_MIN SLOW_MAX} {
      set value [get_property $property $delays]
      if {![string is double -strict $value] || $value<=0} {error "Invalid ps net delay $property for $destination: $value"}
      dict set corner_data $destination $property $value
     }
    }
    # Temporary analysis views only. Restore default quad analysis before routing.
    foreach corner {Fast Slow} {
     set other [expr {$corner eq "Fast" ? "Slow" : "Fast"}]
     config_timing_corners -corner $other -delay_type none
     config_timing_corners -corner $corner -delay_type min_max
     foreach {type label} {min hold max setup} {
      set paths [get_timing_paths -to [get_pins $target_pins] -delay_type $type -max_paths 100 -nworst 1]
      if {[llength $paths]!=$target_count} {error "Missing $corner $label paths: [llength $paths]"}
      report_timing -of_objects $paths -file $out/${corner}_${label}_targets.rpt
      set seen {}
      foreach path $paths {
       set destination [get_property ENDPOINT_PIN $path]
       if {[lsearch -exact $target_pins $destination]<0} {error "Unexpected corner endpoint $destination"}
       lappend seen $destination
       dict set corner_data $destination ${corner}_${label}_slack [get_property SLACK $path]
       dict set corner_data $destination ${corner}_${label}_requirement [get_property REQUIREMENT $path]
       dict set corner_data $destination ${corner}_${label}_data [get_property DATAPATH_DELAY $path]
      }
      if {[llength [lsort -unique $seen]]!=$target_count} {error "Duplicate $corner $label endpoints"}
     }
    }
    config_timing_corners -corner Fast -delay_type min_max
    config_timing_corners -corner Slow -delay_type min_max
    puts "HOLD_REPAIR_QUAD_TIMING_RESTORED"
    set quad_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    if {abs($quad_hold-$before_hold)>0.001} {error "Quad baseline changed before routing: $before_hold -> $quad_hold"}
    set target_file [open $out/derived_interconnect_targets.tsv w]
    puts $target_file "destination\tFAST_MIN_ps\tFAST_MAX_ps\tSLOW_MIN_ps\tSLOW_MAX_ps\tFast_hold_slack_ns\tFast_setup_slack_ns\tSlow_hold_slack_ns\tSlow_setup_slack_ns\tmin_target_ps\tmax_target_ps"
    set targets [dict create]
    foreach destination $target_pins {
     set data [dict get $corner_data $destination]
     set lower -1e30;set upper 1e30
     foreach corner {Fast Slow} {
      set prefix [string toupper $corner]
      set min_net [dict get $data ${prefix}_MIN]
      set max_net [dict get $data ${prefix}_MAX]
      set hold_slack [dict get $data ${corner}_hold_slack]
      set setup_slack [dict get $data ${corner}_setup_slack]
      if {$setup_slack<=0.020} {error "Insufficient original setup margin at $destination / $corner"}
      set lower [expr {max($lower,$min_net-1000.0*$hold_slack)}]
      set upper [expr {min($upper,$max_net+1000.0*$setup_slack)}]
     }
     set min_target [expr {int(ceil($lower+20.0))}]
     set max_target [expr {int(floor($upper-20.0))}]
     if {$min_target<=0 || $min_target>=$max_target} {error "No legal physical target window at $destination"}
     dict set targets $destination [list $min_target $max_target]
     set row [list $destination]
     foreach key {FAST_MIN FAST_MAX SLOW_MIN SLOW_MAX Fast_hold_slack Fast_setup_slack Slow_hold_slack Slow_setup_slack} {lappend row [dict get $data $key]}
     puts $target_file "[join $row \t]\t$min_target\t$max_target"
    }
    close $target_file
    set progress [open $out/pin_route_progress.tsv w]
    puts $progress "index\tdestination\tmin_ps\tmax_ps\tstarted_epoch_ms\telapsed_ms"
    set index 0
    foreach destination $target_pins {
     incr index
     lassign [dict get $targets $destination] min_target max_target
     set started [clock milliseconds]
     puts "EXPLICIT_PIN_ROUTE_START $index/$target_count $destination min_ps=$min_target max_ps=$max_target"
     route_design -unroute -pins [get_pins $destination]
     route_design -pins [get_pins $destination] -min_delay $min_target -max_delay $max_target
     set elapsed [expr {[clock milliseconds]-$started}]
     puts $progress "$index\t$destination\t$min_target\t$max_target\t$started\t$elapsed"
     flush $progress
     puts "EXPLICIT_PIN_ROUTE_DONE $index/$target_count elapsed_ms=$elapsed"
    }
    close $progress
    puts "HOLD_REPAIR_PIN_ROUTES_COMPLETED count=$index"
    if {![full_route_complete "$out/post_hold_route_status.rpt"]} {error "Local hold repair did not restore complete routing"}
}
if {[catch {
    puts [exec $python -I "$root/scripts/build_manifest.py" capture $out]
    open_checkpoint $checkpoint
    report_timing -delay_type max -max_paths 30 -nworst 1 -file "$out/before_setup.rpt"
    set setup_slack [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    if {$setup_slack<0} {
        phys_opt_design -directive AggressiveExplore
        route_design -directive Explore
    }
    set hold_slack [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    if {$hold_slack<0} {
        write_checkpoint -force "$out/pre_hold_repair.dcp"
        report_timing -delay_type min -slack_lesser_than 0 -max_paths 100 -nworst 1 -file "$out/pre_hold_violations.rpt"
        full_hold_pin_repair $out 0
    }
        if {![full_route_complete "$out/route_status.rpt"]} {error "Full top routing incomplete"}
        report_timing_summary -delay_type min_max -report_unconstrained -file "$out/timing.rpt"
        report_cdc -details -file "$out/cdc.rpt"
        check_timing -verbose -file "$out/check_timing.rpt"
        report_drc -file "$out/drc.rpt"
        report_pulse_width -all_violators -file "$out/pulse_width.rpt"
        report_utilization -hierarchical -file "$out/utilization.rpt"
        write_checkpoint -force "$out/routed.dcp"
        set dac_check_out "$out/dac_pin_timing"
        source "$root/scripts/check_dac_pin_timing.tcl"
        set ad4630_check_out "$out/ad4630_pin_timing"
        source "$root/scripts/check_ad4630_pin_timing.tcl"
        set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
        set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
        puts "FULL_TOP_TIMING WNS=$wns WHS=$whs"
        if {$wns<0 || $whs<0} {error "Full top timing failed"}
        set check_handle [open "$out/check_timing.rpt" r]
        set check_text [read $check_handle]
        close $check_handle
        foreach check {no_clock constant_clock unconstrained_internal_endpoints no_input_delay multiple_clock generated_clocks loops partial_input_delay partial_output_delay latch_loops} {
            set pattern [format {checking %s \(([0-9]+)\)} $check]
            if {![regexp $pattern $check_text match count] || $count!=0} {error "Unresolved check_timing category: $check"}
        }
        if {![regexp {checking no_output_delay \(([0-9]+)\)} $check_text match count] || $count!=1 ||
            ![regexp {1 port with no output delay but with a timing clock} $check_text] ||
            ![regexp {\nFPGA_GPIF_PCLK\r?\n} $check_text]} {error "Unexpected no_output_delay ports; only generated PCLK is exempt"}
        set pulse_handle [open "$out/pulse_width.rpt" r]
        set pulse_text [read $pulse_handle]
        close $pulse_handle
        if {[regexp -nocase {\(VIOLATED\)} $pulse_text]} {error "Clock pulse-width timing violation"}
        if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}]]} {error "Full top DRC violation"}
        puts [exec $python -I "$root/scripts/build_manifest.py" verify $out]
        write_bitstream -force "$out/vapor_lidar_top.bit"
} failure]} {
    puts stderr "ROUTED_TIMING_CLOSURE_FAIL: $failure"
    exit 1
}
puts "ROUTED_TIMING_CLOSURE_PASS"
exit
