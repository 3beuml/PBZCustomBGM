@echo off
rem PBZCustomBGM uninstaller - double-click me.
rem Removes the mod only; UE4SS is kept; your PBZMusic songs are preserved as PBZMusic.by-uninstaller.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall %*
pause
