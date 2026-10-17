set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build eth_diag]
file mkdir $out
cd $root
read_verilog -sv [list rtl/crc32_8bit.sv rtl/udp_audio_tx.sv rtl/rgmii_tx.sv rtl/eth_diag_top.sv]
read_xdc constraints/eth_diag.xdc
synth_design -top eth_diag_top -part xc7a50t-fgg484-1
opt_design
place_design
route_design
report_drc -file [file join $out drc.rpt]
report_timing_summary -file [file join $out timing.rpt]
write_bitstream -force [file join $out eth_diag.bit]
puts "ETH_DIAG_BUILD_PASS"
exit
