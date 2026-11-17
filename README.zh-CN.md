[English](README.md) | **中文**

# PBZCustomBGM — 《影之刃零》自定义 BGM

**进战斗 / 低血 / Boss 决战 / 死亡**四个时机自动播放你自己的歌，F7 面板调节（音量、阈值、试播、开关），面板支持中文/English 一键切换。不捆绑歌曲、无 cmd 黑窗、不联网、不改游戏文件。

Nexus 发布页：https://www.nexusmods.com/phantombladezero/mods/1194 · 下载见 [Releases](https://github.com/3beuml/PBZCustomBGM/releases)

---

## 功能

- **四时机触发**：进战斗循环（默认关）/ 低血 40%（粘滞到战斗结束）/ Boss 血量 ≤25% 决战（锁存到 Boss 死/脱战）/ 死亡播一次
- **F7 面板**：状态/生命/Boss 血量实时行、每曲试播、四曲开关、音量 ±10 可保存、低血阈值 ±5 可保存、打开音乐文件夹、重载配置、语言切换
- **歌单池**：player.ini 填文件夹路径 = 每次触发随机抽曲
- **面板双语**：「语言 Language」按钮即时切换中文/English，自动保存
- **内置演示曲**：三首免版权曲（Kevin MacLeod，CC-BY 4.0），开箱即有效果，随时换自己的歌
- **安全设计**：游戏侧 Lua 严格只读；音频走独立无窗口进程；部署全为新增文件，卸载即删；播放器看门狗自愈。全程无 `cmd`/`os.execute`

## 安装

前置：[UE4SS for Phantom Blade Zero](https://www.nexusmods.com/phantombladezero/mods/413)（装好后游戏目录 `platform\steam\` 下应有 `dwmapi.dll` 和 `ue4ss\`）。

**手动安装（推荐）**

1. 把 zip 里的 `Mods\` 和 `PBZMusic\` 两个文件夹拖进 `...\steamapps\common\PBZ\platform\steam\`
2. 记事本打开 `ue4ss\Mods\mods.txt`，加一行：`CustomBGM : 1`
3. **完全重启游戏**（无热重载），按 **F7** —— 面板显示"播放器：运行中"即成功

**一键安装（可选）**：已移除——手动安装只需 3 步拖拽，无需脚本或安装器。卸载：删除两个文件夹 + 删掉 mods.txt 那一行，你的歌自己备份。

## 换歌

`PBZMusic\` 内置三首演示曲（见文末许可），换成自己的歌：

1. **最快**：把自己的歌改名覆盖 `low.mp3`（或 `death.mp3` / `combat.mp3`），丢进 `PBZMusic\`
2. **路径**：编辑 `PBZMusic\player.ini`：

   ```ini
   [files]
   low   = D:\Music\我的燃曲.flac
   death = D:\Music\挽歌.mp3
   ; boss =                    ; 留空 = 沿用低血曲
   ```

3. **歌单池**：条目指向文件夹：`low = D:\Music\歌单\` → 每次触发随机抽

**格式**：mp3 / wav / flac / m4a / aac / wma 全部实测可用；ogg / opus 与加密下载（ncm / mflac / kgm）不支持，请先转码。

**热重载**：改完 `player.ini` 点 F7「重载音乐配置」或等 5 秒自动生效；`config.ini`（mod 设置）需完全重启游戏。

## F7 面板说明

| 行 / 按钮 | 作用 |
|---|---|
| 状态 / 生命 / 播放器 / Boss | 实时状态（探索/战斗/低血/决战/死亡）、播放器进程、交战 Boss 血量 |
| 四曲开关 | 即时生效，重启后恢复 config.ini 设定 |
| 试播 ×4 | 快速检查配曲，听完自动停 |
| 音量 ±10 / 保存 | 总音量；点**保存音量设置**才持久化 |
| 阈值 ±5 / 保存 | 低血触发阈值；点**保存阈值**写回 config.ini |
| 打开音乐文件夹 | 资源管理器在游戏窗口后面弹出 |
| 语言 | 中文 / English 即时切换，自动保存 |

## 常见问题排查

- **面板不出来**：确认 mods.txt 已加 `CustomBGM : 1`；完全重启游戏；查 `ue4ss\UE4SS.log`——出现 `unexpected symbol near '<\239>'` 说明 Lua 文件带 BOM，重新保存为 UTF-8 无 BOM。
- **播放器"未运行"**：多半是杀软隔离了 `PBZMusic\PBZPlayer.exe`，恢复并加入信任，SHA256 见下方；几秒后自动恢复是看门狗自愈，无需处理。
- **没声音**：看 `PBZMusic\player.log`——`media failed` = 格式/文件问题；`heartbeat lost` = 游戏侧心跳断。日志位置：`ue4ss\UE4SS.log` + `PBZMusic\player.log`。
- **手柄偶发失灵**：v0.6.5 已修复；若再遇，带上两个日志开 issue。
- **游戏大版本更新**：当前验证锚点 build 26266538 / CL 301524 / UE 5.7.4；大更新后可能需要适配。

**SHA256**（杀软拦截时可核对）：

```
PBZPlayer.exe            fb43a39259adf1e295a34aa9fe9e6cac4d2d8c4ef3b3abc34047e7fe0a391142
```

## 演示曲与许可

内置演示曲 —— **Guzheng City**（低血）、**Shenyang**（死亡）、**Clenched Teeth**（战斗）—— 作者 Kevin MacLeod（[incompetech.com](https://incompetech.com)），**CC BY 4.0** 授权随包分发，署名即在本页。可自由商用；换成自己的歌后可删除。本 mod 不含、不分发任何版权音乐。

更多免版权曲源：[Pixabay Music](https://pixabay.com/music/)（免署名）、YouTube 音频库、[incompetech](https://incompetech.com)（CC-BY）、[OpenGameArt](https://opengameart.org)（多为 CC0）。

## 构建

- 播放器：`player\make_wpf.bat` —— 用 .NET Framework 自带 `csc.exe` 编译 `PBZPlayerWPF.cs`，无外部依赖
- Lua 无需编译；保存 `.lua` 文件**不得带 UTF-8 BOM**（UE4SS 拒载 BOM 文件）

## 许可

MIT —— 见 [LICENSE](LICENSE)。vendored `ModMenu.lua` 为 MIT（mattdavida/ue4ss-ModMenu，含本地改动）。UE4SS 本体由其项目按自身条款分发，本仓库不捆绑。演示曲：Kevin MacLeod，CC BY 4.0。
