# GmodRP Client Mod

Windows x64 Garry's Mod client package with pinned DXVK 3.1.1, loaded-renderer information and the native **Video > Advanced > Multicore Rendering** selection. The profile uses the engine's existing convars. There is no separate floating graphics window, temporal upscaler or replacement game engine.

Use Garry's Mod's Windows `x86-64` branch and a Vulkan-capable GPU/driver. Renderer status checks the loaded D3D9 DLL hash and Vulkan loader; installing a DLL alone is not proof of a successfully initialized Vulkan device. FPS improvement is not guaranteed.

## Build and test

Install Visual Studio C++ desktop build tools and CMake 3.21 or later. The project is self-contained: maintained Garry's Mod module headers and MinHook sources/licenses are included. No old renderer build, workspace path or separately built MinHook library is required.

```powershell
.\scripts\Build.ps1
```

This configures Windows x64, builds Release with the static MSVC runtime (`/MT`), and runs the profile persistence tests. The module is `build\Release\gmsv_gmodrp_vulkan_info_win64.dll`. Debug and another build directory are supported through `-Configuration Debug` and `-BuildDirectory`.

The equivalent commands for Windows CI are:

```powershell
cmake -S . -B build -A x64 -DBUILD_TESTING=ON
cmake --build build --config Release --parallel 2
ctest --test-dir build -C Release --output-on-failure
.\scripts\Package.ps1 -SkipBuild
```

The profile test verifies the config-file behavior; it does not qualify an in-game UI hook or prove GPU performance. Test the native dropdown against the supported GameUI build before distributing a release. Unsupported native menu builds must preserve the stock behavior.

## Package

```powershell
.\scripts\Package.ps1
```

Outputs under `dist`:

- `GmodRP-Client-Mod`: reviewable extracted package with integrity manifest.
- `GmodRP-Client-Mod.zip`: portable installer package.
- `GmodRP-Client-Mod-Setup.exe`: single executable installer.

The script reuses `.cache\dxvk-3.1.1.tar.gz` or downloads that exact official release, verifies its pinned SHA-256, and extracts/verifies only its x64 D3D9 DLL. No latest-version lookup changes the package implicitly. `third_party\dxvk\LICENSE` and the other dependency licenses accompany the binary package. Existing output is preserved; choose `-OutputDirectory` for another build. Use `-SkipExe` where executable packaging is unnecessary.

The executable uses Windows IExpress when available. If IExpress cannot produce the package, the build uses the Windows .NET Framework C# compiler to create a small GUI bootstrap with the same ZIP and Setup script embedded. This adds no runtime download. The bootstrap and Setup retain their temporary extracted files for diagnosis and invoke the same reviewable PowerShell installer. Neither packaging method launches the installer during a build. Release executables are unsigned unless the distributor signs them separately.

## Install and recover

Close the game and run the executable, or extract the ZIP and run `Install.cmd`. The installer detects Steam libraries; pass `-GamePath` to `Install.ps1` for a custom location. It requires permission to write the game installation. It refuses an unknown `d3d9.dll`, a running game, or remaining advanced-renderer files.

Every overwritten original is copied and hash-verified in `GmodRP-Client-Mod-Backups` inside the game directory before installation writes begin. Its `receipt.json` records original files and whether they existed. To restore, close the game, copy backed-up originals to their relative paths, and move newly introduced files to the Recycle Bin. Keep the backup. Steam updates may overwrite menu files and require a reviewed reinstall.

The package contains no Counter-Strike: Source assets, server configuration, server password, previous advanced-renderer binaries or FSR/DLSS integrations.
