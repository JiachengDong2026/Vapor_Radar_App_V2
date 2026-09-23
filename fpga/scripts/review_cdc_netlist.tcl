# Read-only inspection of the final checkpoint; all evidence goes to the review directory.
# vivado -mode batch -source review_cdc_netlist.tcl -tclargs routed.dcp cdc_review
set task_checkpoint [file normalize [lindex $argv 0]]
set task_review_dir [file normalize [lindex $argv 1]]
if {![file exists $task_checkpoint] || ![file exists "$task_review_dir/cdc_entries.tcl"]} {error "Missing final checkpoint or parsed CDC entries"}
set_param general.maxThreads 2
open_checkpoint $task_checkpoint
source "$task_review_dir/cdc_entries.tcl"
set task_fh [open "$task_review_dir/netlist_endpoints.tsv" w]
puts $task_fh "rule\tsource\tdestination\tsource_ref\tdestination_ref\tchecks"
proc single {objects label} {
    if {[llength $objects]!=1} {error "Expected one $label, got [llength $objects]: $objects"}
    return [lindex $objects 0]
}
proc async_register {name} {
    set cell [single [get_cells -quiet $name] $name]
    if {![string match FD* [get_property REF_NAME $cell]] || ![get_property ASYNC_REG $cell]} {error "Not an ASYNC_REG flop: $name"}
    return $cell
}
proc direct_driver {destination expected} {
    set pin [single [get_pins -quiet $destination] $destination]
    set net [single [get_nets -of_objects $pin] "net of $destination"]
    set drivers [get_pins -of_objects $net -filter {DIRECTION == OUT}]
    if {[llength $drivers]!=1 || [get_property NAME $drivers] ne $expected} {error "Unexpected direct driver of $destination: $drivers expected $expected"}
}
proc clock_of {pin} {
    return [get_property NAME [single [get_clocks -of_objects $pin] "clock of $pin"]]
}
set task_memory_count 0
set task_reset_count 0
foreach entry $cdc_entries {
    lassign $entry rule source_clock destination_clock source destination
    set from [single [get_pins -quiet $source] $source]
    set to [single [get_pins -quiet $destination] $destination]
    set from_cell [single [get_cells -of_objects $from] "cell of $source"]
    set to_cell [single [get_cells -of_objects $to] "cell of $destination"]
    set from_ref [get_property REF_NAME $from_cell]
    set to_ref [get_property REF_NAME $to_cell]
    set starts [get_property NAME [all_fanin -flat -startpoints_only -to $to]]
    if {$source ni $starts} {error "Reported source not in endpoint fanin: $source -> $destination starts=$starts"}
    if {$rule eq "CDC-13"} {
        incr task_memory_count
        if {![string match {u_member1/u_adc1/u_word_cdc/*} $source] || ![string match {u_member1/u_adc1/u_capture_fifo/*} $destination]} {error "Unreviewed memory crossing $source -> $destination"}
        if {$source_clock ne "g_hw.shifted" || $destination_clock ne "sys_raw"} {error "Unreviewed memory clock pair"}
        if {![string match RAM* $from_ref] || ![string match RAM* $to_ref]} {error "Not memory primitives: $from_ref -> $to_ref"}
        if {[get_property REF_PIN_NAME $from] ne "CLK" || [get_property REF_PIN_NAME $to] ne "I"} {error "Not reviewed memory CLK -> I pins"}
        if {[clock_of $from] ne $source_clock} {error "Memory source clock mismatch"}
        set to_clock [single [get_pins -of_objects $to_cell -filter {REF_PIN_NAME == CLK}] "capture memory clock"]
        if {[clock_of $to_clock] ne $destination_clock} {error "Memory capture clock mismatch"}
        set path [single [get_timing_paths -from $from -to $to -delay_type max -max_paths 1] "bounded memory data path"]
        if {[get_property SLACK $path]<0} {error "Memory data path violates bound: $source -> $destination"}
        if {[get_property EXCEPTION $path] ne "MaxDelay Path 20.000ns -datapath_only"} {error "Memory data path lost the reviewed 20ns datapath bound"}
        puts $task_fh "$rule\t$source\t$destination\t$from_ref\t$to_ref\tslack=[get_property SLACK $path];exception=[get_property EXCEPTION $path]"
    } elseif {$rule eq "CDC-10"} {
        incr task_reset_count
        set reset_cases [dict create \
          {u_member1/u_adc1/monitor_reset_pipe_reg[0]/CLR} [list u_member1/u_adc1/monitor_reset_pipe_reg 3 g_hw.shifted] \
          {u_member1/u_adc1/rx_reset_pipe_reg[0]/CLR} [list u_member1/u_adc1/rx_reset_pipe_reg 2 g_hw.shifted] \
          {u_member1/u_adc1/u_rx/capture_reset_pipe_reg[0]/CLR} [list u_member1/u_adc1/u_rx/capture_reset_pipe_reg 3 g_hw.shifted] \
          {u_clock/gpif_release_reg[0]/CLR} [list u_clock/gpif_release_reg 16 gpif_raw]]
        if {![dict exists $reset_cases $destination]} {error "Unreviewed reset destination: $destination"}
        lassign [dict get $reset_cases $destination] base depth expected_clock
        if {![string match FD* $from_ref] || [get_property REF_PIN_NAME $from] ne "C" || [get_property REF_PIN_NAME $to] ne "CLR"} {error "Unexpected reset endpoints"}
        if {[clock_of $from] ne $source_clock || $destination_clock ne $expected_clock} {error "Reset clock mismatch"}
        for {set stage 0} {$stage<$depth} {incr stage} {
            set cell_name [format {%s[%d]} $base $stage]
            async_register $cell_name
            if {[clock_of [get_pins $cell_name/C]] ne $expected_clock} {error "Reset release stage clock mismatch"}
            if {$stage>0} {
                set previous [format {%s[%d]} $base [expr {$stage-1}]]
                direct_driver $cell_name/D $previous/Q
                set timing [single [get_timing_paths -from [get_pins $previous/C] -to [get_pins $cell_name/D] -max_paths 1] "reset release timed stage"]
                if {[get_property SLACK $timing]<0 || [get_property EXCEPTION $timing] ne ""} {error "Reset release stage is excepted or failing"}
            }
        }
        puts $task_fh "$rule\t$source\t$destination\t$from_ref\t$to_ref\tASYNC_REG_stages=$depth;direct_timed_chain=1"
    } else {error "Unreviewed critical CDC rule $rule"}
}
close $task_fh
set task_fh [open "$task_review_dir/synchronizer_evidence.txt" w]
foreach {label port base} {
 PTB210 FPGA_RS232A_RXD u_member3/u_0/u_uart_rx
 HMP FPGA_RS485_RXD_L u_member3/u_1/core/transport/rx
 AI8 FPGA_RS485_RXD_L u_member3/u_6/core/master/rx
 EPSILON FPGA_RS232B_RXD u_member3/u_2/u_rx
 TFA_HF FPGA_UART_RXD_L u_member3/u_5/u_hf_rx
 TFA_LF TFA_LF_RXD u_member3/u_5/u_lf_rx
} {
    async_register ${base}/rxd_meta_reg
    async_register ${base}/rxd_sync_reg
    set starts [get_property NAME [all_fanin -flat -startpoints_only -to [get_pins ${base}/rxd_meta_reg/D]]]
    if {$starts ne $port} {error "UART does not capture expected raw physical port: $label $starts"}
    direct_driver ${base}/rxd_sync_reg/D ${base}/rxd_meta_reg/Q
    set path [single [get_timing_paths -from [get_pins ${base}/rxd_meta_reg/C] -to [get_pins ${base}/rxd_sync_reg/D] -max_paths 1] "UART second stage"]
    if {[get_property SLACK $path]<0 || [get_property EXCEPTION $path] ne ""} {error "UART second stage is excepted or failing"}
    puts $task_fh "$label raw_port=$starts two_async_stages=1 direct_driver=1 setup_slack=[get_property SLACK $path]"
}
foreach {prefix first_suffix second_suffix src_clock dst_clock} {
 rd w1 w2 sys_raw g_hw.shifted
 wr r1 r2 g_hw.shifted sys_raw
} {
    for {set bit 0} {$bit<9} {incr bit} {
        set base u_member1/u_adc1/u_word_cdc
        set first [format {%s/%s_gray_%s_reg[%d]} $base $prefix $first_suffix $bit]
        set second [format {%s/%s_gray_%s_reg[%d]} $base $prefix $second_suffix $bit]
        async_register $first
        async_register $second
        set start [single [all_fanin -flat -startpoints_only -to [get_pins $first/D]] "Gray bit launch"]
        set start_cell [single [get_cells -of_objects $start] "Gray launch cell"]
        set start_name [get_property NAME $start_cell]
        set expected [format {%s/%s_gray_reg[%d]} $base $prefix $bit]
        set expected_msb [format {%s/%s_bin_reg[%d]} $base $prefix $bit]
        if {$start_name ne $expected && !($bit==8 && $start_name eq $expected_msb)} {error "Wrong Gray bit launch: $start_name"}
        if {[clock_of $start] ne $src_clock || [clock_of [get_pins $first/C]] ne $dst_clock} {error "Gray clock pair mismatch"}
        direct_driver $first/D $start_name/Q
        direct_driver $second/D $first/Q
        set path [single [get_timing_paths -from [get_pins $first/C] -to [get_pins $second/D] -max_paths 1] "Gray second stage"]
        if {[get_property SLACK $path]<0 || [get_property EXCEPTION $path] ne ""} {error "Gray second stage is excepted or failing"}
        puts $task_fh "GRAY_${prefix}_$bit first=$first source=$start second=$second two_async_stages=1 slack=[get_property SLACK $path]"
    }
}
close $task_fh
report_bus_skew -file "$task_review_dir/bus_skew.rpt"
write_xdc -force "$task_review_dir/routed_resolved.xdc"
puts "FORMAL_CDC_NETLIST_REVIEW_PASS memory_entries=$task_memory_count reset_entries=$task_reset_count"
close_design
exit
