[CmdletBinding()]
param([string]$VivadoBin = "D:\XILINX\Vivado\2019.1\bin")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $root "build\sim_fm"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$memOut = Join-Path $out "mem"
New-Item -ItemType Directory -Force -Path $memOut | Out-Null
Copy-Item -Force (Join-Path $root "mem\sine_q15_1024.mem") $memOut
Copy-Item -Force (Join-Path $root "mem\channel_fir_q18.mem") $memOut
$files = @(
    (Join-Path $root "rtl\nco_mixer_2x.sv"),
    (Join-Path $root "rtl\cic3_decimator_2x.sv"),
    (Join-Path $root "rtl\complex_fir.sv"),
    (Join-Path $root "rtl\fm_discriminator.sv"),
    (Join-Path $root "rtl\cic3_decimator.sv"),
    (Join-Path $root "rtl\audio_post.sv"),
    (Join-Path $root "tests\tb_fm_chain.sv")
)
Push-Location $out
try {
    & (Join-Path $VivadoBin "xvlog.bat") -sv $files
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }
    & (Join-Path $VivadoBin "xelab.bat") --relax tb_fm_chain -s tb_fm_chain_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }
    & (Join-Path $VivadoBin "xsim.bat") tb_fm_chain_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed" }
    python (Join-Path $root "tests\verify_fm_chain.py")
    if ($LASTEXITCODE -ne 0) { throw "FM-chain verification failed" }
} finally {
    Pop-Location
}
