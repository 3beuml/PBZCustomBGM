# install.ps1 - PBZCustomBGM installer / uninstaller (PowerShell 5.1+)
#
# Install :  powershell -ExecutionPolicy Bypass -File install.ps1
# Custom  :  ... -File install.ps1 -GamePath "X:\SteamLibrary\steamapps\common\PBZ\platform\steam"
# Remove  :  ... -File install.ps1 -Uninstall
#
# This mod is add-files-only: it never overwrites or modifies game files.
# Requirement: UE4SS (KintaroModding PBZ specific build) must be installed first:
#   https://www.nexusmods.com/phantombladezero/mods/413  (dwmapi.dll + ue4ss into ...\PBZ\platform\steam)

param(
    [string]$GamePath = "",
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

function Find-GamePath {
    $roots = @()
    try {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        if ($steam) { $roots += $steam }
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            (Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"') | ForEach-Object {
                $roots += ($_.Matches[0].Groups[1].Value -replace '\\\\', '\')
            }
        }
    } catch { }
    foreach ($r in $roots) {
        $p = Join-Path $r 'steamapps\common\PBZ\platform\steam'
        if (Test-Path (Join-Path $p 'PBZ.exe')) { return $p }
    }
    return ""
}

$srcRoot = $PSScriptRoot
if (-not $srcRoot) { $srcRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

if ($Uninstall) {
    if (-not $GamePath) { $GamePath = Find-GamePath }
    if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'PBZ.exe'))) {
        Write-Host "Game not found. Pass it explicitly:  -GamePath `"...\PBZ\platform\steam`""
        exit 1
    }
    Write-Host "Uninstalling from: $GamePath"
    $mod = Join-Path $GamePath 'ue4ss\Mods\CustomBGM'
    $mus = Join-Path $GamePath 'PBZMusic'
    if (Test-Path $mod) { Remove-Item -Recurse -Force $mod; Write-Host "  removed ue4ss\Mods\CustomBGM" }
    if (Test-Path $mus) {
        $bak = "$mus.by-uninstaller"
        if (Test-Path $bak) { Remove-Item -Recurse -Force $bak }
        Rename-Item $mus $bak
        Write-Host "  PBZMusic kept as PBZMusic.by-uninstaller (your songs are there - delete manually)"
    }
    $modsTxt = Join-Path $GamePath 'ue4ss\Mods\mods.txt'
    if (Test-Path $modsTxt) {
        $lines = Get-Content $modsTxt | Where-Object { $_ -notmatch '^\s*CustomBGM\s*:' }
        Set-Content -Path $modsTxt -Value $lines -Encoding ASCII
        Write-Host "  removed CustomBGM line from mods.txt"
    }
    Write-Host "Done. UE4SS itself (dwmapi.dll / ue4ss) was kept - delete manually if no longer needed."
    exit 0
}

# ---- install ----
if (-not $GamePath) { $GamePath = Find-GamePath }
if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'PBZ.exe'))) {
    Write-Host "Could not find the game automatically."
    Write-Host "Pass it explicitly:  -GamePath `"X:\...\steamapps\common\PBZ\platform\steam`""
    exit 1
}
Write-Host "Game found: $GamePath"

if (-not (Test-Path (Join-Path $GamePath 'dwmapi.dll')) -or -not (Test-Path (Join-Path $GamePath 'ue4ss'))) {
    Write-Host ""
    Write-Host "ERROR: UE4SS (PBZ build) is missing."
    Write-Host "This mod requires UE4SS (KintaroModding PBZ specific build v3.0.1-1183)."
    Write-Host "Install it first, into this same folder:"
    Write-Host "  $GamePath"
    Write-Host "Download: https://www.nexusmods.com/phantombladezero/mods/413"
    exit 1
}

if (-not (Test-Path (Join-Path $srcRoot 'Mods\CustomBGM\Scripts\main.lua'))) {
    Write-Host "ERROR: package layout invalid (Mods\CustomBGM not found next to install.ps1)."
    exit 1
}

# copy mod
$destMod = Join-Path $GamePath 'ue4ss\Mods\CustomBGM'
Copy-Item -Recurse -Force -Path (Join-Path $srcRoot 'Mods\CustomBGM') -Destination (Join-Path $GamePath 'ue4ss\Mods')
Write-Host "  installed ue4ss\Mods\CustomBGM"

# ensure mods.txt entry
$modsTxt = Join-Path $GamePath 'ue4ss\Mods\mods.txt'
if (-not (Test-Path $modsTxt)) { Set-Content -Path $modsTxt -Value 'CustomBGM : 1' -Encoding ASCII }
else {
    $hasLine = (Get-Content $modsTxt) -match '^\s*CustomBGM\s*:'
    if (-not $hasLine) { Add-Content $modsTxt 'CustomBGM : 1' -Encoding ASCII }
    else {
        (Get-Content $modsTxt) -replace '^\s*CustomBGM\s*:\s*0\s*$', 'CustomBGM : 1' |
            Set-Content $modsTxt -Encoding ASCII
    }
}

# copy music folder; if PBZMusic already exists (reinstall), KEEP it renamed instead of
# destroying the user's songs and config
$destMus = Join-Path $GamePath 'PBZMusic'
if (Test-Path $destMus) {
    $prev = Join-Path $GamePath 'PBZMusic.previous'
    if (Test-Path $prev) { Remove-Item -Recurse -Force $prev }
    Rename-Item $destMus 'PBZMusic.previous'
    Write-Host "  previous PBZMusic kept as PBZMusic.previous (your songs/config are there - copy back any music you want)"
}
Copy-Item -Recurse -Force -Path (Join-Path $srcRoot 'PBZMusic') -Destination $destMus
Write-Host "  installed PBZMusic"

Write-Host ""
Write-Host "Install complete. Press F7 in game for the CustomBGM panel."
Write-Host "Put your songs into PBZMusic - the mod ships no audio (see README)."
[string]$launch = Read-Host "Launch the game now? [Y/n]"
if ($launch -notmatch '^[nN]') {
    try {
        Start-Process 'steam://rungameid/4115450'
        Write-Host "Steam launch requested (Phantom Blade Zero)."
    } catch {
        Write-Host "Could not auto-launch Steam; start the game from your library."
    }
}
