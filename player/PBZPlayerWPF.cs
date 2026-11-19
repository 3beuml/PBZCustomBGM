// PBZPlayerWPF.cs — CustomBGM v0.6.2 常驻播放进程（WPF MediaElement = Windows Media Foundation 解码）
// v0.6.1（11-04 夜）：
//   - 修切曲无声：交叉淡出结束后未重新武装淡入，新曲以 fadeLevel=0 永久静音（死亡曲/试播按此路径全哑）；
//     现在淡出完成后按是否仍持有 Source 重新武装淡入或复位音量
//   - alive.txt 改由专用线程写（System.Threading.Timer 无引用会被 GC 回收停摆）
//   - 新增看门狗：DispatcherTimer（Background 优先级）>15s 无 tick → 记日志 + 自杀退出，
//     Lua 哨兵 ≤5s 内重新拉起（21:49 实测 UI 泵停滞无声卡死的兜底自救）
// v0.6.2（11-04 深夜）：
//   - alive.txt 改写 unix epoch 秒：原先写 .NET Ticks（纪元公元1年），Lua os.time() 相减恒为负，
//     playerAlive() 永远判活 → 播放器死了永不重建、F7 谎报"运行中"（22:59 会话实证）
// v0.6.7（11-18）：
//   - 支持 state.txt 的 reload=1 行：重读 player.ini（此前"重载音乐配置"按钮只刷 Lua 侧显示，
//     播放器启动后从不重读 ini，换歌必须重启进程——11-18 白天班实锤修复）
// 支持：mp3 / wav / wma / m4a / aac / flac（ogg 不支持）
// 新增（相对 v0.5）：
//   - 每类曲目独立音量（[volumes] combat/low/death，0~100）+ 全局音量（global，可被菜单实时改）
//   - 切曲淡入淡出（0.4s），死亡曲播完自然结束，复cue/脱战淡出
//   - 歌单池：player.ini 里填【文件夹路径】即从该文件夹随机抽曲（mp3/wav/flac/wma/m4a/aac）
//   - state.txt 支持 volume=0~100 行：菜单实时改全局音量
//   - volume_override.txt：菜单"保存音量"写盘，启动时优先于 global
// 协议不变：state.txt + heartbeat.txt + alive.txt + player.log；单实例互斥体
//   - heartbeat 5 秒失效 → 停声待命
//   - state: combat(循环) / low(循环) / death(播一次) / explore / stop / off(停)
//   - /selftest；/warmup
// 编译：csc -target:winexe -r:System.dll -r:System.Core.dll -r:WindowsBase.dll
//        -r:PresentationCore.dll -r:PresentationFramework.dll -r:System.Xaml.dll PBZPlayerWPF.cs
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace PBZCustomBGM
{
    internal static class PBZPlayerWPF
    {
        const string MutexName = "PBZCustomBGM.Player.Mutex";
        const string StateFile = "state.txt";
        const string HeartbeatFile = "heartbeat.txt";
        const string AliveFile = "alive.txt";
        const string LogFile = "player.log";
        const string IniFile = "player.ini";
        const string VolOverrideFile = "volume_override.txt";
        const int SR = 22050;

        static string baseDir;
        static string combatPath = "combat.wav";
        static string lowPath = "low.wav";
        static string deathPath = "death.wav";
        static string bossPath;                                      // 决战曲：null = 沿用低血曲歌源
        static double volCombat = 0.8, volLow = 0.9, volDeath = 1.0; // 每类 0~1
        static double volBoss = 0.9;
        static int globalVol = 100;                                  // 全局 0~100

        static MediaElement media;
        static string lastState;
        static string lastPreview;
        static string lastOpen;             // 上一次处理的 open= 目标（null=无）
        static bool lastReload;             // reload=1 行的上升沿检测（true→false 之间只触发一次重读）
        static bool loopMode, onceMode, previewMode;
        static string currentLoopFile;

        // 淡入淡出状态机（100ms/步 ×4 ≈ 0.4s）
        static int fadeDir = 0;          // -1 淡出, +1 淡入, 0 无
        static double fadeLevel = 1.0;   // 0~1 乘子
        static Action pendingAfterFade;

        // 看门狗：Tick 每 100ms 戳一次；独立守护线程读戳判断 UI 泵死活
        static long lastUiTick;
        static Thread housekeeping;

        static int Main(string[] args)
        {
            baseDir = AppDomain.CurrentDomain.BaseDirectory;
            bool created = false;
            var mutex = new Mutex(true, MutexName, out created);
            if (!created) return 0;
            try
            {
                if (args != null && args.Length > 0)
                {
                    var a0 = args[0].TrimStart('/', '-');
                    if (string.Equals(a0, "selftest", StringComparison.OrdinalIgnoreCase)) { SelfTest(); return 0; }
                    if (string.Equals(a0, "warmup", StringComparison.OrdinalIgnoreCase)) { Warmup(); return 0; }
                }
                var th = new Thread(new ThreadStart(HostThread));
                th.SetApartmentState(ApartmentState.STA);
                th.IsBackground = false;
                th.Start();
                th.Join();
            }
            catch (Exception e)
            {
                try { Log("fatal: " + e.Message); } catch { }
            }
            finally
            {
                try { if (media != null) { media.Stop(); media.Source = null; } } catch { }
                try { mutex.ReleaseMutex(); } catch { }
            }
            return 0;
        }

        // ---------------- 焦点防护 ----------------
        // 隐藏窗口若成为前台焦点，游戏会失焦 → UE 引擎停用全部输入（手柄 A 无反应）。
        // WS_EX_NOACTIVATE 从系统层面禁止本窗口成为前台：无论进程重启多少次都不可能再抢焦点。
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
        const int GWL_EXSTYLE = -20;
        const int WS_EX_NOACTIVATE = 0x08000000;
        const int WS_EX_TOOLWINDOW = 0x00000080;

        static void ApplyNoActivateStyle(Window window)
        {
            try
            {
                var wih = new System.Windows.Interop.WindowInteropHelper(window);
                if (wih.Handle == IntPtr.Zero) return;
                int ex = GetWindowLong(wih.Handle, GWL_EXSTYLE);
                SetWindowLong(wih.Handle, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
                Log("focus-guard: WS_EX_NOACTIVATE applied (window can never take foreground)");
            }
            catch (Exception e) { try { Log("focus-guard error: " + e.Message); } catch { } }
        }

        // ---------------- STA 宿主 ----------------

        static void HostThread()
        {
            // 标准 WPF 上下文：没有 Application 时 MediaElement 音频管线会静默失效（v0.2 教训）
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            LoadIni();
            Log("started (MediaElement v0.6.7+focus-guard), baseDir=" + baseDir);

            var window = new Window
            {
                WindowStyle = WindowStyle.None,
                ShowInTaskbar = false,
                ShowActivated = false,
                Width = 200, Height = 120,
                Left = -2200, Top = -2000,
                Opacity = 0,
                Title = "PBZMusicPlayer",
            };
            var grid = new Grid();
            media = new MediaElement
            {
                LoadedBehavior = MediaState.Manual,
                UnloadedBehavior = MediaState.Manual,
                ScrubbingEnabled = false,
            };
            grid.Children.Add(media);
            window.Content = grid;

            media.MediaEnded += delegate { OnMediaEnded(); };
            media.MediaFailed += delegate(object s, System.Windows.ExceptionRoutedEventArgs e)
            {
                Log("media failed: " + e.ErrorException.Message);
            };
            media.MediaOpened += delegate
            {
                ApplyMediaVolume();
                Log("media opened (vol=" + Math.Round(TypeVolOf(activeType) * (globalVol / 100.0) * 100.0)
                    + "%, fadeDir=" + fadeDir + ")");
            };

            // 独立守护线程：写 alive.txt + 看门狗。
            // 不能用匿名 System.Threading.Timer（无托管引用会被 GC 回收，心跳无声停摆）；
            // 也不能只依赖 DispatcherTimer（Background 优先级可被饿死——21:49 实测 UI 泵停滞无声卡死）。
            housekeeping = new Thread(delegate()
            {
                while (true)
                {
                    Thread.Sleep(1000);
                    // 写 unix epoch 秒：Lua 侧 playerAlive() 用 os.time() 比对。
                    // 曾误写 .NET Ticks（纪元=公元1年，比 unix 大 ~638 年）→ 差值恒为负 → Lua 永远判"活着"，自愈失效（11-04 踩）。
                    long now = (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
                    try { File.WriteAllText(baseDir + AliveFile, now.ToString()); } catch { }
                    long ui = Interlocked.Read(ref lastUiTick);
                    if (ui != 0 && DateTime.UtcNow.Ticks - ui > TimeSpan.TicksPerSecond * 15)
                    {
                        try { Log("watchdog: ui pump stalled >15s, auto-exit for revive"); } catch { }
                        try { Environment.Exit(2); } catch { }
                    }
                }
            });
            housekeeping.IsBackground = false;
            housekeeping.Start();

            var timer = new DispatcherTimer(DispatcherPriority.Background);
            timer.Interval = TimeSpan.FromMilliseconds(100);
            timer.Tick += delegate { Tick(); };
            timer.Start();
            window.Show();
            ApplyNoActivateStyle(window);

            try { app.Run(); }
            catch (Exception e) { try { Log("app ended: " + e.Message); } catch { } }
        }

        // ---------------- 音量与淡入淡出 ----------------

        static string activeType = "low";
        static double TypeVolOf(string key)
        {
            if (key == "combat") return volCombat;
            if (key == "death") return volDeath;
            if (key == "boss") return volBoss;
            return volLow;
        }

        static void ApplyMediaVolume()
        {
            try
            {
                double v = TypeVolOf(activeType) * (globalVol / 100.0) * fadeLevel;
                if (v < 0) v = 0; if (v > 1) v = 1;
                media.Volume = v;
            }
            catch { }
        }

        static void FadeStep()
        {
            if (fadeDir == 0) return;
            if (fadeDir < 0)
            {
                fadeLevel -= 0.25;
                if (fadeLevel <= 0)
                {
                    fadeLevel = 0;
                    fadeDir = 0;
                    var p = pendingAfterFade;
                    pendingAfterFade = null;
                    if (p != null) p();

                    // v0.6.1 修复：切曲淡出收尾后必须重新武装淡入。
                    // 旧代码到此直接 return，fadeLevel 悬在 0、fadeDir=0，
                    // 新曲 MediaOpened 后 ApplyMediaVolume 算出 音量×0=0 且无人再动它 → 永久静声。
                    // 淡出挂的是"切曲"且新 Source 已就位 → 从 0 淡入；挂的是"停"（Source 已清） → 音量复位待命。
                    if (media != null && media.Source != null) { fadeLevel = 0; fadeDir = +1; }
                    else { fadeLevel = 1.0; fadeDir = 0; }
                    return;
                }
                try { media.Volume = TypeVolOf(activeType) * (globalVol / 100.0) * fadeLevel; } catch { }
            }
            else
            {
                fadeLevel += 0.25;
                if (fadeLevel >= 1) { fadeLevel = 1; fadeDir = 0; }
                try { media.Volume = TypeVolOf(activeType) * (globalVol / 100.0) * fadeLevel; } catch { }
            }
        }

        static void HardStop()
        {
            try { if (media != null && media.Source != null) { media.Stop(); media.Source = null; } } catch { }
            loopMode = false; onceMode = false; previewMode = false;
            currentLoopFile = null;
            fadeDir = 0; fadeLevel = 1.0; pendingAfterFade = null;
        }

        // ---------------- 主循环 ----------------

        static void Tick()
        {
            lastUiTick = DateTime.UtcNow.Ticks; // 看门狗用：证明 UI 泵还活着
            try
            {
                FadeStep();

                string state, preview, openPath; bool reload;
                ParseStateFile(out state, out preview, out openPath, out reload);
                // reload=1（F7"重载音乐配置"）：上升沿触发一次 ini 重读，
                // 新曲目路径对下一次状态切换生效（不打断正在播的曲子）
                if (reload && !lastReload)
                {
                    Log("reload: re-reading player.ini");
                    LoadIni();
                }
                lastReload = reload;
                if (!IsHeartbeatFresh(5.0) || state == null)
                {
                    if (lastState != null && media != null && media.Source != null)
                    {
                        HardStop();
                        Log("heartbeat lost -> stopped");
                    }
                    lastState = null; lastPreview = null; lastOpen = null;
                    return;
                }
                if (!string.Equals(state, lastState, StringComparison.OrdinalIgnoreCase))
                {
                    lastState = state;
                    lastPreview = null;
                    ApplyState(state);
                }
                else if (preview != lastPreview)
                {
                    lastPreview = preview;
                    if (!string.IsNullOrEmpty(preview)) StartPreview(preview);
                }
                // open= 目录：与 preview 同机制，内容变化即执行（Lua 侧 force 写盘 + 4s 保护窗）
                if (openPath != lastOpen)
                {
                    lastOpen = openPath;
                    if (!string.IsNullOrEmpty(openPath)) OpenFolder(openPath);
                }
            }
            catch (Exception e) { try { Log("tick error: " + e.Message); } catch { } }
        }

        static void ApplyState(string s)
        {
            if (s == "combat") SwitchMedia(PickMedia(combatPath), "combat", false);
            else if (s == "low") SwitchMedia(PickMedia(lowPath), "low", false);
            else if (s == "death") SwitchMedia(PickMedia(deathPath), "death", true);
            else if (s == "boss") SwitchMedia(PickMedia(string.IsNullOrEmpty(bossPath) ? lowPath : bossPath), "boss", false);
            else
            {
                // explore / stop / off：淡出后停
                if (media != null && media.Source != null)
                {
                    pendingAfterFade = delegate { HardStop(); };
                    fadeDir = -1;
                }
                else HardStop();
            }
        }

        static void SwitchMedia(string file, string key, bool once)
        {
            try
            {
                if (string.IsNullOrEmpty(file))
                {
                    if (currentLoopFile != key) Log("media missing for " + key);
                    if (media != null && media.Source != null)
                    {
                        pendingAfterFade = delegate { HardStop(); };
                        fadeDir = -1;
                    }
                    else HardStop();
                    currentLoopFile = key;
                    return;
                }
                activeType = key;
                bool wasActive = media != null && media.Source != null;
                Action open = delegate
                {
                    DoOpen(file, once);
                };
                if (wasActive)
                {
                    pendingAfterFade = open;
                    fadeDir = -1;
                }
                else
                {
                    fadeLevel = 0; fadeDir = +1;
                    open();
                }
            }
            catch (Exception e) { Log("SwitchMedia error: " + e.Message); }
        }

        static void DoOpen(string file, bool once)
        {
            try
            {
                if (media == null) return;
                if (media.Source != null) { media.Stop(); media.Source = null; }
                loopMode = !once; onceMode = once; previewMode = false;
                currentLoopFile = once ? null : file;
                media.Source = new Uri(file, UriKind.Absolute);
                media.Volume = 0;
                media.Play();
                Log((once ? "once " : "loop ") + "[" + activeType + " v" + Math.Round(TypeVolOf(activeType) * (globalVol / 100.0) * 100) + "%]: " + file);
            }
            catch (Exception e) { Log("DoOpen error: " + e.Message); }
        }

        static void StartPreview(string file)
        {
            try
            {
                string f = PickMedia(file);
                if (string.IsNullOrEmpty(f)) { Log("preview missing: " + file); return; }
                activeType = "preview";
                bool wasActive = media != null && media.Source != null;
                Action open = delegate
                {
                    if (media.Source != null) { media.Stop(); media.Source = null; }
                    loopMode = false; onceMode = false; previewMode = true;
                    currentLoopFile = null;
                    media.Source = new Uri(f, UriKind.Absolute);
                    media.Volume = 0;
                    media.Play();
                    Log("preview: " + f);
                };
                if (wasActive) { pendingAfterFade = open; fadeDir = -1; }
                else { fadeLevel = 0; fadeDir = +1; open(); }
            }
            catch (Exception e) { Log("StartPreview error: " + e.Message); }
        }

        static void OnMediaEnded()
        {
            try
            {
                if (previewMode)
                {
                    Log("preview finished");
                    ApplyState(lastState);
                    return;
                }
                if (loopMode)
                {
                    media.Position = TimeSpan.Zero;
                    media.Play();
                    return;
                }
                // once（死亡曲）自然结束 → 保持安静
            }
            catch (Exception e) { Log("OnMediaEnded error: " + e.Message); }
        }

        // ---------------- 曲目解析（文件 or 歌单池文件夹） ----------------

        static readonly string[] MediaExts = { "*.mp3", "*.wav", "*.flac", "*.wma", "*.m4a", "*.aac" };

        static string PickMedia(string p)
        {
            if (string.IsNullOrEmpty(p)) return null;
            string f = (!Path.IsPathRooted(p)) ? Path.Combine(baseDir, p) : p;
            try
            {
                if (Directory.Exists(f))
                {
                    var list = new System.Collections.Generic.List<string>();
                    foreach (var pat in MediaExts)
                        try { list.AddRange(Directory.GetFiles(f, pat)); } catch { }
                    if (list.Count == 0) return null;
                    var rnd = new Random(unchecked((int)DateTime.Now.Ticks));
                    return list[rnd.Next(list.Count)];
                }
                if (File.Exists(f)) return f;
            }
            catch { }
            return null;
        }

        // ---------------- 系统文件 ----------------

        static bool IsHeartbeatFresh(double maxAgeSeconds)
        {
            try
            {
                var f = baseDir + HeartbeatFile;
                if (!File.Exists(f)) return false;
                var age = (DateTime.UtcNow - File.GetLastWriteTimeUtc(f)).TotalSeconds;
                return age >= -2.0 && age <= maxAgeSeconds;
            }
            catch { return false; }
        }

        static void ParseStateFile(out string state, out string preview, out string openPath, out bool reload)
        {
            state = null; preview = null; openPath = null; reload = false;
            try
            {
                if (!File.Exists(baseDir + StateFile)) return;
                foreach (var raw in File.ReadAllLines(baseDir + StateFile))
                {
                    var line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#") || line.StartsWith(";")) continue;
                    int eq = line.IndexOf('=');
                    if (eq <= 0) continue;
                    var k = line.Substring(0, eq).Trim().ToLowerInvariant();
                    var v = line.Substring(eq + 1).Trim().Replace("\"", "");
                    if (k == "state" && v.Length > 0) state = v;
                    else if (k == "preview" && v.Length > 0) preview = v;
                    else if (k == "open" && v.Length > 0) openPath = v;
                    else if (k == "volume")
                    {
                        int d;
                        if (int.TryParse(v, out d) && d >= 0 && d <= 100 && d != globalVol)
                        {
                            globalVol = d;
                            ApplyMediaVolume();
                            Log("global volume -> " + d + "%");
                        }
                    }
                    else if (k == "reload")
                    {
                        reload = (v == "1");
                    }
                }
            }
            catch { }
        }

        // 用 ShellExecute 打开目录（资源管理器）：F7"打开音乐文件夹"由此代劳，
        // 游戏线程里的 LaunchURL(file:///目录) 实测会卡死游戏（11-05 踩），故移到本进程执行
        static void OpenFolder(string path)
        {
            try
            {
                Log("open folder: " + path);
                var psi = new System.Diagnostics.ProcessStartInfo();
                psi.FileName = path;
                psi.UseShellExecute = true;
                System.Diagnostics.Process.Start(psi);
            }
            catch (Exception e)
            {
                try { Log("open folder error: " + e.Message); } catch { }
            }
        }

        static void LoadIni()
        {
            try
            {
                var f = baseDir + IniFile;
                // 默认值
                combatPath = "combat.wav"; lowPath = "low.wav"; deathPath = "death.wav"; bossPath = null;
                volCombat = 0.8; volLow = 0.9; volDeath = 1.0; volBoss = 0.9; globalVol = 100;
                if (!File.Exists(f)) { Log(IniFile + " not found, using defaults"); return; }
                string section = "";
                foreach (var raw in File.ReadAllLines(f))
                {
                    var line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#") || line.StartsWith(";")) continue;
                    if (line.StartsWith("["))
                    {
                        section = line.Trim('[', ']').ToLowerInvariant();
                        continue;
                    }
                    int eq = line.IndexOf('=');
                    if (eq <= 0) continue;
                    var k = line.Substring(0, eq).Trim().ToLowerInvariant();
                    var v = line.Substring(eq + 1).Trim().Replace("\"", "");
                    double d;
                    if (section == "files")
                    {
                        if (k == "combat") combatPath = v;
                        else if (k == "low") lowPath = v;
                        else if (k == "death") deathPath = v;
                        else if (k == "boss") bossPath = v;
                    }
                    else if (section == "volumes")
                    {
                        if (double.TryParse(v, out d))
                        {
                            if (d < 0) d = 0; if (d > 100) d = 100;
                            if (k == "combat") volCombat = d / 100.0;
                            else if (k == "low") volLow = d / 100.0;
                            else if (k == "death") volDeath = d / 100.0;
                            else if (k == "boss") volBoss = d / 100.0;
                            else if (k == "global") globalVol = (int)d;
                        }
                    }
                }
                // 菜单"保存音量"的覆盖文件优先
                var vo = baseDir + VolOverrideFile;
                if (File.Exists(vo))
                {
                    int d;
                    if (int.TryParse(File.ReadAllText(vo).Trim(), out d) && d >= 0 && d <= 100) globalVol = d;
                }
                Log(string.Format("files: combat={0} low={1} death={2} boss={3} | vol c/l/d/b/g={4}/{5}/{6}/{7}/{8}%",
                    combatPath, lowPath, deathPath, bossPath,
                    (int)Math.Round(volCombat * 100), (int)Math.Round(volLow * 100),
                    (int)Math.Round(volDeath * 100), (int)Math.Round(volBoss * 100), globalVol));
            }
            catch (Exception e) { Log("LoadIni error: " + e.Message); }
        }

        static void Log(string s)
        {
            try
            {
                var path = baseDir + LogFile;
                var line = DateTime.Now.ToString("HH:mm:ss") + "  " + s + Environment.NewLine;
                if (File.Exists(path) && new FileInfo(path).Length > 256 * 1024) File.WriteAllText(path, "");
                File.AppendAllText(path, line);
            }
            catch { }
        }

        // ---------------- 自检 与 测试音 ----------------

        static void SelfTest()
        {
            try
            {
                LoadIni();
                var ok = new System.Text.StringBuilder();
                ok.AppendLine("selftest=true");
                ok.AppendLine("build=mediaelement-v0.6");
                ok.AppendLine("time=" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                ok.AppendLine("combat=" + Resolve(combatPath) + " exists=" + (File.Exists(Resolve(combatPath)) || Directory.Exists(Resolve(combatPath)) ? "1" : "0"));
                ok.AppendLine("low=" + Resolve(lowPath) + " exists=" + (File.Exists(Resolve(lowPath)) || Directory.Exists(Resolve(lowPath)) ? "1" : "0"));
                ok.AppendLine("death=" + Resolve(deathPath) + " exists=" + (File.Exists(Resolve(deathPath)) || Directory.Exists(Resolve(deathPath)) ? "1" : "0"));
                ok.AppendLine(string.Format("volumes c/l/d/g = {0}/{1}/{2}/{3}",
                    (int)Math.Round(volCombat * 100), (int)Math.Round(volLow * 100),
                    (int)Math.Round(volDeath * 100), globalVol));
                File.WriteAllText(baseDir + "selftest_ok.txt", ok.ToString());
            }
            catch (Exception e)
            {
                try { File.WriteAllText(baseDir + "selftest_ok.txt", "selftest=false\r\nerror=" + e.Message); } catch { }
            }
        }

        static void Warmup()
        {
            try
            {
                WriteWav(Resolve(combatPath), delegate(int i)
                {
                    double t = (i % (1.5 * SR)) / (double)SR;
                    double f = (t < 0.75) ? 440.0 : 660.0;
                    double edge = Math.Min(t, 1.5 - t) / 0.06; if (edge > 1.0) edge = 1.0;
                    return Math.Sin(2 * Math.PI * f * t) * 0.45 * edge;
                }, 6);
                WriteWav(Resolve(lowPath), delegate(int i)
                {
                    double t = (i % (0.5 * SR)) / (double)SR;
                    double on = (t > 0.02 && t < 0.14) ? 1.0 : 0.0;
                    double env = Math.Min(t - 0.02, 0.14 - t) / 0.02; if (env > 1.0) env = 1.0;
                    return Math.Sin(2 * Math.PI * 880.0 * t) * 0.35 * on * env;
                }, 5);
                WriteWav(Resolve(deathPath), delegate(int i)
                {
                    double t = (double)i / (double)SR;
                    double f = 300.0 - 50.0 * t;
                    double env = Math.Max(0.0, 1.0 - t / 3.0);
                    return Math.Sin(2 * Math.PI * f * t) * 0.4 * env;
                }, 3);
                Log("warmup done");
            }
            catch (Exception e)
            {
                try { Log("warmup error: " + e.Message); } catch { }
            }
        }

        static short ToShort(double s)
        {
            if (s > 1.0) s = 1.0; if (s < -1.0) s = -1.0;
            return (short)(s * 32767.0);
        }

        static string Resolve(string p)
        {
            if (string.IsNullOrEmpty(p)) return null;
            if (!Path.IsPathRooted(p)) p = Path.Combine(baseDir, p);
            return p;
        }

        static void WriteWav(string path, Func<int, double> fn, int seconds)
        {
            using (var fs = new FileStream(path, FileMode.Create))
            using (var w = new System.IO.BinaryWriter(fs))
            {
                int dataBytes = seconds * SR * 2;
                w.Write(new byte[] { 0x52, 0x49, 0x46, 0x46 });
                w.Write(36 + dataBytes);
                w.Write(new byte[] { 0x57, 0x41, 0x56, 0x45 });
                w.Write(new byte[] { 0x66, 0x6D, 0x74, 0x20 });
                w.Write(16); w.Write((short)1); w.Write((short)1);
                w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
                w.Write(new byte[] { 0x64, 0x61, 0x74, 0x61 });
                w.Write(dataBytes);
                for (int i = 0; i < seconds * SR; i++) w.Write(ToShort(fn(i)));
            }
        }
    }
}
