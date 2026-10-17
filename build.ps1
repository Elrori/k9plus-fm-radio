[CmdletBinding()]
param(
    [string]$Vivado = "D:\XILINX\Vivado\2019.1\bin\vivado.bat"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado not found: $Vivado"
}
Push-Location $root
try {
    python scripts\gen_coeffs.py
    & $Vivado -mode batch -nojournal -nolog -source scripts\build.tcl
    if ($LASTEXITCODE -ne 0) { throw "Vivado failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
