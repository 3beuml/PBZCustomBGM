# PBZCustomBGM

影之刃零（Phantom Blade Zero）的自定义 BGM mod。进战斗、残血、Boss 决战、死亡四个时机自动播放你自己的歌，游戏内 F7 面板调节。不带任何歌曲，也不弹 cmd 黑窗。

Nexus 发布页：https://www.nexusmods.com/phantombladezero/mods/1194

## 功能

- 四时机触发：进战斗（循环）/ 残血（默认 40%，可粘滞到战斗结束）/ Boss 血量 25% 进入决战 / 死亡（播一次）
- F7 面板：开关、试播、每类音量、低血阈值调节、打开音乐文件夹、重载配置
- 歌单池：player.ini 填文件夹路径，每次随机播放
- 独立音量 + 总音量，切曲淡入淡出
- 播放器自带看门狗和焦点防护，卡死自愈、不抢游戏焦点

- 🌐 **F7 面板中英双语**：「语言 Language」按钮即时切换中文/English，点击即写回 config.ini（重启保留）

## 安装

先装 [UE4SS for Phantom Blade Zero](https://www.nexusmods.com/phantombladezero/mods/5)。

1. 把 `Mods\` 和 `PBZMusic\` 两个文件夹放进 `...\steamapps\common\PBZ\platform\steam\`
2. `ue4ss\Mods\mods.txt` 加一行 `CustomBGM : 1`
3. 开游戏按 F7

## 换歌

编辑 `PBZMusic\player.ini`：

```ini
[files]
low   = C:\Music\低血曲.mp3
death = C:\Music\死亡曲.flac
boss  =                          ; 留空 = 沿用低血曲
```

支持 mp3 / wav / flac / m4a / aac / wma（ogg 和加密格式不支持）。改完不用重启游戏，F7 点"重载音乐配置"或等 5 秒自动生效。

## 游戏内使用（F7 面板）

装好并**完全重启游戏**后按 F7 打开「CustomBGM 音乐箱」：

- **状态行**：当前状态（探索/战斗/低血/决战/死亡）、播放器运行状态、Boss 血量实时
- **四曲开关**（战斗/低血/决战/死亡）：即时生效，重启后恢复 config.ini 设定
- **试播**：每曲一键试听，快速检查配曲
- **音量 ±10 与全局音量**：点「保存音量设置」才持久化，否则重启丢失
- **低血阈值 ±5**：点「保存阈值」写回 config.ini
- **打开音乐文件夹 / 重载音乐配置**：改 player.ini 后立即生效（或等 5 秒自动重读）

最快换歌：把自己的歌改名覆盖 `PBZMusic\` 里的 `low / death / combat`（如直接叫 `low.mp3`），不用动任何配置。

## 排障 FAQ

**Q: 按 F7 没反应？** ① `mods.txt` 没加 `CustomBGM : 1`；② 没完全重启游戏（无热重载）；③ `UE4SS.log` 里出现 `unexpected symbol near '<\239>'` = Lua 文件带 BOM，重新保存为 UTF-8 无 BOM；④ UE4SS 不是 PBZ 专用版。

**Q: 面板显示"播放器：未运行"？** 多半是杀软把 `PBZPlayer.exe` 隔离了——去隔离区恢复并加入信任（SHA256 见下文）；若几秒后自动恢复则是看门狗自愈，不用管。

**Q: 改 config.ini 不生效？** mod 配置必须**完全重启游戏**才生效；只有 player.ini（音乐/音量）支持热重载。

**Q: 没声音？** 看 `PBZMusic\player.log`：`media failed` = 格式/文件问题（见格式说明）；`heartbeat lost` = 游戏侧心跳断。支持 mp3/wav/flac/m4a/aac/wma；ogg 与加密下载（ncm/mflac/kgm）不支持。

## 构建

播放器：`player\make_wpf.bat`（.NET Framework 自带 csc 编译）
安装器：`csc -out:PBZCustomBGM-Setup.exe installer\Setup.cs`
Lua 不用编译，保存时不要带 BOM。

## 已知问题

- OGG/Opus 和加密格式（ncm/mflac/kgm）不支持，先转码
- 手柄偶尔失灵的问题在 0.6.5 已修（输入残留 + 焦点抢夺两个 bug）

## English quick start

1. **Prerequisite** — install [UE4SS for PBZ](https://www.nexusmods.com/phantombladezero/mods/413).
2. **Install** — download the zip from [Releases](https://github.com/3beuml/PBZCustomBGM/releases), drag `Mods\` and `PBZMusic\` into `...\steamapps\common\PBZ\platform\steam\`, add one line `CustomBGM : 1` to `ue4ss\Mods\mods.txt`, **fully restart the game** (no hot reload).
3. **Use** — press **F7** in game (click the **语言 / Language** button to switch 中文/English anytime): per-track toggles, preview, per-track volume (press **Save** to persist), low-HP threshold, open music folder, reload config. Three royalty-free demo tracks are included (Kevin MacLeod / incompetech.com, CC-BY 4.0) — drop songs into `PBZMusic\` to replace them (mp3/wav/flac/m4a/aac/wma; ogg & DRM-wrapped downloads unsupported) or set paths/folders in `PBZMusic\player.ini`. Triggers: combat loop (silent by default), low HP 40% (sticky until fight ends), boss duel ≤25%, death once.
4. **Troubles** — no F7 panel: check the `CustomBGM : 1` line and fully restart; "player: not running": your AV likely quarantined `PBZPlayer.exe` (see below). Logs: `ue4ss\UE4SS.log` + `PBZMusic\player.log`.

## 许可

MIT。第三方组件：UE4SS（按其自身条款分发）、ModMenu.lua（MIT，mattdavida/ue4ss-ModMenu，带本地改动）。

## 下载

- 正式发布页：https://www.nexusmods.com/phantombladezero/mods/1194
- 若 Nexus 主文件显示"已被隔离/审核中"，可从本仓库 [Releases](https://github.com/3beuml/PBZCustomBGM/releases) 直接下载同版 zip。

## 杀毒软件误报说明

`PBZPlayer.exe` 是本 mod 的无窗口播放器本体，C# 源码在 `player/PBZPlayerWPF.cs`，用 `player/make_wpf.bat`（.NET Framework 自带 csc）即可编译。个人项目没有代码签名证书，个别杀毒软件或 SmartScreen 可能误报——遇到拦截选"保留/信任"即可。

如需核对，SHA256 如下：

```
PBZPlayer.exe            fb43a39259adf1e295a34aa9fe9e6cac4d2d8c4ef3b3abc34047e7fe0a391142
PBZCustomBGM-Setup.exe   ee843340a91dc89acae4888f1ca7dda890e6dd5b17e7268caa6a81ad9085d445
```

本 mod 全程不调用 cmd / 脚本宿主，不联网，不捆绑任何歌曲。

**内置演示曲**（可自由商用，换成自己的歌后可删除）：
Guzheng City / Shenyang / Clenched Teeth — Kevin MacLeod（incompetech.com），
Creative Commons BY 4.0 授权随包分发。本 mod 不含、不分发任何版权音乐。

**免版权曲源推荐**：Pixabay Music（免费商用无署名）、YouTube 音频库、incompetech.com（CC-BY）、
OpenGameArt（多为 CC0）。认准 CC0 / CC-BY 标记即可入包。
