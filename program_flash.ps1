[CmdletBinding()]
param(
    [string]$Vivado = "D:\XILINX\Vivado\2019.1\bin\vivado.bat",
    [string]$Bin = "",
    [string]$CfgMemPart = "mx25l12845g-spi-x1_x2_x4"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$image = if ($Bin) {
    if ([IO.Path]::IsPathRooted($Bin)) { [IO.Path]::GetFullPath($Bin) }
    else { [IO.Path]::GetFullPath((Join-Path $root $Bin)) }
} else {
    Join-Path $root "build\k9plus_fm_radio.bin"
}
$unlock = Join-Path $root "hardware\bigpig-xilinx\XI050CD\Flash_Write_Protect_Cancel.bit"
$script = Join-Path $root "scripts\program_flash.tcl"

if (-not (Test-Path -LiteralPath $Vivado)) { throw "Vivado not found: $Vivado" }
if (-not (Test-Path -LiteralPath $image)) { throw "Build the configuration image first: $image" }
if (-not (Test-Path -LiteralPath $unlock)) { throw "Initialize the hardware submodule first: $unlock" }

$env:K9_FLASH_BIN = $image
$env:K9_UNLOCK_BIT = $unlock
$env:K9_CFGMEM_PART = $CfgMemPart
try {
    & $Vivado -mode batch -nojournal -nolog -source $script
    if ($LASTEXITCODE -ne 0) { throw "Vivado flash programming failed: $LASTEXITCODE" }
} finally {
    Remove-Item Env:K9_FLASH_BIN -ErrorAction SilentlyContinue
    Remove-Item Env:K9_UNLOCK_BIT -ErrorAction SilentlyContinue
    Remove-Item Env:K9_CFGMEM_PART -ErrorAction SilentlyContinue
}
