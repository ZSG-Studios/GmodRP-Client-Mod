@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
if errorlevel 1 (
  echo Installation failed. Read the error above. Existing files were preserved in the reported backup if installation started.
  pause
  exit /b 1
)
pause
