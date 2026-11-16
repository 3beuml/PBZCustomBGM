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
