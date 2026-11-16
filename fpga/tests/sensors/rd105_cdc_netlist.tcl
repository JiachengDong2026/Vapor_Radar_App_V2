# Read-only final-checkpoint review, including the new shared-port RD105 UART.
# vivado -mode batch -source this_file -tclargs routed.dcp parsed_cdc_directory
# Reuse every existing exact endpoint, reset, Gray, UART and bus-skew check.
set rd105_checker [file normalize [file join [file dirname [info script]] ../../scripts/review_cdc_netlist.tcl]]
set rd105_handle [open $rd105_checker r]
set rd105_text [read $rd105_handle]
close $rd105_handle
set rd105_anchor {SDFM300 FPGA_UART_RXD_L u_member3/u_5/u_rx]}
if {[string first $rd105_anchor $rd105_text]<0} {error "Common UART review list changed; review the RD105 insertion"}
set rd105_extended {SDFM300 FPGA_UART_RXD_L u_member3/u_5/u_rx \
 RD105 FPGA_RS485_RXD_L u_member3/u_7/transport/rx]}
set rd105_repair_audit {
# Independently audit every first-stage endpoint physically repaired in this run.
set repair_list [file join [file dirname $task_checkpoint] hold_repair_endpoints.tsv]
if {[file exists $repair_list]} {
    set repair_handle [open $repair_list r]
    set repair_rows [split [string trim [read $repair_handle]] \n]
    close $repair_handle
    set repair_evidence [open "$task_review_dir/hold_stage_evidence.tsv" w]
    puts $repair_evidence "source\tfirst\tsecond\tsetup_ns\thold_ns"
    foreach row $repair_rows {
        set fields [split [string trim $row] \t]
        if {![string is double -strict [lindex $fields 0]]} {continue}
        if {[llength $fields]!=5} {error "Malformed hold repair evidence: $row"}
        lassign $fields original_slack launch endpoint source_clock destination_clock
        set source_cell [string range $launch 0 end-2]
        set first [string range $endpoint 0 end-2]
        set second [string map {_meta_reg _sync_reg _w1_reg _w2_reg _r1_reg _r2_reg} $first]
        if {$first eq $second} {error "Unknown hold synchronizer: $first"}
        async_register $first
        async_register $second
        # Vivado may insert a noninverting LUT1 for hold repair. Verify its
        # truth table and both edges, rather than assuming a direct connection.
        set first_pin [single [get_pins $first/D] "repaired first stage D"]
        set driver [single [get_pins -of_objects [get_nets -of_objects $first_pin] -filter {DIRECTION == OUT}] "repaired first-stage driver"]
        set driver_name [get_property NAME $driver]
        if {$driver_name ne "$source_cell/Q"} {
            set fix_cell [single [get_cells -of_objects $driver] "hold fix cell"]
            if {[get_property REF_NAME $fix_cell] ne "LUT1" || [get_property INIT $fix_cell] ne "2'h2" || [get_property REF_PIN_NAME $driver] ne "O"} {error "Unexpected hold fix logic: $fix_cell"}
            direct_driver [get_property NAME $fix_cell]/I0 $source_cell/Q
        }
        direct_driver $second/D $first/Q
        if {[clock_of [get_pins $first/C]] ne $destination_clock || [clock_of [get_pins $second/C]] ne $destination_clock} {error "Hold synchronizer clock changed"}
        set margins {}
        foreach delay {max min} {
            set path [single [get_timing_paths -from [get_pins $first/C] -to [get_pins $second/D] -delay_type $delay -max_paths 1] "hold repair second stage $delay"]
            set margin [get_property SLACK $path]
            if {$margin<0 || [get_property EXCEPTION $path] ne ""} {error "Hold repair second stage is failing or excepted"}
            lappend margins $margin
        }
        puts $repair_evidence "$launch\t$first\t$second\t[join $margins \t]"
    }
    close $repair_evidence
}
}
set rd105_review_anchor {report_bus_skew -file "$task_review_dir/bus_skew.rpt"}
if {[string first $rd105_review_anchor $rd105_text]<0} {error "Common skew review entry changed"}
eval [string map [list $rd105_anchor $rd105_extended $rd105_review_anchor "$rd105_repair_audit\n$rd105_review_anchor"] $rd105_text]
