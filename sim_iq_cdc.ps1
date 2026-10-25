[CmdletBinding()]
param([string]$VivadoBin = "D:\XILINX\Vivado\2019.1\bin")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $root "build\sim_iq_cdc"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$files = @((Join-Path $root "rtl\iq_sample_cdc.sv"), (Join-Path $root "tests\tb_iq_sample_cdc.sv"))
$glbl = Join-Path (Split-Path -Parent $VivadoBin) "data\verilog\src\glbl.v"
Push-Location $out
try {
    & (Join-Path $VivadoBin "xvlog.bat") -sv $files
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }
    & (Join-Path $VivadoBin "xvlog.bat") $glbl
    if ($LASTEXITCODE -ne 0) { throw "xvlog glbl failed" }
    & (Join-Path $VivadoBin "xelab.bat") --relax -L xpm tb_iq_sample_cdc glbl -s tb_iq_sample_cdc_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }
    & (Join-Path $VivadoBin "xsim.bat") tb_iq_sample_cdc_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed" }
} finally { Pop-Location }
