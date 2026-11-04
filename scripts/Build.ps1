[CmdletBinding()]
param([string]$BuildDirectory, [ValidateSet('Release','Debug')][string]$Configuration='Release', [switch]$SkipTests)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if (!$BuildDirectory) { $BuildDirectory=Join-Path $root 'build' }
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
$cmakeCommand=Get-Command cmake -ErrorAction SilentlyContinue
$cmake=if ($cmakeCommand) { $cmakeCommand.Source } else { $null }
if (!$cmake) {
    $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vs) { $candidate=Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'; if (Test-Path -LiteralPath $candidate) { $cmake=$candidate } }
    }
}
if (!$cmake) { throw 'Install CMake 3.21+ and Visual Studio C++ desktop build tools.' }
& $cmake -S $root -B $BuildDirectory -A x64 -DBUILD_TESTING=ON
if ($LASTEXITCODE) { throw 'CMake configure failed.' }
& $cmake --build $BuildDirectory --config $Configuration --parallel 2
if ($LASTEXITCODE) { throw 'Client module build failed.' }
if (!$SkipTests) {
    $ctest=Join-Path (Split-Path $cmake -Parent) 'ctest.exe'
    if (!(Test-Path -LiteralPath $ctest)) { $ctest='ctest' }
    & $ctest --test-dir $BuildDirectory -C $Configuration --output-on-failure
    if ($LASTEXITCODE) { throw 'Client module tests failed.' }
}
Write-Host "Built: $BuildDirectory\$Configuration\gmsv_gmodrp_vulkan_info_win64.dll"
