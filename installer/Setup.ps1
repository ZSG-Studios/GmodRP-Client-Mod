[CmdletBinding()]
param([string]$GamePath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$destination=Join-Path ([IO.Path]::GetTempPath()) ('GmodRP-Client-Mod-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $destination | Out-Null
    Expand-Archive -LiteralPath (Join-Path $PSScriptRoot 'package.zip') -DestinationPath $destination
    $arguments=@{}
    if ($GamePath) { $arguments.GamePath=$GamePath }
    & (Join-Path $destination 'Install.ps1') @arguments
    [void][Windows.Forms.MessageBox]::Show('GmodRP Client Mod installed. Launch Garrys Mod through Steam using the Windows x86-64 branch. Originals were backed up inside the game folder.','GmodRP Client Mod',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
} catch {
    $message=$_.Exception.Message
    if (Test-Path -LiteralPath $destination) { $message | Set-Content -LiteralPath (Join-Path $destination 'setup-error.txt') -Encoding UTF8 }
    [void][Windows.Forms.MessageBox]::Show("Installation stopped: $message`r`n`r`nExtracted package and error details: $destination`r`nClose the game first. If Windows denies writing to Program Files, rerun with permission to write that game installation. For another Steam library, run Install.ps1 -GamePath from the extracted package.",'GmodRP Client Mod',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
