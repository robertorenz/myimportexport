# Builds and runs the headless class test. Usage: pwsh test\build.ps1 [-NoRun]
param([switch]$NoRun)
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$build = Join-Path $PSScriptRoot '.build'
New-Item -ItemType Directory -Force $build | Out-Null
Copy-Item "$root\libsrc\win\*" $build -Force
Copy-Item "$PSScriptRoot\MIETest.clw" $build -Force
if (Test-Path "$root\bin\MIEConvert.exe") { Copy-Item "$root\bin\MIEConvert.exe" $build -Force }
$clw = Join-Path $build 'MIETest.clw'
$cls = Join-Path $build 'MyImportExport.clw'
@"
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <ProjectGuid>{6A0C2E51-3D7B-4C55-9E0A-1B7D5E2F9A10}</ProjectGuid>
    <Configuration Condition=" '`$(Configuration)' == '' ">Debug</Configuration>
    <Platform Condition=" '`$(Platform)' == '' ">Win32</Platform>
    <OutputType>Exe</OutputType>
    <AssemblyName>MIETest</AssemblyName>
    <OutputName>MIETest</OutputName>
    <DefineConstants>_MIEDllMode_=&gt;0%3b_MIELinkMode_=&gt;1</DefineConstants>
    <Model>Dll</Model>
  </PropertyGroup>
  <PropertyGroup Condition=" '`$(Configuration)' == 'Debug' ">
    <DebugSymbols>True</DebugSymbols><DebugType>Full</DebugType><vid>full</vid>
    <check_stack>True</check_stack><check_index>True</check_index>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="$clw" />
  </ItemGroup>
  <ItemGroup>
    <FileDriver Include="TOPSPEED" />
    <FileDriver Include="DOS" />
    <FileDriver Include="ASCII" />
  </ItemGroup>
  <Import Project="`$(ClarionBinPath)\SoftVelocity.Build.Clarion.targets" />
</Project>
"@ | Set-Content -Encoding UTF8 (Join-Path $build 'MIETest.cwproj')
$env:ClarionBinPath = 'C:\clarion12\bin'
$msbuild = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
& $msbuild (Join-Path $build 'MIETest.cwproj') /nologo /v:minimal /p:Configuration=Debug /p:Platform=Win32
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED"; exit 1 }
if ($NoRun) { exit 0 }
Push-Location $build
$p = Start-Process -FilePath (Join-Path $build 'MIETest.exe') -Wait -PassThru
Pop-Location
Get-Content (Join-Path $build 'mietest.log')
Write-Host "Exit code: $($p.ExitCode)"
# JSON keeps numbers typed even with "Format with dictionary pictures" on
$pics = Get-Content (Join-Path $build 'out_pics.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($pics[0].Balance -isnot [double] -and $pics[0].Balance -isnot [decimal]) {
    Write-Host "PICTURES: Balance is not a JSON number: $($pics[0].Balance)"; exit 1
}
Write-Host "PICTURES: numbers stay numbers in JSON"
exit $p.ExitCode
