[CmdletBinding()]
param(
    [string]$Vivado = "D:\XILINX\Vivado\2019.1\bin\vivado.bat",
    [string]$Bit = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$bit = if ($Bit) {
    if ([IO.Path]::IsPathRooted($Bit)) { [IO.Path]::GetFullPath($Bit) }
    else { [IO.Path]::GetFullPath((Join-Path $root $Bit)) }
} else {
    Join-Path $root "build\k9plus_fm_radio.bit"
}
if (-not (Test-Path -LiteralPath $bit)) { throw "Build the bitstream first: $bit" }
$bitTcl = $bit.Replace('\', '/')
$tcl = Join-Path $root "build\program_generated.tcl"
@"
load_features labtools
open_hw
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a50t*] 0]
if {[llength `$dev] == 0} { error "XC7A50T JTAG device not found" }
current_hw_device `$dev
refresh_hw_device `$dev
set_property PROGRAM.FILE {$bitTcl} `$dev
program_hw_devices `$dev
puts "K9PLUS_FM_PROGRAM_PASS"
close_hw
exit
"@ | Set-Content -LiteralPath $tcl -Encoding ascii
& $Vivado -mode batch -nojournal -nolog -source $tcl
if ($LASTEXITCODE -ne 0) { throw "Vivado programming failed: $LASTEXITCODE" }
