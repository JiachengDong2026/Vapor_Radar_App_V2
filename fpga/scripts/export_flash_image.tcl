# Export the deployed U2 MT25QU256 image format. No hardware connection/programming.
# vivado -mode batch -source export_flash_image.tcl -tclargs routed.dcp external_dir
if {[llength $argv] != 2} {error "Usage: routed.dcp external_output_directory"}
set checkpoint [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set repo [file normalize [file join [file dirname [info script]] ../..]]
set out_key [string tolower $out]
set repo_key [string tolower $repo]
if {$out_key eq $repo_key || [string first "$repo_key/" "$out_key/"] == 0 || [string first "$out_key/" "$repo_key/"] == 0} {
    error "Flash artifacts must be outside the repository and its ancestors"
}
if {![file isfile $checkpoint]} {error "Routed checkpoint missing"}
if {[file exists $out]} {error "Use a new output directory"}
file mkdir $out
cd $out
open_checkpoint $checkpoint
# Same configuration as the verified 2026-10-02 SPIx4 Flash image.
set_property CONFIG_MODE SPIx4 [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 10.6 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
write_bitstream [file join $out vapor_lidar_top_spi4.bit]
write_cfgmem -format MCS -size 32 -interface SPIx4 -loadbit "up 0x00000000 [file join $out vapor_lidar_top_spi4.bit]" [file join $out vapor_lidar_top_spi4.mcs]
# MCS and BIN export share the .prm metadata basename in this new directory.
write_cfgmem -force -format BIN -size 32 -interface SPIx4 -loadbit "up 0x00000000 [file join $out vapor_lidar_top_spi4.bit]" [file join $out vapor_lidar_top_spi4.bin]
puts "FLASH_IMAGE_READY"
exit
