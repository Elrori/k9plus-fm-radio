set_property PACKAGE_PIN V4 [get_ports eth_rx_clk]
set_property IOSTANDARD LVCMOS33 [get_ports eth_rx_clk]
create_clock -name phy0_rx_clk -period 8.000 [get_ports eth_rx_clk]

set_property PACKAGE_PIN W4  [get_ports eth_tx_clk]
set_property PACKAGE_PIN Y4  [get_ports eth_tx_ctl]
set_property PACKAGE_PIN AA3 [get_ports {eth_tx_data[0]}]
set_property PACKAGE_PIN AA4 [get_ports {eth_tx_data[1]}]
set_property PACKAGE_PIN AB5 [get_ports {eth_tx_data[2]}]
set_property PACKAGE_PIN AA5 [get_ports {eth_tx_data[3]}]

set_property PACKAGE_PIN W20  [get_ports eth1_tx_clk]
set_property PACKAGE_PIN AA20 [get_ports eth1_tx_ctl]
set_property PACKAGE_PIN AB21 [get_ports {eth1_tx_data[0]}]
set_property PACKAGE_PIN AA21 [get_ports {eth1_tx_data[1]}]
set_property PACKAGE_PIN AB22 [get_ports {eth1_tx_data[2]}]
set_property PACKAGE_PIN Y21  [get_ports {eth1_tx_data[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_clk eth_tx_ctl eth_tx_data[*] eth1_tx_clk eth1_tx_ctl eth1_tx_data[*]}]
set_property DRIVE 8 [get_ports {eth_tx_clk eth_tx_ctl eth_tx_data[*] eth1_tx_clk eth1_tx_ctl eth1_tx_data[*]}]
set_property SLEW FAST [get_ports {eth_tx_clk eth_tx_ctl eth_tx_data[*] eth1_tx_clk eth1_tx_ctl eth1_tx_data[*]}]

set_property PACKAGE_PIN P17 [get_ports {led[0]}]
set_property PACKAGE_PIN V20 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_property PACKAGE_PIN W22 [get_ports eth_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports eth_rst_n]

set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
