// PBZCustomBGM-Setup.cs — 一键安装/卸载器（控制台 exe，无外壳、无执行策略摩擦）
// 用法：
//   PBZCustomBGM-Setup.exe                       （自动找游戏，装）
//   PBZCustomBGM-Setup.exe -gamepath X:\...\PBZ\platform\steam
//   PBZCustomBGM-Setup.exe -uninstall
//   PBZCustomBGM-Setup.exe -y                    （跳过所有交互与暂停；自动化/无终端安全）
//   PBZCustomBGM-Setup.exe -launch               （装完自动启动游戏；交互模式走询问）
// 语义与 install.ps1 一致：
//   - 安装 = 新增文件（Mods\CustomBGM + PBZMusic），绝不覆盖游戏原文件
//   - 重装 = 旧 PBZMusic 整体改名 PBZMusic.previous（用户歌保留），新目录为干净默认
//   - 卸载 = 删 mod、PBZMusic 改名 PBZMusic.by-uninstaller 保留用户歌、UE4SS 不动
//   - 找不到游戏时打印扫描过的所有 Steam 库，方便贴日志求助
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

static class Setup
{
    const string AppId = "4115450";
    static string srcRoot; // exe 同级的 Mods\ 与 PBZMusic\ 所在目录

    static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }
        try { Console.InputEncoding = Encoding.UTF8; } catch { }

        srcRoot = AppDomain.CurrentDomain.BaseDirectory;
        bool uninstall = false, assumeYes = false, launchFlag = false;
        string gamePath = null;
        if (args != null)
        {
            for (int i = 0; i < args.Length; i++)
            {
                string a = (args[i] ?? "").Trim().TrimStart('-', '/').ToLowerInvariant();
                if (a == "uninstall") uninstall = true;
                else if (a == "y" || a == "yes") assumeYes = true;
                else if (a == "launch") launchFlag = true;
                else if (a == "gamepath" || a == "g")
                {
                    if (i + 1 < args.Length) gamePath = args[++i].Trim('"');
                }
                else if (a == "h" || a == "help" || a == "?")
                {
                    Console.WriteLine("用法: PBZCustomBGM-Setup.exe [-uninstall] [-gamepath 路径] [-launch] [-y]");
                    return 0;
                }
            }
        }

        Console.WriteLine();
        Console.WriteLine("==========================================");
        Console.WriteLine(" PBZCustomBGM 安装器（安装=新增文件，绝不碰游戏本体）");
        Console.WriteLine("==========================================");
        Console.WriteLine();

        try
        {
            if (uninstall) return DoUninstall(gamePath, assumeYes);
            return DoInstall(gamePath, assumeYes, launchFlag);
        }
        catch (Exception e)
        {
            Console.WriteLine("[错误] " + e.Message);
            Pause(assumeYes);
            return 1;
        }
    }

    // ---------- 游戏定位 ----------
    static void AddRoot(List<string> roots, string r)
    {
        if (string.IsNullOrEmpty(r)) return;
        try { r = Path.GetFullPath(r); } catch { return; }
        if (!roots.Contains(r)) roots.Add(r);
    }

    static List<string> FindGameCandidates()
    {
        var roots = new List<string>();

        foreach (var keyName in new[] { "HKEY_CURRENT_USER", "HKEY_LOCAL_MACHINE" })
        {
            try
            {
                var keyPath = keyName == "HKEY_CURRENT_USER"
                    ? @"HKEY_CURRENT_USER\SOFTWARE\Valve\Steam"
                    : @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam";
                var valueName = keyName == "HKEY_CURRENT_USER" ? "SteamPath" : "InstallPath";
                var key = Microsoft.Win32.Registry.GetValue(keyPath, valueName, null) as string;
                if (!string.IsNullOrEmpty(key)) AddRoot(roots, key);
            }
            catch { }
        }

        foreach (var r in roots.ToArray())
        {
            var vdf = Path.Combine(r, "steamapps", "libraryfolders.vdf");
            if (File.Exists(vdf))
            {
                try
                {
                    var rx = new Regex("\x22path\x22\\s+\x22([^\x22]+)\x22");
                    foreach (Match m in rx.Matches(File.ReadAllText(vdf)))
                        AddRoot(roots, m.Groups[1].Value.Replace(@"\\", @"\"));
                }
                catch { }
            }
        }

        var hits = new List<string>();
        foreach (var r in roots)
        {
            var p = Path.Combine(r, "steamapps", "common", "PBZ", "platform", "steam");
            if (File.Exists(Path.Combine(p, "PBZ.exe"))) hits.Add(p);
        }
        return hits;
    }

    static void PrintScanned(List<string> roots)
    {
        if (roots.Count == 0) { Console.WriteLine("（未找到任何 Steam 库目录）"); return; }
        Console.WriteLine("扫描过的 Steam 库目录：");
        foreach (var r in roots) Console.WriteLine("  · " + r);
    }

    static string ResolveGame(string argPath, bool assumeYes)
    {
        // 参数优先
        if (!string.IsNullOrEmpty(argPath))
        {
            var p = Path.GetFullPath(argPath);
            if (!File.Exists(Path.Combine(p, "PBZ.exe")))
            {
                Console.WriteLine("[错误] 指定目录不是游戏目录（没找到 PBZ.exe）：" + p);
                Pause(assumeYes); Environment.Exit(1);
            }
            return p;
        }

        var candidates = FindGameCandidates();
        if (candidates.Count == 0)
        {
            Console.WriteLine("[错误] 所有 Steam 库里都没找到《影之刃零》。");
            PrintScanned(FindGameCandidates());
            Console.WriteLine("请用参数指定游戏目录后重试：");
            Console.WriteLine("  PBZCustomBGM-Setup.exe -gamepath \"X:\\...\\steamapps\\common\\PBZ\\platform\\steam\"");
            Pause(assumeYes); Environment.Exit(1);
        }
        if (candidates.Count == 1) return candidates[0];

        // 多库命中：让用户挑
        Console.WriteLine("在多个 Steam 库找到《影之刃零》：");
        for (int i = 0; i < candidates.Count; i++) Console.WriteLine("  [" + (i + 1) + "] " + candidates[i]);
        int pick = 1;
        if (!assumeYes)
        {
            Console.Write("安装到哪一个？输入编号直接回车=1： ");
            var line = Console.ReadLine();
            int.TryParse((line ?? "").Trim(), out pick);
        }
        if (pick < 1 || pick > candidates.Count) pick = 1;
        return candidates[pick - 1];
    }

    // ---------- 安装 ----------
    static int DoInstall(string argPath, bool assumeYes, bool launchFlag)
    {
        if (!Directory.Exists(Path.Combine(srcRoot, "Mods", "CustomBGM", "Scripts")))
        {
            Console.WriteLine("[错误] 包结构不完整：缺少 Mods\\CustomBGM（安装器需与 Mods、PBZMusic 目录同级）");
            Pause(assumeYes); return 1;
        }

        string game = ResolveGame(argPath, assumeYes);
        string ue4ss = Path.Combine(game, "ue4ss");
        int tries = 0;
        while (!File.Exists(Path.Combine(game, "dwmapi.dll")) || !Directory.Exists(ue4ss))
        {
            // 新手引导：缺 UE4SS 不是死路——给链接 + 精确放置位置，装完按 Enter 重检（最多 3 轮）
            Console.WriteLine("[提示] 该目录还没有 UE4SS（游玩本 mod 的必需前置，只装一次）。");
            Console.WriteLine("  1. 打开下载页（需要登录 Nexus 账号）：");
            Console.WriteLine("     https://www.nexusmods.com/phantombladezero/mods/413");
            Console.WriteLine("  2. 把下载压缩包里的 dwmapi.dll 和 ue4ss 文件夹放进：");
            Console.WriteLine("     " + game);
            try { Process.Start(new ProcessStartInfo("https://www.nexusmods.com/phantombladezero/mods/413") { UseShellExecute = true }); } catch { }
            if (assumeYes) { Console.WriteLine("[错误] -y 模式无法等待手动安装 UE4SS。"); Pause(true); return 1; }
            tries++;
            if (tries >= 3)
            {
                Console.WriteLine("[错误] 重检 3 轮仍未检测到 UE4SS。");
                Console.WriteLine("       装好 UE4SS 后重新运行本安装器即可继续。");
                Pause(false); return 1;
            }
            Console.Write("装好 UE4SS 后按 Enter 重新检测（输入 n 退出）: ");
            var line2 = Console.ReadLine();
            if (line2 != null && line2.Trim().ToLowerInvariant().StartsWith("n")) { Pause(false); return 1; }
        }

        Console.WriteLine();
        Console.WriteLine("目标游戏目录：");
        Console.WriteLine("  " + game);
        Console.WriteLine("将写入（全部为新增文件）：");
        Console.WriteLine("  " + ue4ss + "\\Mods\\CustomBGM");
        Console.WriteLine("  " + Path.Combine(game, "PBZMusic"));
        if (!assumeYes)
        {
            Console.Write("确认安装? [Y/n]: ");
            var ans = Console.ReadLine();
            if (!string.IsNullOrEmpty(ans) && ans.Trim().ToLowerInvariant().StartsWith("n"))
            {
                Console.WriteLine("已取消，未做任何改动。");
                Pause(assumeYes); return 0;
            }
        }

        // mods 目录
        string destMod = Path.Combine(ue4ss, "Mods", "CustomBGM");
        if (Directory.Exists(destMod))
        {
            var old = Path.Combine(ue4ss, "Mods", "CustomBGM.previous");
            if (Directory.Exists(old)) Directory.Delete(old, true);
            Directory.Move(destMod, old);
            Console.WriteLine("  · 旧 mod 目录保留为 CustomBGM.previous");
        }
        CopyDir(Path.Combine(srcRoot, "Mods", "CustomBGM"), destMod);
        Console.WriteLine("  · 已安装 ue4ss\\Mods\\CustomBGM");

        // mods.txt 行
        string modsTxt = Path.Combine(ue4ss, "Mods", "mods.txt");
        if (!File.Exists(modsTxt)) File.WriteAllText(modsTxt, "CustomBGM : 1\r\n");
        else
        {
            var lines = new List<string>(File.ReadAllLines(modsTxt));
            bool found = false;
            for (int i = 0; i < lines.Count; i++)
                if (Regex.IsMatch(lines[i], @"^\s*CustomBGM\s*:"))
                {
                    lines[i] = "CustomBGM : 1"; found = true;
                }
            if (!found) lines.Add("CustomBGM : 1");
            File.WriteAllLines(modsTxt, lines);
        }

        // 音乐目录（重装时整体改名保留用户歌）
        string destMus = Path.Combine(game, "PBZMusic");
        if (Directory.Exists(destMus))
        {
            var prev = Path.Combine(game, "PBZMusic.previous");
            if (Directory.Exists(prev)) Directory.Delete(prev, true);
            Directory.Move(destMus, prev);
            Console.WriteLine("  · 旧音乐目录保留为 PBZMusic.previous（你的歌都在里面，可拷回来）");
        }
        CopyDir(Path.Combine(srcRoot, "PBZMusic"), destMus);
        Console.WriteLine("  · 已安装 PBZMusic");

        Console.WriteLine();
        Console.WriteLine("✅ 安装完成。进游戏后按 F7 打开 CustomBGM 面板。");
        Console.WriteLine("   （mod 不带歌曲——把你的歌放进 PBZMusic，见里面的用户必读）");
        bool launch = launchFlag;
        if (!assumeYes)
        {
            Console.Write("现在启动游戏? [Y/n]: ");
            var ans = Console.ReadLine();
            launch = string.IsNullOrEmpty(ans) || !ans.Trim().ToLowerInvariant().StartsWith("n");
        }
        if (launch)
        {
            try
            {
                Process.Start(new ProcessStartInfo("steam://" + "rungameid/" + AppId) { UseShellExecute = true });
                Console.WriteLine("已请求 Steam 启动游戏。");
            }
            catch { Console.WriteLine("无法自动拉起 Steam，请从库中启动。"); }
        }
        Pause(assumeYes);
        return 0;
    }

    // ---------- 卸载 ----------
    static int DoUninstall(string argPath, bool assumeYes)
    {
        Console.WriteLine("拆除 CustomBGM（只删 mod 自己的新增文件，游戏本体/UE4SS 不动）。");
        string game = ResolveGame(argPath, assumeYes);
        if (!assumeYes)
        {
            Console.Write("确认从 " + game + " 卸载? [Y/n]: ");
            var ans = Console.ReadLine();
            if (!string.IsNullOrEmpty(ans) && ans.Trim().ToLowerInvariant().StartsWith("n"))
            {
                Console.WriteLine("已取消。"); Pause(assumeYes); return 0;
            }
        }

        string destMod = Path.Combine(game, "ue4ss", "Mods", "CustomBGM");
        if (Directory.Exists(destMod)) { Directory.Delete(destMod, true); Console.WriteLine("  · 已删除 ue4ss\\Mods\\CustomBGM"); }
        else Console.WriteLine("  · 未发现 mod 目录（可能已删）");

        var modsTxt = Path.Combine(game, "ue4ss", "Mods", "mods.txt");
        if (File.Exists(modsTxt))
        {
            var keep = new List<string>();
            foreach (var l in File.ReadAllLines(modsTxt))
                if (!Regex.IsMatch(l ?? "", @"^\s*CustomBGM\s*:")) keep.Add(l);
            File.WriteAllLines(modsTxt, keep);
            Console.WriteLine("  · mods.txt 已清 CustomBGM 行");
        }

        string mus = Path.Combine(game, "PBZMusic");
        if (Directory.Exists(mus))
        {
            string bak = mus + ".by-uninstaller";
            if (Directory.Exists(bak))
            {
                // 之前卸载留下的备份不许删（用户的歌在里面）——用时间戳错开命名
                bak += DateTime.Now.ToString("-yyyyMMdd-HHmmss");
                while (Directory.Exists(bak)) bak += "x";
            }
            Directory.Move(mus, bak);
            Console.WriteLine("  · PBZMusic 保留为 " + Path.GetFileName(bak) + "（你的歌在里面）");
        }
        Console.WriteLine();
        Console.WriteLine("✅ 卸载完成（UE4SS 保留——不再需要时手动删除 dwmapi.dll 与 ue4ss 目录）");
        Pause(assumeYes);
        return 0;
    }

    // ---------- 工具 ----------
    static void CopyDir(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (var f in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
        {
            var rel = f.Substring(from.Length).TrimStart('\\', '/');
            var dest = Path.Combine(to, rel);
            Directory.CreateDirectory(Path.GetDirectoryName(dest));
            File.Copy(f, dest, true);
        }
    }

    // skipThank(-y / 无终端) 时直接返回，防止 ReadLine 挂起
    static void Pause(bool skip)
    {
        if (skip) return;
        try { Console.Write("按 Enter 退出…"); Console.ReadLine(); } catch { }
    }
}
