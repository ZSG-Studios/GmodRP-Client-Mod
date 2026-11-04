# v0.1.1 installation verification

Tested on Windows on November 4, 2026.

- Downloaded the published v0.1.0 executable and verified its GitHub SHA-256.
- Its real EXE path correctly rejected installation while Garry's Mod was running.
- Its real installation path exposed a missing `Get-FileHash` command in the child Windows PowerShell process. v0.1.1 replaces that dependency with .NET SHA-256.
- Ran the complete v0.1.1 candidate EXE against the installed game: observed the success dialog, acknowledged it, and verified exit code 0.
- All four installed payload files match the packaged hashes. The installer preserved originals and an installation receipt.
- Launched the installed client: Vulkan loaded and the supported multicore settings verified active.
- Captured the game-rendered graphics dialog: Multicore Rendering is enabled in Video > Advanced; loaded DXVK/Vulkan information is in the same dialog; the floating panel is absent.
- All 15 installer fixture checks passed under Windows PowerShell 5.1: clean installation, reinstall, original backups, one menu include, unknown-wrapper rejection and tampered-payload rejection.
- The 24 profile assertions passed for preservation, restoration, malformed inputs and unsupported legacy settings.

Repeat the installer checks with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/installer_integration.ps1 -PackageDirectory dist/GmodRP-Client-Mod
```

The live client uses an AMD RX 9070 XT. These results do not qualify NVIDIA hardware, every driver, or an unknown future GameUI build.
