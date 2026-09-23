# Formal source list; external test projects are not dependencies.
set root [file normalize [file join [file dirname [info script]] ..]]
set repo [file dirname $root]
if {[info exists ::env(VAPOR_BUILD_ROOT)]} {
    set artifact_root [file normalize $::env(VAPOR_BUILD_ROOT)]
} else {
    set artifact_root [file normalize [file join $repo .. Vapor_Lc_App_Test formal_build]]
}
file mkdir $artifact_root
set include_dirs [list "$root/rtl/include" "$root/rtl/adc" "$root/rtl/dila" "$root/sim/system/vectors"]
set sources [list \
    "$root/rtl/control/action_controller.v" \
    "$root/rtl/adc/adc_cycle_framer.v" \
    "$root/rtl/control/cfg_bus_arbiter.v" \
    "$root/rtl/control/cfg_status_poller.v" \
    "$root/rtl/clock/clk_rst_mgr.v" \
    "$root/rtl/clock/clock_health_monitor.v" \
    "$root/rtl/control/cmd_decoder.v" \
    "$root/rtl/control/config_divider.v" \
    "$root/rtl/control/counter_cdc.v" \
    "$root/rtl/stream/data_packetizer.v" \
    "$root/rtl/stream/event_record_fifo.v" \
    "$root/rtl/usb/gpif_slave_fifo_master.v" \
    "$root/rtl/usb/gpif_transport_buffers.v" \
    "$root/rtl/control/reg_ctrl_crossbar.v" \
    "$root/rtl/sensors/sensor_hub.v" \
    "$root/rtl/control/status_manager.v" \
    "$root/rtl/motor/stepper_ctrl.v" \
    "$root/rtl/stream/stream_arbiter.v" \
    "$root/rtl/stream/stream_gate.v" \
    "$root/rtl/control/system_registers.v" \
    "$root/rtl/clock/system_reset_controller.v" \
    "$root/rtl/time/timestamp_capture.v" \
    "$root/rtl/time/time_sync_core.v" \
    "$root/rtl/usb/transport_async_fifo.v" \
    "$root/rtl/usb/usb_fx3_gpif_if.v" \
    "$root/rtl/top/vapor_lidar_top.v" \
    "$root/rtl/control/vlp_cmd_rx.v" \
    "$root/rtl/control/watchdog.v" \
    "$root/rtl/stream/word_to_byte_stream.v" \
    "$root/rtl/common/async_fifo_wrap.v" \
    "$root/rtl/common/bulk_stream_fifo.v" \
    "$root/rtl/common/cdc_bit_sync.v" \
    "$root/rtl/common/cdc_bus_handshake.v" \
    "$root/rtl/common/cdc_pulse_sync.v" \
    "$root/rtl/common/cfg_bus_if.v" \
    "$root/rtl/common/msg_stream_fifo.v" \
    "$root/rtl/common/sample_stream_fifo.v" \
    "$root/rtl/common/sync_fifo.v" \
    "$root/rtl/common/system_timebase.v" \
    "$root/rtl/adc/adc3660_ddr_rx.v" \
    "$root/rtl/adc/adc_ad4630_if.v" \
    "$root/rtl/adc/adc_adc3660_if.v" \
    "$root/rtl/adc/adc_channel_regs.v" \
    "$root/rtl/adc/adc_debug_uart.v" \
    "$root/rtl/adc/adc_spi_master.v" \
    "$root/rtl/adc/adc_stream_fanout.v" \
    "$root/rtl/dila/dila_block_framer.v" \
    "$root/rtl/dila/dila_core.v" \
    "$root/rtl/dila/dila_lpf.v" \
    "$root/rtl/dila/dila_magnitude.v" \
    "$root/rtl/dila/dila_mixer.v" \
    "$root/rtl/dila/dila_ref_gen.v" \
    "$root/rtl/adc/member1_adc_dila.v" \
    "$root/rtl/adc/member1_async_fifo.v" \
    "$root/rtl/adc/member1_board_clock.v" \
    "$root/rtl/dila/member1_divider.v" \
    "$root/rtl/dila/member1_divider64.v" \
    "$root/rtl/adc/member1_uart_tx.v" \
    "$root/rtl/dac/dac_ad5791_if.v" \
    "$root/rtl/wms/sine_lut.v" \
    "$root/rtl/wms/wms_dac_channel.v" \
    "$root/rtl/wms/wms_dac_dual.v" \
    "$root/rtl/wms/wms_unsigned_divider.v" \
    "$root/rtl/wms/wms_wavegen.v" \
    "$root/rtl/sensors/ai8_modbus_rs485.v" \
    "$root/rtl/sensors/ai8_poll_core.v" \
    "$root/rtl/sensors/bmp390_driver.v" \
    "$root/rtl/sensors/crc16_modbus.v" \
    "$root/rtl/sensors/epsilon_link_recovery.v" \
    "$root/rtl/sensors/epsilon_rs232.v" \
    "$root/rtl/sensors/epsilon_rs422.v" \
    "$root/rtl/sensors/hmp_modbus_rs485.v" \
    "$root/rtl/sensors/i2c_arbiter_2.v" \
    "$root/rtl/sensors/i2c_master.v" \
    "$root/rtl/sensors/member3_sensor_bank.v" \
    "$root/rtl/sensors/modbus_rtu_master.v" \
    "$root/rtl/sensors/msg_stream_hex_uart.v" \
    "$root/rtl/sensors/ptb210_rs232.v" \
    "$root/rtl/sensors/rd105_uart.v" \
    "$root/rtl/sensors/rs485_halfduplex_ctrl.v" \
    "$root/rtl/sensors/rs485_transaction_arbiter.v" \
    "$root/rtl/sensors/sensor_record_fifo.v" \
    "$root/rtl/sensors/sht45_driver.v" \
    "$root/rtl/sensors/tfa1500_parser.v" \
    "$root/rtl/sensors/tfa1500_uart.v" \
    "$root/rtl/sensors/uart_rx.v" \
    "$root/rtl/sensors/uart_tx.v"]
proc prepare_memories {work} {
    global root
    file copy -force "$root/rtl/wms/sine_q31.mem" "$work/sine_q31.mem"
    foreach group {system adc_dila sensors wms_dac} {
        foreach f [glob -nocomplain "$root/sim/$group/vectors/*"] {
            if {[file isfile $f]} {file copy -force $f [file join $work [file tail $f]]}
        }
    }
}
