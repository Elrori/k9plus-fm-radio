[CmdletBinding()]
param([string]$VivadoBin = "D:\XILINX\Vivado\2019.1\bin")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $root "build\sim_udp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$files = @(
    (Join-Path $root "rtl\crc32_8bit.sv"),
    (Join-Path $root "rtl\udp_audio_tx.sv"),
    (Join-Path $root "tests\tb_udp_audio_tx.sv")
)
Push-Location $out
try {
    & (Join-Path $VivadoBin "xvlog.bat") -sv $files
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }
    & (Join-Path $VivadoBin "xelab.bat") tb_udp_audio_tx -s tb_udp_audio_tx_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }
    & (Join-Path $VivadoBin "xsim.bat") tb_udp_audio_tx_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed" }
    python (Join-Path $root "tests\verify_packet.py")
    if ($LASTEXITCODE -ne 0) { throw "packet verification failed" }
} finally {
    Pop-Location
}
