set_property PACKAGE_PIN W19 [get_ports clk_25m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_25m]
create_clock -name board_clk_25m -period 40.000 [get_ports clk_25m]

# Expansion IO2[32:33], Bank 35 IO_L2P/N_T0_AD12P/N_35.
set_property PACKAGE_PIN C2 [get_ports rf_p]
set_property PACKAGE_PIN B2 [get_ports rf_n]
set_property IOSTANDARD LVDS_25 [get_ports {rf_p rf_n}]
set_property DIFF_TERM FALSE [get_ports {rf_p rf_n}]
set_false_path -from [get_ports {rf_p rf_n}]

set_property PACKAGE_PIN V18 [get_ports {key_n[0]}]
set_property PACKAGE_PIN V19 [get_ports {key_n[1]}]
set_property PACKAGE_PIN U18 [get_ports {key_n[2]}]
set_property PACKAGE_PIN P16 [get_ports {key_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key_n[*]}]
set_property PULLUP TRUE [get_ports {key_n[*]}]
set_false_path -from [get_ports {key_n[*]}]

set_property PACKAGE_PIN P17 [get_ports {led[0]}]
set_property PACKAGE_PIN V20 [get_ports {led[1]}]
set_property PACKAGE_PIN V22 [get_ports {led[2]}]
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
set_property DRIVE 4 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]

# RGMII Ethernet PHY 0 from colorlight_k9plus_ext.
set_property PACKAGE_PIN W4 [get_ports eth_tx_clk]
set_property PACKAGE_PIN V4 [get_ports eth_rx_clk]
set_property PACKAGE_PIN Y4 [get_ports eth_tx_ctl]
set_property PACKAGE_PIN AA1 [get_ports eth_rx_ctl]
set_property PACKAGE_PIN AA3 [get_ports {eth_tx_data[0]}]
set_property PACKAGE_PIN AA4 [get_ports {eth_tx_data[1]}]
set_property PACKAGE_PIN AB5 [get_ports {eth_tx_data[2]}]
set_property PACKAGE_PIN AA5 [get_ports {eth_tx_data[3]}]
set_property PACKAGE_PIN AB1 [get_ports {eth_rx_data[0]}]
set_property PACKAGE_PIN AB2 [get_ports {eth_rx_data[1]}]
set_property PACKAGE_PIN Y3  [get_ports {eth_rx_data[2]}]
set_property PACKAGE_PIN AB3 [get_ports {eth_rx_data[3]}]
set_property PACKAGE_PIN W21 [get_ports eth_mdc]
set_property PACKAGE_PIN Y22 [get_ports eth_mdio]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_clk eth_rx_clk eth_tx_ctl eth_rx_ctl eth_tx_data[*] eth_rx_data[*] eth_mdc eth_mdio}]
set_property DRIVE 8 [get_ports {eth_tx_clk eth_tx_ctl eth_tx_data[*]}]
set_property SLEW FAST [get_ports {eth_tx_clk eth_tx_ctl eth_tx_data[*]}]
set_property PACKAGE_PIN W22 [get_ports eth_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports eth_rst_n]
create_clock -name phy0_rx_clk -period 8.000 [get_ports eth_rx_clk]
set_false_path -from [get_ports {eth_rx_ctl eth_rx_data[*]}]

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
set_property CONFIG_MODE SPIx1 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR NO [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

# The 120 MHz DSP and 125 MHz Ethernet MMCM outputs are independent. All data
# between them uses explicit toggle/data synchronizers.
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks rf_clk_unbuf] \
    -group [get_clocks phy0_rx_clk]
