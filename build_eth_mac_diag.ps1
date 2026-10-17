$ErrorActionPreference = 'Stop'
$vivado = 'D:\XILINX\Vivado\2019.1\bin\vivado.bat'
& $vivado -mode batch -source scripts\build_eth_mac_diag.tcl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
