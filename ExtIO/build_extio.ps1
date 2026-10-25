[CmdletBinding()]
param([string]$PlatformToolset = 'v145')
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Installer vswhere.exe not found.' }
$install = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
if (-not $install) { throw 'Visual Studio with MSBuild was not found.' }
$msbuild = Join-Path $install 'MSBuild\Current\Bin\MSBuild.exe'
& $msbuild (Join-Path $PSScriptRoot 'ExtIO_K9Plus_FM.vcxproj') '/m' `
    '/p:Configuration=Release' '/p:Platform=Win32' "/p:PlatformToolset=$PlatformToolset"
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed ($LASTEXITCODE)" }
Write-Host (Join-Path $PSScriptRoot 'Release\ExtIO_K9Plus_FM_6M.dll')
