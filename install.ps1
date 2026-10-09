# Installs MyImportExport into a Clarion 12 installation and registers the template.
# Usage:  pwsh .\install.ps1 [-ClarionRoot C:\clarion12]
param([string]$ClarionRoot = 'C:\clarion12')
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$tpl  = Join-Path $ClarionRoot 'accessory\template\win'
$lib  = Join-Path $ClarionRoot 'accessory\libsrc\win'
$bin  = Join-Path $ClarionRoot 'accessory\bin'
foreach ($d in $tpl, $lib, $bin) { New-Item -ItemType Directory -Force $d | Out-Null }
Copy-Item "$here\template\MyImportExport.tpl", "$here\template\MyImportExport.tpw" $tpl -Force
Copy-Item "$here\libsrc\MyImportExport.inc", "$here\libsrc\MyImportExport.clw" $lib -Force
Copy-Item "$here\bin\MIEConvert.exe" $bin -Force
Write-Host "Copied template -> $tpl"
Write-Host "Copied class    -> $lib"
Write-Host "Copied helper   -> $bin"
& (Join-Path $ClarionRoot 'bin\ClarionCL.exe') -tr "$tpl\MyImportExport.tpl"
Write-Host "Template registered. Restart the Clarion IDE if it is open."
