@echo off
rem 编译 PBZPlayer.exe（WPF MediaElement 版，v0.5）
rem .NET Framework 4 自带编译器 + GAC 定位 PresentationCore 等程序集
set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe

set WB=
set PC=
set PF=
set SX=
for /d %%D in ("%WINDIR%\Microsoft.NET\assembly\GAC_MSIL\WindowsBase\v4.0_*") do if not defined WB set WB=%%D\WindowsBase.dll
for /d %%D in ("%WINDIR%\Microsoft.NET\assembly\GAC_64\PresentationCore\v4.0_*") do if not defined PC set PC=%%D\PresentationCore.dll
for /d %%D in ("%WINDIR%\Microsoft.NET\assembly\GAC_MSIL\PresentationFramework\v4.0_*") do if not defined PF set PF=%%D\PresentationFramework.dll
for /d %%D in ("%WINDIR%\Microsoft.NET\assembly\GAC_MSIL\System.Xaml\v4.0_*") do if not defined SX set SX=%%D\System.Xaml.dll

"%CSC%" -nologo -target:winexe -r:System.dll -r:System.Core.dll -r:"%WB%" -r:"%PC%" -r:"%PF%" -r:"%SX%" -out:PBZPlayer.exe PBZPlayerWPF.cs
echo Done. PBZPlayer.exe (MediaElement/MP3)
