@echo off
rem PBZCustomBGM one-click installer - double-click me.
rem Wraps install.ps1 (extra switches like -GamePath are forwarded).
rem If SmartScreen/AV asks: this is a plain PowerShell wrapper, view it before allowing.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
