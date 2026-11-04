GmodRP Client Mod
================

Run GmodRP-Client-Mod-Setup.exe for the single-file installer, or extract the
ZIP and run Install.cmd. Keep the game closed during installation. The setup
retains extracted temporary files for diagnostics; it downloads nothing.
The mod uses the native Video > Advanced > Multicore Rendering dropdown.
There is no separate floating graphics/settings window.

Contents: official DXVK 3.1.1 x64 D3D9-to-Vulkan runtime, the small GmodRP
renderer information / multicore profile helper, its main-menu controls and
custom advanced-video layout. No FSR, DLSS, advanced renderer, server files,
server passwords, or Counter-Strike: Source assets are included.

Close Garry's Mod, extract the entire package, and double-click Install.cmd.
The installer locates Steam's Garry's Mod installation. To choose another:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\GarrysMod"
Use Garry's Mod's Windows x86-64 branch. Launch normally through Steam.
If the game is under Program Files and access is denied, run the installer
from a PowerShell window with permission to write that game installation.

The main-menu tools show loaded renderer status and offer the normal engine
multicore profile. A configured Vulkan label alone does not prove Vulkan is
running: check the loaded runtime status. Hardware/driver support is required;
NVIDIA GeForce branding alone is insufficient to guarantee compatibility.
Multicore uses existing engine convars; it does not replace the engine renderer.
There is no promise of an FPS increase or new temporal upscaling features.

Every existing overwritten file is copied first into a timestamped
GmodRP-Client-Mod-Backups directory inside the game folder, with a receipt.
An existing unknown d3d9.dll is refused. The installer does not remove an older
advanced-renderer installation; restore that separately before installing.
The installer verifies package hashes, but these are an integrity check rather
than an independent publisher signature. Keep the package from a trusted source.

To restore: close the game, read the backup receipt.json, and copy each backed-up
file to its original relative path. For files whose Existed field is false,
move their installed copies to the Recycle Bin. Retain the backups. Steam game
updates may replace the menu loader or video layout; reinstall after reviewing
the update. No automatic updater or game restart is installed.

DXVK is distributed under the license in DXVK-LICENSE.txt.
Release: https://github.com/doitsujin/dxvk/releases/tag/v3.1.1
Source: https://github.com/doitsujin/dxvk/tree/v3.1.1
