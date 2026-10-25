[CmdletBinding()]
param([string]$VivadoBin = "D:\XILINX\Vivado\2019.1\bin")
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
python (Join-Path $root "scripts/gen_coeffs.py")
if ($LASTEXITCODE -ne 0) { throw "coefficients failed" }
python (Join-Path $root "tests/verify_wide_dfe.py")
if ($LASTEXITCODE -ne 0) { throw "response failed" }
Push-Location (Join-Path $root "build/sim_wide")
try {
    & (Join-Path $VivadoBin "xvlog.bat") -sv ../../rtl/wide_fir_dec2.sv ../../tests/tb_wide_fir.sv
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }
    & (Join-Path $VivadoBin "xelab.bat") --relax tb_wide_fir -s wide_test
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }
    & (Join-Path $VivadoBin "xsim.bat") wide_test -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed" }
    if (-not (Select-String -Path xsim.log -Pattern "WIDE_FIR_PASS" -Quiet)) { throw "missing pass marker" }
} finally { Pop-Location }
