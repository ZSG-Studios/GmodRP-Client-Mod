[CmdletBinding()]
param([string]$BuildDirectory, [ValidateSet('Release','Debug')][string]$Configuration='Release', [string]$OutputDirectory, [switch]$SkipBuild, [switch]$SkipExe)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if (!$BuildDirectory) { $BuildDirectory=Join-Path $root 'build' }
if (!$OutputDirectory) { $OutputDirectory=Join-Path $root 'dist' }
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if (!$SkipBuild) { & (Join-Path $PSScriptRoot 'Build.ps1') -BuildDirectory $BuildDirectory -Configuration $Configuration }
$archiveHash='40565B4A724AADC4433FA4E010B4B23916D9B1F1BAEEE64E17186DB94F54E608'
$dxvkHash='C126316F7478EAFF1AD8087702EDA5930F2400187B9C8B3592219C34F6632780'
$cache=Join-Path $root '.cache'
$archive=Join-Path $cache 'dxvk-3.1.1.tar.gz'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
if (!(Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/doitsujin/dxvk/releases/download/v3.1.1/dxvk-3.1.1.tar.gz' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive).Hash -ne $archiveHash) { throw 'Cached DXVK release archive hash mismatch; preserved for review.' }
$dxvk=Join-Path $cache 'dxvk-3.1.1\x64\d3d9.dll'
if (!(Test-Path -LiteralPath $dxvk)) {
    & tar -xzf $archive -C $cache 'dxvk-3.1.1/x64/d3d9.dll'
    if ($LASTEXITCODE) { throw 'DXVK extraction failed (Windows tar is required).' }
}
if ((Get-FileHash -LiteralPath $dxvk).Hash -ne $dxvkHash) { throw 'Extracted DXVK binary hash mismatch.' }
$package=Join-Path $OutputDirectory 'GmodRP-Client-Mod'
$zip=Join-Path $OutputDirectory 'GmodRP-Client-Mod.zip'
$exe=Join-Path $OutputDirectory 'GmodRP-Client-Mod-Setup.exe'
foreach ($path in @($package,$zip,$exe)) { if (Test-Path -LiteralPath $path) { throw "Output already exists; preserve it or choose -OutputDirectory: $path" } }
$inputs=[ordered]@{
    'payload\bin\win64\d3d9.dll'=$dxvk
    'payload\garrysmod\lua\bin\gmsv_gmodrp_vulkan_info_win64.dll'=(Join-Path $BuildDirectory "$Configuration\gmsv_gmodrp_vulkan_info_win64.dll")
    'payload\garrysmod\lua\menu\gmodrp_client_tools.lua'=(Join-Path $root 'menu\renderer_info.lua')
    'payload\garrysmod\resource\OptionsSubVideoAdvancedDlg.res'=(Join-Path $root 'menu\OptionsSubVideoAdvancedDlg.res')
    'DXVK-LICENSE.txt'=(Join-Path $root 'third_party\dxvk\LICENSE')
    'MinHook-LICENSE.txt'=(Join-Path $root 'third_party\minhook\LICENSE.txt')
    'GarrysMod-Headers-LICENSE.txt'=(Join-Path $root 'third_party\garrysmod_common\LICENSE.txt')
    'README.txt'=(Join-Path $root 'installer\README.txt')
    'Install.ps1'=(Join-Path $root 'installer\Install.ps1')
    'Install.cmd'=(Join-Path $root 'installer\Install.cmd')
}
foreach ($input in $inputs.Values) { if (!(Test-Path -LiteralPath $input -PathType Leaf)) { throw "Missing package input: $input" } }
New-Item -ItemType Directory -Path $package -Force | Out-Null
$hashes=[ordered]@{}
foreach ($relative in $inputs.Keys) {
    $destination=Join-Path $package $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $inputs[$relative] -Destination $destination
    $hashes[$relative]=(Get-FileHash -LiteralPath $destination).Hash
}
[ordered]@{Name='GmodRP Client Mod';PackageVersion=1;DxvkVersion='3.1.1';DxvkRelease='https://github.com/doitsujin/dxvk/releases/tag/v3.1.1';CreatedAt=[DateTimeOffset]::Now.ToString('o');Files=$hashes} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $package 'manifest.json') -Encoding UTF8
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip -CompressionLevel Optimal
if (!$SkipExe) {
    $iexpress=Join-Path $env:SystemRoot 'System32\iexpress.exe'
    # Flat IExpress inputs; Setup expands the inner package to a retained folder.
    $stage=Join-Path $cache ('iexpress-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item -LiteralPath $zip -Destination (Join-Path $stage 'package.zip')
    Copy-Item -LiteralPath (Join-Path $root 'installer\Setup.ps1') -Destination (Join-Path $stage 'Setup.ps1')
    $sed=@"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$exe
FriendlyName=GmodRP Client Mod
AppLaunched=powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File Setup.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="package.zip"
FILE1="Setup.ps1"
[SourceFiles]
SourceFiles0=$stage\
[SourceFiles0]
%FILE0%=
%FILE1%=
"@
    $sedPath=Join-Path $stage 'package.sed'
    [IO.File]::WriteAllText($sedPath,(($sed -replace "`r?`n","`r`n")+"`r`n"),[Text.Encoding]::ASCII)
    $built=$false
    if (Test-Path -LiteralPath $iexpress) {
        $process=Start-Process -FilePath $iexpress -ArgumentList @('/N','/Q',('"'+$sedPath+'"')) -WindowStyle Hidden -Wait -PassThru
        $built=$process.ExitCode -eq 0 -and (Test-Path -LiteralPath $exe)
    }
    if (!$built) {
        Write-Host 'IExpress did not produce an installer; building the embedded Windows .NET bootstrap.'
        $csc=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (!(Test-Path -LiteralPath $csc)) { throw 'Neither IExpress nor the Windows .NET Framework C# compiler is available. ZIP remains ready.' }
        $bootstrap=@'
using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Windows.Forms;
internal static class Bootstrap {
    private static void Extract(string name,string path) {
        using(var source=Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
            if(source==null)throw new InvalidOperationException("Missing embedded installer resource: "+name);
            using(var target=File.Create(path))source.CopyTo(target);
        }
    }
    [STAThread] private static int Main() {
        string folder=Path.Combine(Path.GetTempPath(),"GmodRP-Client-Mod-Launcher-"+Guid.NewGuid().ToString("N"));
        try {
            Directory.CreateDirectory(folder);
            Extract("PackageZip",Path.Combine(folder,"package.zip"));
            string setup=Path.Combine(folder,"Setup.ps1");Extract("SetupScript",setup);
            string shell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe");
            var start=new ProcessStartInfo(shell,"-NoProfile -STA -ExecutionPolicy Bypass -File \""+setup+"\"");
            start.UseShellExecute=false;start.CreateNoWindow=true;start.WorkingDirectory=folder;
            using(var child=Process.Start(start)){child.WaitForExit();return child.ExitCode;}
        } catch(Exception error) {
            MessageBox.Show("Installation stopped: "+error.Message+"\r\nRetained installer files: "+folder,"GmodRP Client Mod",MessageBoxButtons.OK,MessageBoxIcon.Error);
            return 1;
        }
    }
}
'@
        $sourcePath=Join-Path $stage 'Bootstrap.cs'
        [IO.File]::WriteAllText($sourcePath,$bootstrap,[Text.Encoding]::UTF8)
        & $csc /nologo /optimize+ /target:winexe /platform:x64 /reference:System.Windows.Forms.dll ("/out:"+$exe) ("/resource:"+(Join-Path $stage 'package.zip')+',PackageZip') ("/resource:"+(Join-Path $stage 'Setup.ps1')+',SetupScript') $sourcePath
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $exe)) { throw 'Embedded bootstrap build failed; ZIP remains available.' }
    }
}
Write-Host "Ready: $package"
Write-Host "ZIP: $zip"
if (!$SkipExe) { Write-Host "Single executable installer: $exe" }
