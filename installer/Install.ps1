[CmdletBinding()]
param([string]$GamePath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Get-PayloadFileHash {
    param([Parameter(Mandatory=$true)][string]$LiteralPath, [string]$Algorithm = 'SHA256')
    if ($Algorithm -ne 'SHA256') { throw 'Only SHA256 payload verification is supported.' }
    $stream = [IO.File]::OpenRead($LiteralPath)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [pscustomobject]@{ Hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') } }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Find-Game {
    $roots = [Collections.Generic.List[string]]::new()
    $registry = Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($registry -and $registry.PSObject.Properties['SteamPath']) { $roots.Add([string]$registry.SteamPath) }
    if (${env:ProgramFiles(x86)}) { $roots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam')) }
    foreach ($root in @($roots.ToArray())) {
        $libraries = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraries) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($libraries), '"path"\s+"([^"]+)"')) {
                $roots.Add($match.Groups[1].Value.Replace('\\','\'))
            }
        }
    }
    foreach ($root in ($roots | Select-Object -Unique)) {
        $candidate = Join-Path $root 'steamapps\common\GarrysMod'
        if (Test-Path -LiteralPath (Join-Path $candidate 'bin\win64\gmod.exe')) { return $candidate }
    }
    throw 'Garrys Mod x64 was not found. Run Install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\GarrysMod".'
}
if (!$GamePath) { $GamePath = Find-Game }
$game = (Resolve-Path -LiteralPath $GamePath).ProviderPath.TrimEnd('\')
if (!(Test-Path -LiteralPath (Join-Path $game 'bin\win64\gmod.exe') -PathType Leaf)) { throw 'This is not a Windows x64 Garrys Mod client folder.' }
if (Get-Process -Name gmod -ErrorAction SilentlyContinue) { throw 'Close Garrys Mod before installing the client mod.' }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.PackageVersion -ne 1 -or $manifest.DxvkVersion -ne '3.1.1') { throw 'Unsupported package manifest.' }
$payload = @(
    'bin\win64\d3d9.dll',
    'garrysmod\lua\bin\gmsv_gmodrp_vulkan_info_win64.dll',
    'garrysmod\lua\menu\gmodrp_client_tools.lua',
    'garrysmod\resource\OptionsSubVideoAdvancedDlg.res'
)
foreach ($relative in $payload) {
    $key = 'payload\' + $relative
    $entry = $manifest.Files.PSObject.Properties[$key]
    if (!$entry -or $entry.Value -notmatch '^[A-Fa-f0-9]{64}$') { throw "Missing integrity record: $key" }
    $source = Join-Path $PSScriptRoot $key
    if ((Get-PayloadFileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.Value) { throw "Package file failed integrity check: $key" }
}
$dxvkHash = 'C126316F7478EAFF1AD8087702EDA5930F2400187B9C8B3592219C34F6632780'
if ((Get-PayloadFileHash -LiteralPath (Join-Path $PSScriptRoot 'payload\bin\win64\d3d9.dll')).Hash -ne $dxvkHash) { throw 'Pinned official DXVK binary hash mismatch.' }
$wrapper = Join-Path $game 'bin\win64\d3d9.dll'
if ((Test-Path -LiteralPath $wrapper) -and (Get-PayloadFileHash -LiteralPath $wrapper).Hash -ne $dxvkHash) {
    throw 'An unknown D3D9 wrapper is installed (possibly the old D3D12 renderer). It was preserved. Restore/remove that renderer before installing this package.'
}
foreach ($relative in @('garrysmod\addons\gmodrp_native_renderer', 'garrysmod\lua\bin\gmcl_gmodrp_renderer_win64.dll', 'garrysmod\lua\bin\gmsv_gmodrp_renderer_win64.dll')) {
    if (Test-Path -LiteralPath (Join-Path $game $relative)) { throw "Old advanced renderer remains; restore it separately first: $relative" }
}
$loaderRelative = 'garrysmod\lua\menu\menu.lua'
$loaderPath = Join-Path $game $loaderRelative
$loader = [IO.File]::ReadAllText($loaderPath)
if ($loader -match 'gmodrp_renderer_options|gmodrp_ordered_scene') { throw 'The old advanced menu loader is still installed. Restore it before installing this package.' }
# Migrate only the exact previous information-helper include; keep unrelated Lua.
$loader = [regex]::Replace($loader, '(?m)^\s*include\(["'']gmodrp_vulkan_info\.lua["'']\)\s*\r?$', '')
$marker = '-- GmodRP Client Tools menu'
$include = "include('gmodrp_client_tools.lua')"
$existing = [regex]::Matches($loader, '(?m)^\s*include\(["'']gmodrp_client_tools\.lua["'']\)\s*\r?$')
if ($existing.Count -gt 1) { throw 'Duplicate client tools includes found; preserve and review menu.lua.' }
if ($existing.Count -eq 0) { $loader += "`r`n$marker`r`n$include`r`n" }
$backup = Join-Path $game ('GmodRP-Client-Mod-Backups\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup | Out-Null
$records = @()
# Copy every original before the first installation write.
foreach ($relative in @($payload) + @($loaderRelative)) {
    $target = Join-Path $game $relative
    $existed = Test-Path -LiteralPath $target -PathType Leaf
    $originalHash = $null
    if ($existed) {
        $destination = Join-Path $backup $relative
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $target -Destination $destination
        $originalHash = (Get-PayloadFileHash -LiteralPath $target).Hash
        if ((Get-PayloadFileHash -LiteralPath $destination).Hash -ne $originalHash) { throw "Backup verification failed: $relative" }
    }
    $records += [pscustomobject]@{ RelativePath=$relative; Existed=[bool]$existed; OriginalSHA256=$originalHash }
}
$receipt = [ordered]@{ Package='GmodRP Client Mod'; GameRoot=$game; CreatedAt=[DateTimeOffset]::Now.ToString('o'); State='BACKED_UP'; Files=$records }
$receiptPath = Join-Path $backup 'receipt.json'
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
Write-Host "Verified originals backed up to: $backup"
foreach ($relative in $payload) {
    $destination = Join-Path $game $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('payload\' + $relative)) -Destination $destination -Force
    $expected = $manifest.Files.PSObject.Properties['payload\' + $relative].Value
    if ((Get-PayloadFileHash -LiteralPath $destination).Hash -ne $expected) { throw "Installed file verification failed: $relative. Originals are in $backup" }
}
[IO.File]::WriteAllText($loaderPath, $loader, [Text.UTF8Encoding]::new($false))
$receipt.State = 'INSTALLED'
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
Write-Host 'Installed DXVK 3.1.1 and GmodRP client menu tools. Start Garrys Mod through Steam (x86-64 branch).'
Write-Host "Recovery receipt: $receiptPath"
