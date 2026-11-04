#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PackageDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$project = Split-Path $PSScriptRoot -Parent
$source = (Resolve-Path -LiteralPath $PackageDirectory).ProviderPath
$run = Join-Path $project ('.cache\installer-e2e-fixtures\winps-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$package = Join-Path $run 'package'
Copy-Item -LiteralPath $source -Destination $package -Recurse
$checks = [Collections.Generic.List[object]]::new()
function Test-Hash([string]$Path) {
    $file = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($file)).Replace('-', '') }
    finally { $sha.Dispose(); $file.Dispose() }
}
function Check([string]$Name, [bool]$Value) {
    $checks.Add([pscustomobject]@{ name=$Name; passed=$Value })
    if (!$Value) { throw "FAILED: $Name" }
}
function New-Fixture([string]$Name) {
    $path = Join-Path $run $Name
    foreach ($dir in @('bin\win64','garrysmod\lua\menu','garrysmod\resource')) {
        New-Item -ItemType Directory -Path (Join-Path $path $dir) -Force | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $path 'bin\win64\gmod.exe'), 'fixture placeholder')
    [IO.File]::WriteAllText((Join-Path $path 'garrysmod\lua\menu\menu.lua'), "-- original loader`r`ninclude('menu_main.lua')`r`n")
    [IO.File]::WriteAllText((Join-Path $path 'garrysmod\resource\OptionsSubVideoAdvancedDlg.res'), 'fixture original resource')
    return $path
}
function Snapshot([string]$Path) {
    return ((Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($Path.Length) + '=' + (Test-Hash $_.FullName)
    }) -join "`n")
}
function Save-Result([string]$Status, [string]$Failure = '') {
    [pscustomobject]@{
        status=$Status; error=$Failure; checks=$checks.ToArray(); fixtureRun=$run
        packageSource=$source; installerSHA256=(Test-Hash (Join-Path $package 'Install.ps1'))
        runtime=[pscustomobject]@{version=$PSVersionTable.PSVersion.ToString(); edition=$PSVersionTable.PSEdition; executable=(Get-Process -Id $PID).Path}
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'results.json') -Encoding UTF8
}
try {
    $clean = New-Fixture 'clean'
    $loader = Join-Path $clean 'garrysmod\lua\menu\menu.lua'
    $originalHash = Test-Hash $loader
    $resourceHash = Test-Hash (Join-Path $clean 'garrysmod\resource\OptionsSubVideoAdvancedDlg.res')
    & (Join-Path $package 'Install.ps1') -GamePath $clean
    $manifest = Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.Files.PSObject.Properties | Where-Object Name -like 'payload\*') {
        $relative = $entry.Name.Substring(8)
        Check ('clean payload ' + $relative) ((Test-Hash (Join-Path $clean $relative)) -eq $entry.Value)
    }
    Check 'clean include once' ([regex]::Matches([IO.File]::ReadAllText($loader), "include\('gmodrp_client_tools.lua'\)").Count -eq 1)
    $backups = @(Get-ChildItem -LiteralPath (Join-Path $clean 'GmodRP-Client-Mod-Backups') -Directory)
    Check 'clean backup count' ($backups.Count -eq 1)
    Check 'loader backup original hash' ((Test-Hash (Join-Path $backups[0].FullName 'garrysmod\lua\menu\menu.lua')) -eq $originalHash)
    Check 'resource backup original hash' ((Test-Hash (Join-Path $backups[0].FullName 'garrysmod\resource\OptionsSubVideoAdvancedDlg.res')) -eq $resourceHash)
    Check 'installed receipt' ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'receipt.json') -Raw | ConvertFrom-Json).State -eq 'INSTALLED')
    $beforeLoader = Test-Hash $loader
    & (Join-Path $package 'Install.ps1') -GamePath $clean
    Check 'reinstall preserves include and loader' ((Test-Hash $loader) -eq $beforeLoader)
    Check 'reinstall creates second backup' (@(Get-ChildItem -LiteralPath (Join-Path $clean 'GmodRP-Client-Mod-Backups') -Directory).Count -eq 2)

    $unknown = New-Fixture 'unknown-wrapper'
    [IO.File]::WriteAllText((Join-Path $unknown 'bin\win64\d3d9.dll'), 'unrecognized fixture wrapper')
    $before = Snapshot $unknown
    $rejected = $false
    try { & (Join-Path $package 'Install.ps1') -GamePath $unknown }
    catch { $rejected = $_.Exception.Message -like '*unknown D3D9 wrapper*' }
    Check 'unknown wrapper rejected' $rejected
    Check 'unknown wrapper no mutations' ((Snapshot $unknown) -eq $before)

    $tampered = New-Fixture 'tampered-payload'
    $before = Snapshot $tampered
    [IO.File]::AppendAllText((Join-Path $package 'payload\garrysmod\lua\menu\gmodrp_client_tools.lua'), 'tampered fixture')
    $rejected = $false
    try { & (Join-Path $package 'Install.ps1') -GamePath $tampered }
    catch { $rejected = $_.Exception.Message -like '*integrity check*' }
    Check 'tampered payload rejected' $rejected
    Check 'tampered payload no mutations' ((Snapshot $tampered) -eq $before)
    Save-Result 'PASS'
    Write-Output "PASS: $($checks.Count) checks; fixtures $run"
} catch {
    Save-Result 'FAIL' $_.Exception.Message
    throw
}
