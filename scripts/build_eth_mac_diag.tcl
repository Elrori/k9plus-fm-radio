set root [file normalize [file join [file dirname [info script]] ..]]
set ref [file normalize [file join $root .. .. verilog-ethernet-anlogic rtl]]
set out [file join $root build eth_mac_diag]
file mkdir $out
cd $root
read_verilog [list [file join $ref lfsr.v] [file join $ref axis_gmii_tx.v]]
read_verilog -sv [list rtl/rgmii_tx.sv rtl/eth_mac_diag_top.sv]
read_xdc constraints/eth_diag.xdc
synth_design -top eth_mac_diag_top -part xc7a50t-fgg484-1
opt_design
place_design
route_design
report_drc -file [file join $out drc.rpt]
report_timing_summary -file [file join $out timing.rpt]
write_bitstream -force [file join $out eth_mac_diag.bit]
puts "ETH_MAC_DIAG_BUILD_PASS"
exit
