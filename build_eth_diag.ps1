[CmdletBinding()]
param([string]$Vivado = "D:\XILINX\Vivado\2019.1\bin\vivado.bat")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root
try {
    & $Vivado -mode batch -nojournal -nolog -source scripts\build_eth_diag.tcl
    if ($LASTEXITCODE -ne 0) { throw "Vivado diagnostic build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}
