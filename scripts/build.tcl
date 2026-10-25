set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build]
set ref [file normalize [file join $root .. .. verilog-ethernet-anlogic rtl]]
file mkdir $out
cd $root

# Non-project synthesis does not automatically load parameterized macros.
set xpm_root [file join $::env(K9_VIVADO_ROOT) data ip xpm]
read_verilog -sv [list \
    [file join $xpm_root xpm_cdc hdl xpm_cdc.sv] \
    [file join $xpm_root xpm_memory hdl xpm_memory.sv] \
    [file join $xpm_root xpm_fifo hdl xpm_fifo.sv]]

read_verilog [list [file join $ref lfsr.v] [file join $ref axis_gmii_tx.v]]
read_verilog -sv [list \
    rtl/clock_gen.sv \
    rtl/nco_mixer_2x.sv \
    rtl/cic3_decimator_2x.sv \
    rtl/wide_fir_dec2.sv \
    rtl/complex_fir.sv \
    rtl/fm_discriminator.sv \
    rtl/cic3_decimator.sv \
    rtl/audio_post.sv \
    rtl/udp_audio_axis_tx.sv \
    rtl/udp_iq_axis_tx.sv \
    rtl/udp_raw_axis_tx.sv \
    rtl/iq_sample_cdc.sv \
    rtl/raw_sample_cdc.sv \
    rtl/rgmii_tune_rx.sv \
    rtl/rgmii_tx.sv \
    rtl/k9plus_fm_top.sv]
read_xdc constraints/k9plus_fm.xdc

synth_design -top k9plus_fm_top -part xc7a50t-fgg484-1 -flatten_hierarchy rebuilt
write_checkpoint -force [file join $out post_synth.dcp]
report_drc -file [file join $out drc_synth.rpt]
report_utilization -hierarchical -file [file join $out utilization_synth.rpt]
report_timing_summary -file [file join $out timing_synth.rpt]

opt_design
place_design
phys_opt_design
route_design
phys_opt_design
report_drc -file [file join $out drc_route.rpt]
report_route_status -file [file join $out route_status.rpt]
report_utilization -hierarchical -file [file join $out utilization_route.rpt]
report_timing_summary -max_paths 20 -file [file join $out timing_route.rpt]
write_checkpoint -force [file join $out routed.dcp]

set bitfile [file join $out k9plus_fm_radio.bit]
write_bitstream -force $bitfile
write_cfgmem -force -format bin -interface SPIx1 -size 16 \
    -loadbit "up 0x0 $bitfile" -file [file join $out k9plus_fm_radio.bin]
puts "K9PLUS_FM_BUILD_PASS"
exit
