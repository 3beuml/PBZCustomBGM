# PBZCustomBGM

影之刃零（Phantom Blade Zero）的自定义 BGM mod。进战斗、残血、Boss 决战、死亡四个时机自动播放你自己的歌，游戏内 F7 面板调节。不带任何歌曲，也不弹 cmd 黑窗。

Nexus 发布页：https://www.nexusmods.com/phantombladezero/mods/1194

## 功能

- 四时机触发：进战斗（循环）/ 残血（默认 40%，可粘滞到战斗结束）/ Boss 血量 25% 进入决战 / 死亡（播一次）
- F7 面板：开关、试播、每类音量、低血阈值调节、打开音乐文件夹、重载配置
- 歌单池：player.ini 填文件夹路径，每次随机播放
- 独立音量 + 总音量，切曲淡入淡出
- 播放器自带看门狗和焦点防护，卡死自愈、不抢游戏焦点

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

## 构建

播放器：`player\make_wpf.bat`（.NET Framework 自带 csc 编译）
安装器：`csc -out:PBZCustomBGM-Setup.exe installer\Setup.cs`
Lua 不用编译，保存时不要带 BOM。

## 已知问题

- OGG/Opus 和加密格式（ncm/mflac/kgm）不支持，先转码
- 手柄偶尔失灵的问题在 0.6.5 已修（输入残留 + 焦点抢夺两个 bug）

## 许可

MIT。第三方组件：UE4SS（按其自身条款分发）、ModMenu.lua（MIT，mattdavida/ue4ss-ModMenu，带本地改动）。
