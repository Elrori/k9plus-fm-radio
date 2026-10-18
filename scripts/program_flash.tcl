load_features labtools

foreach name {K9_FLASH_BIN K9_UNLOCK_BIT K9_CFGMEM_PART} {
    if {![info exists ::env($name)]} { error "Missing environment variable $name" }
}

set binfile [file normalize $::env(K9_FLASH_BIN)]
set unlock_bit [file normalize $::env(K9_UNLOCK_BIT)]
set part_name $::env(K9_CFGMEM_PART)
if {![file exists $binfile]} { error "Configuration image not found: $binfile" }
if {![file exists $unlock_bit]} { error "Flash write-protect image not found: $unlock_bit" }

open_hw
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a50t*] 0]
if {[llength $dev] == 0} { error "XC7A50T JTAG device not found" }
current_hw_device $dev
refresh_hw_device $dev

set part [lindex [get_cfgmem_parts -of_objects $dev $part_name] 0]
if {[llength $part] == 0} { error "Unsupported cfgmem part for XC7A50T: $part_name" }

# The XI050CD vendor image releases the board-level SPI write protection.
set_property PROGRAM.FILE $unlock_bit $dev
program_hw_devices $dev
after 1000

create_hw_cfgmem -hw_device $dev $part
set cfgmem [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.FILES $binfile $cfgmem
set_property PROGRAM.PRM_FILE {} $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
set_property PROGRAM.BLANK_CHECK 0 $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem
set_property PROGRAM.CHECKSUM 0 $cfgmem

create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
refresh_hw_device $dev
program_hw_cfgmem -hw_cfgmem $cfgmem
puts "K9PLUS_FM_FLASH_PROGRAM_VERIFY_PASS"

# Reconfigure from non-volatile SPI flash so the just-written image is also
# exercised before this script reports success.
boot_hw_device $dev
after 3000
refresh_hw_device $dev
puts "K9PLUS_FM_FLASH_BOOT_REQUESTED"

close_hw
exit
