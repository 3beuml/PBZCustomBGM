**English** | [中文](README.zh-CN.md)

# PBZCustomBGM

**Custom BGM triggers for Phantom Blade Zero (UE4SS).** Your music plays automatically when combat starts, when your HP drops low, when a boss duel begins, and on death. The in-game F7 panel handles preview, volume, thresholds and a 中文/English language switch.

No bundled music · no cmd windows · no network calls · uninstall = delete two folders

[![Nexus Mods](https://img.shields.io/badge/Nexus-phantombladezero-orange)](https://www.nexusmods.com/phantombladezero/mods/1194) [![Release](https://img.shields.io/github/v/tag/3beuml/PBZCustomBGM?label=release)](https://github.com/3beuml/PBZCustomBGM/releases) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

---

## Features

- **Four triggers** — combat (loop, off by default), low HP at 40% (sticky until the fight ends), boss duel at ≤25% boss HP (latched until the boss dies), death (plays once)
- **F7 panel** — live status / HP / boss HP row, per-track preview, per-track toggles, volume ±10 with save, low-HP threshold ±5 with save, open music folder, reload config, language switch
- **Playlist pools** — point `player.ini` at a folder and the player picks a random track each trigger
- **Bilingual panel** — the Language button switches 中文 / English instantly and saves automatically
- **Built-in demo tracks** — three royalty-free tracks (Kevin MacLeod, CC-BY 4.0) so it works out of the box; replace them with your own files anytime
- **Safety design** — the game-side Lua sentinel is strictly read-only, audio runs in a separate windowless process, all deployment is add-files-only, and the player self-heals via a watchdog. No `cmd`/`os.execute` anywhere.

## Installation

Prerequisite: [UE4SS for Phantom Blade Zero](https://www.nexusmods.com/phantombladezero/mods/413) — you should see `dwmapi.dll` and a `ue4ss\` folder under `...\steamapps\common\PBZ\platform\steam\`.

**Manual (recommended)**

1. Drag the `Mods\` and `PBZMusic\` folders from the zip into `...\steamapps\common\PBZ\platform\steam\`
2. Open `ue4ss\Mods\mods.txt` in Notepad and add one line: `CustomBGM : 1`
3. Fully restart the game (no hot reload), then press **F7** — "Player: running" means it works

**One-click (optional)** — removed. Manual install is a 3-step drag-and-drop and needs no scripts or installer. Uninstalling = delete the two folders plus that one line in `mods.txt`.

## Your music

Three royalty-free demo tracks ship in `PBZMusic\` (see [Demo music](#demo-music--licensing)). To use your own:

1. **Fastest** — rename your song to `low.mp3` (or `death.mp3` / `combat.mp3`) and drop it into `PBZMusic\`
2. **Paths** — edit `PBZMusic\player.ini`:

   ```ini
   [files]
   low   = D:\Music\my_battle_song.flac
   death = D:\Music\farewell.mp3
   ; boss =                    ; empty = reuse the low-HP track
   ```

3. **Playlist pool** — point an entry at a folder: `low = D:\Music\hype_list\` → random pick each trigger

**Formats**: MP3 / WAV / FLAC / M4A / AAC / WMA all verified on Windows 11. OGG/Opus and DRM-wrapped downloads (NCM / MFLAC / KGM) are not supported — convert first.

**Hot reload**: after editing `player.ini`, press "Reload music config" in the F7 panel or wait 5 seconds. `config.ini` (mod settings) needs a full game restart.

## In-game panel (F7)

| Row / button | What it does |
|---|---|
| Status / HP / Player / Boss | live state (explore / combat / low / duel / death), player process, boss HP while engaged |
| 4 track toggles | apply instantly; revert to `config.ini` after restart |
| Preview ×4 | quick check of your tracks; stops automatically |
| Volume ±10 / Save | master volume; persists only after **Save volume** |
| Threshold ±5 / Save | low-HP trigger; persists after **Save threshold** |
| Open music folder | opens Explorer behind the game window |
| Language | switches 中文 / English instantly, saved automatically |

## Troubleshooting

- **No F7 panel** — check the `CustomBGM : 1` line in `mods.txt`, fully restart the game, and check `ue4ss\UE4SS.log` for a `CustomBGM` load line (a `unexpected symbol near '<\239>'` error means a Lua file was saved with a BOM).
- **"Player: not running"** — the antivirus probably quarantined `PBZMusic\PBZPlayer.exe`: restore and trust it, then verify the SHA256 published below. A brief flicker that recovers on its own is the built-in watchdog, safe to ignore.
- **No sound** — read `PBZMusic\player.log`: `media failed` points to a file/format issue; `heartbeat lost` means the game side went away. Logs: `ue4ss\UE4SS.log` + `PBZMusic\player.log`.
- **Controller input stuck** — fixed in v0.6.5; if it ever returns, grab both logs and open an issue.
- **Game updates** — verified against build 26266538 / CL 301524 / UE 5.7.4; major game updates may need an adapter fix.

**SHA256** (verify if your antivirus flags the player):

```
PBZPlayer.exe            fb43a39259adf1e295a34aa9fe9e6cac4d2d8c4ef3b3abc34047e7fe0a391142
```

## Demo music & licensing

Built-in demo tracks — **Guzheng City** (low HP), **Shenyang** (death), **Clenched Teeth** (combat) — by Kevin MacLeod ([incompetech.com](https://incompetech.com)), licensed **CC BY 4.0**, attribution included in the package. Free for commercial use; delete them after adding your own music. No copyrighted music ships with this mod.

More royalty-free sources: [Pixabay Music](https://pixabay.com/music/) (no attribution needed), the YouTube Audio Library, [incompetech](https://incompetech.com) (CC-BY), [OpenGameArt](https://opengameart.org) (mostly CC0).

## Build

- Player: `player\make_wpf.bat` — compiles `PBZPlayerWPF.cs` with the .NET Framework built-in `csc.exe`, no external dependencies
- Lua needs no build; save `.lua` files **without a UTF-8 BOM** (UE4SS refuses to load BOM files)

## License

MIT — see [LICENSE](LICENSE). Vendored `ModMenu.lua` is MIT (mattdavida/ue4ss-ModMenu, local changes). UE4SS itself is distributed by its own project under its own terms and is not bundled here. Demo tracks: Kevin MacLeod, CC BY 4.0.

Nexus page: https://www.nexusmods.com/phantombladezero/mods/1194
