-- CustomBGM v0.1 — Phantom Blade Zero 自定义音乐触发
-- 原则：游戏侧只读不写（哨兵轮询），声音全部交给无窗播放进程 PBZPlayer.exe
-- 通信：写入 PBZMusic\state.txt + heartbeat.txt（心跳保鲜，游戏退出后播放器自动静音）
-- 依赖：UE4SS v3.0.1-1183（Kintaro PBZ 版）；ModMenu.lua 框架（MIT，维护于 vendored copy）
-- 已验证游戏版本：Steam 4115450，build 26266538 / CL 301524 / UE 5.7.4
-- 来源参考：xbunax/pbz_damage_test（MusicSubsystem 摸底）、nxvpsn/PBZ DCounter（死亡数据可行性）

local source = debug.getinfo(1, 'S').source
local DIR = source:gsub('^@', ''):match('^(.*[/\\])')
if not DIR then
    print('[CustomBGM] Disabled: cannot resolve Scripts directory\n')
    return
end

local function log(s) print('[CustomBGM] ' .. tostring(s) .. '\n') end
local CFG = dofile(DIR .. 'config.lua')

--------------------------------------------------
-- UE4SS shared UEHelpers（傻缺版本差异时自动退化到 FindAllOf）
--------------------------------------------------
local okH, UEHelpers = pcall(require, 'UEHelpers')

--------------------------------------------------
-- 配置（mod 根目录 config.ini = Scripts 的上一级 CustomBGM\）
-- 11-05 修：曾误读 Scripts\config.ini（不存在）→ 全程吃默认值
--------------------------------------------------
local MODROOT = CFG.parent(DIR, 1) -- DIR 以分隔符结尾，直接上溯一级 = CustomBGM\
local cfg = CFG.loadIni(MODROOT .. 'config.ini')
local opt = {
    menuKey    = (cfg.keybinds and cfg.keybinds.menutoggle) or 'F7',
    master     = CFG.bool(cfg.switches and cfg.switches.masterenabled, true),
    combat     = CFG.bool(cfg.switches and cfg.switches.combatmusic, true),
    low        = CFG.bool(cfg.switches and cfg.switches.lowhealthmusic, true),
    death      = CFG.bool(cfg.switches and cfg.switches.deathmusic, true),
    boss       = CFG.bool(cfg.switches and cfg.switches.bossmusic, true),
    lowSticky  = CFG.bool(cfg.switches and cfg.switches.lowuntilbattleend, true),
    lowPct     = CFG.num(cfg.thresholds and cfg.thresholds.lowhealthpercent, 40, 1, 99),
    lowExitPct = CFG.num(cfg.thresholds and cfg.thresholds.lowhysteresispercent, 5, 0, 49),
    bossPct    = CFG.num(cfg.thresholds and cfg.thresholds.bosslowpercent, 25, 1, 99),
    deathHold  = CFG.num(cfg.thresholds and cfg.thresholds.deathholdseconds, 10, 0, 120),
    pollMs     = CFG.num(cfg.thresholds and cfg.thresholds.pollintervalms, 200, 50, 2000),
    debug      = CFG.bool(cfg.debug and cfg.debug.statelog, false),
    lang       = (cfg.display and cfg.display.lang == 'en') and 'en' or 'zh',
}

--------------------------------------------------
-- 界面文案（zh/en 双语；F7「语言」按钮即时切换并写回 config.ini [Display] Lang）
-- 范围：面板可见文案全部双语；UE4SS.log 日志保持中文（排障口径统一，不受语言影响）
--------------------------------------------------
local STR = {
    zh = {
        panel_title   = 'CustomBGM 音乐箱',
        st_explore    = '探索（默认）', st_combat = '战斗', st_low = '血量低',
        st_death      = '死亡', st_boss = 'BOSS决战', st_stop = '已停用',
        lb_status     = '当前状态：', lb_hp_fmt = '生命：%.0f / %.0f', hp_dash = '生命：-',
        src_ok        = 'MusicSubsystem：✓，战斗=%s，特殊敌=%s',
        src_na        = 'MusicSubsystem：未发现（游戏加载中）',
        player_ok     = '播放器：运行中', player_na = '播放器：未运行（将自动拉起）',
        files_fmt     = '音乐文件 战斗[%s] 低血[%s] 死亡[%s] 决战[%s]',
        lb_now        = '正在播放：', now_none = '（无）', preview_tag = '（试播）',
        boss_duel     = 'Boss：★决战中 血 %.0f / %.0f',
        boss_fight    = 'Boss：交战中 血 %.0f / %.0f（≤%d%%触发）',
        boss_na       = 'Boss：未发现（交战特殊敌人后方能读血）',
        lowpct_fmt    = '低血阈值：%d%%（±5 可调，保存后重启保留）',
        vols_fmt      = '音量：战斗%d%% 低血%d%% 死亡%d%% 决战%d%% | 总音量 %d%%',
        lb_tip        = '提示：', lb_warn = '注意：',
        master_on     = '总开关：开（点击关闭）', master_off = '总开关：关（点击开启）',
        combat_on     = '战斗曲：开', combat_off = '战斗曲：关',
        low_on        = '低血曲：开', low_off = '低血曲：关',
        death_on      = '死亡曲：开', death_off = '死亡曲：关',
        sticky_on     = '低血粘滞：开', sticky_off = '低血粘滞：关',
        boss_on       = '决战曲：开', boss_off = '决战曲：关',
        btn_lang      = '语言：中文（点击切换 English）',
        pv            = '试播：%s', pv_combat = '战斗曲', pv_low = '低血曲',
        pv_death      = '死亡曲', pv_boss = '决战曲',
        pv_ok         = '已请求试播：%s',
        pv_fail       = '试播失败：找不到 %s',
        pv_fail_unset = '试播失败：未配置 %s',
        vol_down      = '总音量 −10', vol_up = '总音量 +10', vol_save = '保存音量设置',
        pct_down      = '低血阈值 −5', pct_up = '低血阈值 +5', pct_save = '保存阈值',
        fixinput      = '修复输入模式', stopall = '全部停止',
        open_media    = '打开音乐文件夹', reload_ini = '重载音乐配置', close = '关闭菜单',
        open_req      = '已请求打开音乐文件夹（资源管理器在游戏后面，切出去即见）',
        pct_missing   = '保存阈值失败：找不到 config.ini',
        pct_noline    = '保存阈值失败：config.ini 里没有 LowHealthPercent 行',
        pct_saved     = '已保存低血阈值 %d%%（重启后生效于此值）',
        pct_ro        = '保存阈值失败：config.ini 不可写',
        lang_saved    = '界面语言已切换：%s（已保存，重启后保留）',
        dash          = '-',
        vols_dash     = '音量：-', lowpct_dash = '低血阈值：-',
    },
    en = {
        panel_title   = 'CustomBGM Music Box',
        st_explore    = 'Explore (default)', st_combat = 'Combat', st_low = 'Low HP',
        st_death      = 'Death', st_boss = 'BOSS DUEL', st_stop = 'Disabled',
        lb_status     = 'State: ', lb_hp_fmt = 'HP: %.0f / %.0f', hp_dash = 'HP: -',
        src_ok        = 'MusicSubsystem: OK, battle=%s, special=%s',
        src_na        = 'MusicSubsystem: not found (game loading)',
        player_ok     = 'Player: running', player_na = 'Player: not running (auto-restart)',
        files_fmt     = 'Files combat[%s] low[%s] death[%s] boss[%s]',
        lb_now        = 'Now playing: ', now_none = '(none)', preview_tag = ' (preview)',
        boss_duel     = 'Boss: ★DUEL hp %.0f / %.0f',
        boss_fight    = 'Boss: engaged hp %.0f / %.0f (triggers ≤%d%%)',
        boss_na       = 'Boss: not found (readable while special enemy engaged)',
        lowpct_fmt    = 'Low-HP threshold: %d%% (±5 adjustable, Save keeps it)',
        vols_fmt      = 'Vol: combat %d%% low %d%% death %d%% boss %d%% | master %d%%',
        lb_tip        = 'Tip: ', lb_warn = 'Warning: ',
        master_on     = 'Master: ON (click to stop)', master_off = 'Master: OFF (click to start)',
        combat_on     = 'Combat track: ON', combat_off = 'Combat track: OFF',
        low_on        = 'Low-HP track: ON', low_off = 'Low-HP track: OFF',
        death_on      = 'Death track: ON', death_off = 'Death track: OFF',
        sticky_on     = 'Low-HP sticky: ON', sticky_off = 'Low-HP sticky: OFF',
        boss_on       = 'Duel track: ON', boss_off = 'Duel track: OFF',
        btn_lang      = 'Language: English (click for 中文)',
        pv            = 'Preview: %s', pv_combat = 'Combat', pv_low = 'Low-HP',
        pv_death      = 'Death', pv_boss = 'Duel',
        pv_ok         = 'Preview requested: %s',
        pv_fail       = 'Preview failed: file not found (%s)',
        pv_fail_unset = 'Preview failed: %s not configured',
        vol_down      = 'Master vol −10', vol_up = 'Master vol +10', vol_save = 'Save volume',
        pct_down      = 'Low-HP −5', pct_up = 'Low-HP +5', pct_save = 'Save threshold',
        fixinput      = 'Fix input mode', stopall = 'Stop all',
        open_media    = 'Open music folder', reload_ini = 'Reload music config', close = 'Close menu',
        open_req      = 'Music folder opening (Explorer opens behind the game window)',
        pct_missing   = 'Save failed: config.ini not found',
        pct_noline    = 'Save failed: LowHealthPercent line missing',
        pct_saved     = 'Low-HP threshold saved: %d%% (kept after restart)',
        pct_ro        = 'Save failed: config.ini not writable',
        lang_saved    = 'Language switched: %s (saved, kept after restart)',
        dash          = '-',
        vols_dash     = 'Vol: -', lowpct_dash = 'Low-HP threshold: -',
    },
}
local function L(k, ...)
    local t = STR[opt.lang] or STR.zh
    local s = t[k] or STR.zh[k] or k
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
end

--------------------------------------------------
-- 路径：Scripts -> CustomBGM -> Mods -> ue4ss -> platform\steam
-- 音乐目录 = platform\steam\PBZMusic
--------------------------------------------------
local function joinSep(p) return p:gsub('[/\\]+$', '') .. '\\' end
local PBZDir  = CFG.parent(joinSep(DIR), 4)          -- ...\platform\steam\
local MEDIA   = CFG.fileExists(PBZDir .. 'PBZMusic') and (PBZDir .. 'PBZMusic\\') or (PBZDir .. 'PBZMusic\\')

local IPC_STATE = MEDIA .. 'state.txt'
local IPC_BEAT  = MEDIA .. 'heartbeat.txt'

--------------------------------------------------
-- 播放器曲目表：PBZMusic\player.ini（每 5 秒重读，换歌即时生效于新触发）
--------------------------------------------------
local mediaIni, mediaIniAt = {}, 0
local function refreshMediaIni()
    mediaIni = CFG.loadIni(MEDIA .. 'player.ini')
    mediaIniAt = os.time()
end
refreshMediaIni()

local files = { combat = 'combat.mp3', low = 'low.mp3', death = 'death.mp3', boss = nil }
local function syncFilesFromIni()
    local f = mediaIni.files or mediaIni
    files.combat = f.combat or 'combat.mp3'
    files.low    = f.low    or 'low.mp3'
    files.death  = f.death  or 'death.mp3'
    files.boss   = f.boss   -- 空/未配置 = 决战曲沿用低血曲（mediaFile 内回落）
end
syncFilesFromIni()

local function mediaFile(key)
    local v = files[key]
    if not v or v == '' then
        -- 决战曲未单独配置时先用低血曲的歌（v0.6.4 过渡约定）
        if key == 'boss' then v = files.low end
        if not v or v == '' then return nil end
    end
    if v:match('^[A-Za-z]:') or v:sub(1, 2) == '\\\\' or v:sub(1, 1) == '/' then
        return v -- 绝对路径
    end
    return MEDIA .. v
end

--------------------------------------------------
-- 引擎侧工具
--------------------------------------------------
local KSL = nil
local function ksl()
    if KSL and KSL:IsValid() then return KSL end
    KSL = StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
    return KSL
end

local function openPathURL(path)
    local p = path:gsub('\\', '/'):gsub(' ', '%%20')
    local obj = ksl()
    if obj then
        local ok, err = pcall(function() obj:LaunchURL('file:///' .. p) end)
        if ok then return true end
        log('LaunchURL 失败：' .. tostring(err))
    else
        log('KismetSystemLibrary 未就绪，无法拉起')
    end
    log('请手动打开：' .. path)
    return false
end

--------------------------------------------------
-- 哨兵读取（全部只读）
--------------------------------------------------
local msCache, msWorld = nil, -1
local function getMusic(worldAddr)
    if msCache and msCache:IsValid() and msWorld == worldAddr then return msCache end
    msCache, msWorld = nil, worldAddr
    for _, m in ipairs(FindAllOf('MusicSubsystem') or {}) do
        if m and m:IsValid() and m:GetWorld():GetAddress() == worldAddr then
            msCache = m
            break
        end
    end
    return msCache
end

-- 返回 战斗中(bool)、特殊敌人数(Boss 雏形指标)、ms 引用
local function battleInfo(worldAddr)
    local ms = getMusic(worldAddr)
    if not ms then return nil, nil, nil end
    local okB, battle = pcall(function() return ms.bInBattle end)
    if okB and battle ~= nil then
        return battle == true, specialCountSafe(ms), ms
    end
    local okC, cnt = pcall(function() return #ms.EngagedEnemies end)
    if okC and cnt ~= nil then
        return cnt > 0, specialCountSafe(ms), ms
    end
    return nil, nil, ms
end

function specialCountSafe(ms)
    if not ms then return nil end
    local ok, n = pcall(function() return #ms.EngagedSpecialEnemies end)
    if ok then return n end
    return nil
end

local seenPawnClass = {}
local function getPawn()
    -- 不再硬筛 '/Script/ProjectPBZ.PBZCharacter'（玩家角色类名未必与木桩同名）
    -- 任意主控 Pawn 都用于血量探测，真实类名写日志一次以便诊断
    local pcs = {}
    if UEHelpers and UEHelpers.GetPlayerController then
        local ok, pc = pcall(UEHelpers.GetPlayerController)
        if ok and pc and pc:IsValid() then pcs[#pcs + 1] = pc end
    end
    for _, pc in ipairs(FindAllOf('PlayerController') or {}) do
        if pc and pc:IsValid() then pcs[#pcs + 1] = pc end
    end
    for _, pc in ipairs(pcs) do
        if pc then
            local okP, p = pcall(function() return pc.Pawn end)
            if okP and p and p:IsValid() then
                local okC, cn = pcall(function() return p:GetClass():GetFName():ToString() end)
                local name = (okC and cn) or '?'
                if not seenPawnClass[name] then
                    seenPawnClass[name] = true
                    log('玩家 Pawn 类：' .. name)
                end
                return p
            end
        end
    end
    return nil
end

-- 返回 hp, max, min, ok（多路径探测，第一次成功路径写日志）
local hpReadPath, hpWarnedOnce = nil, false
local HP_PATHS = {
    { 'AttributeSetBase',  'AttributeSetBase' },
    { 'AttributeSet Base', 'AttributeSetBase(空格)' },
    { 'AttributeSet',      'AttributeSet' },
}
local function hpInfo(pawn)
    if not pawn then return nil, nil, nil, false end
    for _, def in ipairs(HP_PATHS) do
        local ok, hp, hmax, hmin = pcall(function()
            local at = pawn[def[1]]
            return at.Health.CurrentValue, at.Health_Max.CurrentValue, at.Health_Min.CurrentValue
        end)
        if ok and type(hp) == 'number' then
            if not hpReadPath then
                hpReadPath = def[2]
                log('血量读取 OK：' .. def[2])
            end
            local lo = (hmin and hmin > 0) and hmin or 1.0
            return hp, hmax, lo, true
        end
    end
    if not hpWarnedOnce then
        hpWarnedOnce = true
        log('血量读取失败：AttributeSet 族路径全败（详见 UE4SS.log，菜单"生命"将显示 -）')
    end
    return nil, nil, nil, false
end

local function playerAlive()
    local f = io.open(MEDIA .. 'alive.txt', 'rb')
    if not f then return false end
    local c = f:read('*l')
    f:close()
    local n = tonumber(c)
    -- 只认合理区间的 unix epoch 秒；旧版播放器误写过 .NET Ticks（≈6.4e11，远超区间），
    -- 与 os.time() 相减恒为负导致永远"判活"，播放器死了也永不重建（11-04 踩）
    return n ~= nil and n > 1000000000 and n < 5000000000 and (os.time() - n) <= 2
end

--------------------------------------------------
-- 运行时状态与 IPC
--------------------------------------------------
local sw = { master = opt.master, combat = opt.combat, low = opt.low, death = opt.death, boss = opt.boss, lowSticky = opt.lowSticky }
local latched = { dead = false, low = false, boss = false }
local shard = { pawnAddr = nil, worldAddr = -1 }
local lastWritten = nil
local pendingReload = false
local pendingVol = nil      -- 菜单改音量后待写入 state.txt 的总音量（0~100）
local launchTries = 0
local lastBattle = nil      -- 上一 tick 的战斗态，用于识别"战斗结束"沿
local bossMiss = 0          -- 决战锁存期间连续读不到 Boss 血量的 tick 数（>100≈20s 判失联）

local volOverride = nil
do
    local f = io.open(MEDIA .. 'volume_override.txt', 'r')
    if f then
        volOverride = tonumber(f:read('*l') or '')
        f:close()
        if volOverride and (volOverride < 0 or volOverride > 100) then volOverride = nil end
    end
end

local view = {
    state = 'stop',
    hp = nil, hmax = nil,
    battle = nil, special = nil,
    bhp = nil, bmax = nil,
    msReady = nil, hpReady = nil,
    playerAlive = playerAlive(),
    err = nil,
    volGlobal = volOverride or 100,
}

--------------------------------------------------
-- Boss（特殊敌人）血量侦查（v0.6.4 决战曲用）
-- 策略：MusicSubsystem.EngagedSpecialEnemies 数组成员直接试读血量；
--      成员若是 Pawn 读自身 AttributeSet，不是则试成员 .Pawn
-- 读法/类名每次会话首次成功各写一条日志，实战一场 Boss 即可校准
--------------------------------------------------
local bossArrLogged, bossSeenClass = false, nil
local function eachEngagedSpecial(ms)
    local list = {}
    local ok, arr = pcall(function() return ms.EngagedSpecialEnemies end)
    if not ok or arr == nil then
        if not bossArrLogged then
            bossArrLogged = true
            log('Boss 侦查：EngagedSpecialEnemies 属性不可读（决战曲会失灵，需改兜底扫描）')
        end
        return list
    end
    local okN, n = pcall(function() return #arr end)
    n = (okN and type(n) == 'number') and n or 0
    for i = 1, math.min(n, 8) do
        local okE, e = pcall(function() return arr[i] end)
        if okE and e then list[#list + 1] = e end
    end
    if not bossArrLogged then
        bossArrLogged = true
        log('Boss 侦查：EngagedSpecialEnemies 可读，当前数量=' .. tostring(n))
    end
    return list
end

-- 返回 hp, hmax, hmin, ok（第一个可读血量的 Boss 成员；ok=false 表示本轮没读到）
local function bossHpInfo(world)
    if view.battle ~= true and not latched.boss then return nil, nil, nil, false end
    local ms = getMusic(world)
    if not ms then return nil, nil, nil, false end
    for _, e in ipairs(eachEngagedSpecial(ms)) do
        local cok, cn = pcall(function() return e:GetClass():GetFName():ToString() end)
        local cls = (cok and cn) or '?'
        if cls ~= bossSeenClass then
            bossSeenClass = cls
            log('Boss 成员类名：' .. cls)
        end
        local hp, hmax, hmin, okHp = hpInfo(e)
        local p = e
        if not okHp then
            local okP, p2 = pcall(function() return e.Pawn end)
            if okP and p2 and p2:IsValid() then
                p = p2
                hp, hmax, hmin, okHp = hpInfo(p2)
            end
        end
        if okHp and p and p:IsValid() then
            return hp, hmax, hmin, true
        end
    end
    return nil, nil, nil, false
end

local existCache, existAt = {}, 0
local function filesStatus()
    local now = os.time()
    if now - existAt >= 2 then
        existAt = now
        existCache = {
            combat = CFG.fileExists(mediaFile('combat')),
            low    = CFG.fileExists(mediaFile('low')),
            death  = CFG.fileExists(mediaFile('death')),
            boss   = CFG.fileExists(mediaFile('boss')),
        }
    end
    return existCache
end

local lastBeat = 0
local function beat()
    local now = os.time()
    if now - lastBeat < 1 then return end
    lastBeat = now
    local f = io.open(IPC_BEAT, 'w')
    if f then f:write(tostring(now)); f:close() end
end

local function writeIpc(content, force)
    if not force and lastWritten == content then return end
    local f = io.open(IPC_STATE, 'w')
    if f then
        f:write(content)
        f:close()
        lastWritten = content
    end
end

local previewHoldUntil = 0 -- 试播写入后 2 秒内哨兵不得覆盖 state.txt（否则播放器读不到 preview 行）
local deathHoldUntil = 0   -- 复活/读档后死亡曲再多播 DeathHoldSeconds 秒，期间哨兵不写 state
local openHoldUntil = 0    -- open= 行写盘后 4 秒保护窗（同 preview，防被秒覆盖）
local lastPreviewPath = nil

local function pushState(s)
    if os.clock() < previewHoldUntil then return end
    if os.clock() < deathHoldUntil then return end
    if os.clock() < openHoldUntil then return end
    local content = 'state=' .. s .. '\n'
    -- 夜班 A2 保险：连续两次死亡间 state 行从未离开 death（快速复活后再死）时，
    -- 播放器按行内容去重不会把新死亡当"新事件"重播 → 先写一拍 stop，
    -- 下一拍再写 death 形成变化沿，死亡曲才能重起。
    -- （放在 pendingVol/pendingReload 之前：stop 拍不消费待写项，留给下一拍）
    if s == 'death' and lastWritten == content then
        writeIpc('state=stop\n')
        return
    end
    if pendingVol then
        content = content .. 'volume=' .. pendingVol .. '\n'
        pendingVol = nil
    end
    if pendingReload then
        content = content .. 'reload=1\n'
        pendingReload = false
    end
    writeIpc(content)
end

-- 菜单总音量（实时写 IPC；"保存音量"落盘 volume_override.txt 供下次启动优先读取）
local function adjustVol(delta)
    view.volGlobal = math.max(0, math.min(100, view.volGlobal + delta))
    pendingVol = view.volGlobal
    log('总音量 -> ' .. view.volGlobal .. '%')
end

local function saveVol()
    local f = io.open(MEDIA .. 'volume_override.txt', 'w')
    if f then
        f:write(tostring(view.volGlobal))
        f:close()
        log('音量设置已保存：' .. view.volGlobal .. '%')
    else
        log('保存音量失败：PBZMusic 目录不可写')
    end
end

-- F7 内闪示一条提示（borrow err 标签行），不弹窗不切游戏也能确认操作成功
local msgUntil = 0
local function flashMsg(s)
    view.msg = s
    msgUntil = os.clock() + 4
    log(s)
end

-- 低血阈值：F7 ±5 调节 + 写回 config.ini 持久化（v0.6.4）
local function adjustLowPct(delta)
    opt.lowPct = math.max(5, math.min(90, opt.lowPct + delta))
    log('低血阈值（会话内）-> ' .. opt.lowPct .. '%（记得点保存持久化）')
end

local function saveLowPct()
    local path = MODROOT .. 'config.ini'
    local f = io.open(path, 'r')
    if not f then flashMsg(L('pct_missing')) return end
    local body = f:read('*a')
    f:close()
    local newBody = body:gsub('([Ll]ow[Hh]ealth[Pp]ercent%s*=%s*)%-?%d+', '%1' .. tostring(opt.lowPct))
    if newBody == body then
        flashMsg(L('pct_noline'))
        return
    end
    local w = io.open(path, 'w')
    if w then
        w:write(newBody)
        w:close()
        flashMsg(L('pct_saved', opt.lowPct))
    else
        flashMsg(L('pct_ro'))
    end
end

-- 面板语言：F7「语言」按钮即时切换 + 写回 config.ini [Display] Lang 持久化（v0.6.6）
local function saveLang()
    local path = MODROOT .. 'config.ini'
    local f = io.open(path, 'r')
    if not f then
        -- config.ini 缺失（不正常，但兜底）：直接重建最小 [Display] 段
        local w = io.open(path, 'w')
        if w then w:write('[Display]\nLang = ' .. opt.lang .. '\n'); w:close() end
        return
    end
    local body = f:read('*a')
    f:close()
    local newBody = body:gsub('([Ll]ang%s*=%s*)%w+', '%1' .. opt.lang)
    if newBody == body then
        newBody = body .. '\n[Display]\nLang = ' .. opt.lang .. '\n'
    end
    local w = io.open(path, 'w')
    if w then
        w:write(newBody)
        w:close()
    end
end

local function toggleLang()
    opt.lang = (opt.lang == 'zh') and 'en' or 'zh'
    saveLang()
    -- 面板标题在 Register 时固定，运行期切换下次重启后标题跟随
    flashMsg(L('lang_saved', opt.lang == 'zh' and '中文' or 'English'))
    log('界面语言 -> ' .. opt.lang .. '（已写回 config.ini）')
end

local launchCooldown = 0
local function launchPlayer()
    if playerAlive() then return end
    local now = os.time()
    if now < launchCooldown then return end
    launchCooldown = now + 5 -- 每 5 秒自检一次，僵死即重建（上限游览：只对 1~3 次和之后每 12 次写日志）
    launchTries = launchTries + 1
    if launchTries <= 3 or launchTries % 12 == 0 then
        log('尝试拉起播放器（第 ' .. launchTries .. ' 次）…')
    end
    openPathURL(MEDIA .. 'PBZPlayer.exe')
end

--------------------------------------------------
-- 状态机
--------------------------------------------------
local function computeState(hpReady)
    if not sw.master then return 'stop' end
    if latched.dead then
        return sw.death and 'death' or 'stop'
    end
    if latched.boss then
        -- 决战优先于低血/战斗；决战开关关了就按普通战斗逻辑走
        return sw.boss and 'boss' or (sw.combat and 'combat' or 'stop')
    end
    if latched.low then
        if sw.low then return 'low' end
        if view.battle and sw.combat then return 'combat' end
        return 'stop'
    end
    if view.battle then return sw.combat and 'combat' or 'stop' end
    return 'explore'
end

local function coreTick()
    -- 曲目表周期刷新
    if os.time() - mediaIniAt >= 5 then
        refreshMediaIni()
        syncFilesFromIni()
    end

    -- 玩家与世界（复位死亡/低血锁存时若曾处死亡态，则给死亡曲一个延时收尾窗）
    local pawn = getPawn()
    if pawn then
        local a = pawn:GetAddress()
        if a ~= shard.pawnAddr then
            if shard.pawnAddr and latched.dead then
                deathHoldUntil = os.clock() + opt.deathHold
            end
            shard.pawnAddr = a
            latched.dead, latched.low = false, false
            shard.worldJustChanged = true -- 死亡重生/换 pawn 也算场景变化 → 自动收面板
        end
    else
        shard.pawnAddr = nil
    end
    local world = -1
    if pawn then
        local okW, w = pcall(function() return pawn:GetWorld():GetAddress() end)
        if okW then world = w end
    end
    if world ~= shard.worldAddr then
        if shard.worldAddr ~= -1 and latched.dead then
            deathHoldUntil = os.clock() + opt.deathHold
        end
        shard.worldAddr = world
        latched.dead, latched.low, latched.boss = false, false, false -- 载入新世界：Boss 已不在
        bossMiss = 0
        shard.worldJustChanged = true -- 供 tick 自动收面板（吞输入的壳不跨场景）
        msCache, msWorld = nil, -1
    end

    -- 战斗状态
    local battle, special, ms = battleInfo(world)
    if ms == nil then shard.msReady = false
    else shard.msReady = true end
    view.battle = battle
    view.special = special

    -- 低血粘滞：战斗结束（true→false 沿）即解除，低血曲随战斗结束而停
    if sw.lowSticky and latched.low and lastBattle == true and view.battle == false then
        latched.low = false
    end
    -- 决战锁存：战斗结束沿一并解除
    if latched.boss and lastBattle == true and view.battle == false then
        latched.boss = false
    end
    lastBattle = view.battle

    -- Boss 血量与决战锁存（v0.6.4，锁存式：≤25% 触发，播到 Boss 死/脱战）
    local bhp, bmax, bmin, bok = bossHpInfo(world)
    view.bhp, view.bmax = bhp, bmax
    if view.battle ~= true and not latched.boss then
        view.bhp, view.bmax = nil, nil -- 非交战/非决战时菜单 Boss 行显示"未发现"
    end
    if latched.boss then
        if bok and bhp and bmin and bhp <= bmin then
            latched.boss = false -- Boss 判死，回正常状态
        elseif bok then
            bossMiss = 0
        else
            bossMiss = bossMiss + 1
            if bossMiss > 100 then
                latched.boss = false
                log('Boss 失联约 20s，决战锁存解除')
            end
        end
    elseif sw.boss and bok and bhp and bmax and bmax > 0 and bhp > bmin then
        if bhp <= bmax * (opt.bossPct / 100) then
            latched.boss = true
        end
    end

    -- 血量与触发锁存
    local hp, hmax, hmin, okHp = hpInfo(pawn)
    view.hp, view.hmax, view.hpReady = hp, hmax, okHp
    if pawn and okHp and hmax and hmax > 0 then
        if hp <= hmin then
            latched.dead = true
            latched.low = false
            deathHoldUntil = 0 -- 新死亡优先：清掉上一轮复活留下的延播保护窗（夜班 A2 保险）
        elseif latched.dead and hp > hmin then
            latched.dead = false -- 复活/读档复位
            deathHoldUntil = os.clock() + opt.deathHold
        end
        if not latched.dead and not latched.boss then
            local ratio = hp / hmax
            -- 决战锁存期间不触发低血曲（需求：Boss 阶段低血曲让位）
            if not latched.low and ratio < (opt.lowPct / 100) then
                latched.low = true
            elseif latched.low and ratio > ((opt.lowPct + opt.lowExitPct) / 100) then
                -- 粘滞模式：战斗进行中回血不解除，拖到战斗结束（上面的结束沿）再停
                if not (sw.lowSticky and view.battle) then
                    latched.low = false
                end
            end
        end
    else
        if latched.dead then deathHoldUntil = os.clock() + opt.deathHold end
        latched.dead, latched.low = false, false -- 场景加载中不误触发
    end

    local s = computeState(okHp)
    if view.state ~= s then
        -- 状态切换日志：排障用，默认关（config.ini [Debug] StateLog=1 开启）
        if opt.debug then
            local battleStr = tostring(view.battle)
            local hpStr = '不可读'
            if hpReady then hpStr = string.format('%.0f/%.0f', hp or 0, hmax or 0) end
            local reason = '探索/复位'
            if latched.dead then reason = '死亡'
            elseif latched.low then reason = '低血锁存'
            elseif battleStr == 'true' then reason = '战斗中' end
            log(string.format('状态切换: %s -> %s（%s，battle=%s，hp=%s，开关 combat=%s low=%s death=%s）',
                view.state, s, reason, battleStr, hpStr, tostring(sw.combat), tostring(sw.low), tostring(sw.death)))
        end
        view.state = s
    end
    pushState(s)

    -- 持续自检并拉起播放进程（僵死即重建）
    launchPlayer()
end

local function tick()
    local ok, err = pcall(coreTick)
    if not ok then
        view.err = tostring(err)
        log('tick error: ' .. tostring(err))
    else
        view.err = nil
    end
    -- 换世界自动收面板（AutoCloseShellOnWorldChange 在 ui 初始化后定义，运行期全局可见）
    if shard.worldJustChanged then
        shard.worldJustChanged = false
        if AutoCloseShellOnWorldChange then AutoCloseShellOnWorldChange() end
    end
    -- 输入残留看门狗（每 tick 检查共享输入状态不一致）
    if InputResidueWatchdog then InputResidueWatchdog() end
    beat() -- 无论哨兵成败，游戏活着就续心跳
    updateMenu()
    return false
end

--------------------------------------------------
-- F8 菜单（ModMenu vendor）
--------------------------------------------------
-- ModMenu bundle 内部多处 require('PBZTrainingDummy.UEHelpers')
-- （沿用 #413 私有依赖约定：preload 本 mod 自带 copy，不动 shared 目录）
package.preload['PBZTrainingDummy.UEHelpers'] = function()
    return dofile(DIR .. 'vendor/UEHelpers.lua')
end
local okMenu, ui = pcall(dofile, DIR .. 'vendor/ModMenu.lua')
if not okMenu then
    log('ModMenu 加载失败：' .. tostring(ui) .. '；我将只写状态文件，不支持菜单')
    ui = nil
end

function updateMenu()
    if not ui or not ui.IsOpen or not ui.IsOpen() then return end
    local names = {
        explore = L('st_explore'), combat = L('st_combat'), low = L('st_low'),
        death = L('st_death'), boss = L('st_boss'), stop = L('st_stop'), appear = L('st_explore'),
    }
    local files = filesStatus()
    local mark = function(on) return on and '✓' or '×' end
    ui.SetLabel('custombgm', 'status', L('lb_status') .. (names[view.state] or view.state))
    ui.SetLabel('custombgm', 'hp', view.hpReady and L('lb_hp_fmt', view.hp, view.hmax) or L('hp_dash'))
    ui.SetLabel('custombgm', 'src', shard.msReady and
        L('src_ok', tostring(view.battle), tostring(view.special)) or L('src_na'))
    view.playerAlive = playerAlive()
    ui.SetLabel('custombgm', 'player', view.playerAlive and L('player_ok') or L('player_na'))
    ui.SetLabel('custombgm', 'files', L('files_fmt',
        mark(files.combat), mark(files.low), mark(files.death), mark(files.boss)))
    -- 正在播放
    local nowText = L('now_none')
    if lastPreviewPath then
        nowText = (lastPreviewPath:match('[^\\/]+$') or lastPreviewPath) .. L('preview_tag')
    elseif view.state == 'boss' or view.state == 'combat' or view.state == 'low' or view.state == 'death' then
        local p = mediaFile(view.state)
        if p then nowText = (p:match('[^\\/]+$') or p) end
    end
    ui.SetLabel('custombgm', 'now', L('lb_now') .. nowText)
    -- Boss 状态行（决战锁存/交战中血量/未发现）
    local bossText
    if latched.boss and view.bmax then
        bossText = L('boss_duel', view.bhp or 0, view.bmax)
    elseif view.bhp and view.bmax then
        bossText = L('boss_fight', view.bhp, view.bmax, opt.bossPct)
    else
        bossText = L('boss_na')
    end
    ui.SetLabel('custombgm', 'bossline', bossText)
    ui.SetLabel('custombgm', 'lowpct', L('lowpct_fmt', opt.lowPct))
    -- 音量显示（每类来自 player.ini [volumes]，总音量为菜单实时值）
    local vols = mediaIni.volumes or {}
    ui.SetLabel('custombgm', 'vols', L('vols_fmt',
        tonumber(vols.combat) or 80, tonumber(vols.low) or 90,
        tonumber(vols.death) or 100, tonumber(vols.boss) or tonumber(vols.low) or 90, view.volGlobal))
    if os.clock() < msgUntil and view.msg then
        ui.SetLabel('custombgm', 'err', L('lb_tip') .. view.msg)
    elseif view.err then
        ui.SetLabel('custombgm', 'err', L('lb_warn') .. tostring(view.err))
    else
        ui.SetLabel('custombgm', 'err', ' ')
    end
    ui.SetButtonLabel('custombgm', 'master', sw.master and L('master_on') or L('master_off'))
    ui.SetButtonLabel('custombgm', 'combat', sw.combat and L('combat_on') or L('combat_off'))
    ui.SetButtonLabel('custombgm', 'low', sw.low and L('low_on') or L('low_off'))
    ui.SetButtonLabel('custombgm', 'death', sw.death and L('death_on') or L('death_off'))
    ui.SetButtonLabel('custombgm', 'lowsticky', sw.lowSticky and L('sticky_on') or L('sticky_off'))
    ui.SetButtonLabel('custombgm', 'boss', sw.boss and L('boss_on') or L('boss_off'))
    -- 其余按钮文案随语言即时刷新（语言切换不用重启）
    ui.SetButtonLabel('custombgm', 'pv_combat', L('pv', L('pv_combat')))
    ui.SetButtonLabel('custombgm', 'pv_low',    L('pv', L('pv_low')))
    ui.SetButtonLabel('custombgm', 'pv_death',  L('pv', L('pv_death')))
    ui.SetButtonLabel('custombgm', 'pv_boss',   L('pv', L('pv_boss')))
    ui.SetButtonLabel('custombgm', 'vol_down', L('vol_down'))
    ui.SetButtonLabel('custombgm', 'vol_up',   L('vol_up'))
    ui.SetButtonLabel('custombgm', 'vol_save', L('vol_save'))
    ui.SetButtonLabel('custombgm', 'pct_down', L('pct_down'))
    ui.SetButtonLabel('custombgm', 'pct_up',   L('pct_up'))
    ui.SetButtonLabel('custombgm', 'pct_save', L('pct_save'))
    ui.SetButtonLabel('custombgm', 'fixinput', L('fixinput'))
    ui.SetButtonLabel('custombgm', 'stopall',  L('stopall'))
    ui.SetButtonLabel('custombgm', 'open_media', L('open_media'))
    ui.SetButtonLabel('custombgm', 'reload_ini', L('reload_ini'))
    ui.SetButtonLabel('custombgm', 'close',    L('close'))
    ui.SetButtonLabel('custombgm', 'lang',     L('btn_lang'))
end

local function previewFile(key)
    local p = mediaFile(key)
    if not p then
        flashMsg(L('pv_fail_unset', L('pv_' .. key)))
        log('试播失败：未配置 ' .. tostring(key))
        return
    end
    -- 文件夹（歌单池）也允许试播：播放器侧会随机抽一首
    local looksDir = p:sub(-1) == '\\' or p:sub(-1) == '/'
    if not looksDir and not CFG.fileExists(p) then
        flashMsg(L('pv_fail', p))
        log('试播失败：找不到 ' .. tostring(p))
        return
    end
    local content = 'state=' .. view.state .. '\npreview=' .. p .. '\n'
    -- force：连点同一首试播也必须落盘，writeIpc 的去重会吞掉重复请求
    writeIpc(content, true)
    previewHoldUntil = os.clock() + 2.0
    lastPreviewPath = p
    flashMsg(L('pv_ok', p))
    log('已请求试播：' .. p)
end

-- 打开音乐文件夹：走 IPC 交给播放器进程开资源管理器。
-- 11-05 踩：此前直接 LaunchURL(file:///文件夹) 会卡死游戏线程 → 改由播放器代开
local function openMusicFolder()
    writeIpc('state=' .. view.state .. '\nopen=' .. MEDIA .. '\n', true)
    openHoldUntil = os.clock() + 4.0
    if not playerAlive() then launchPlayer() end
    flashMsg(L('open_req'))
end

if ui then
    local binding = Key[opt.menuKey] or Key.F7
    local keyHint = opt.menuKey or 'F7'
    ui.Init({
        title = 'CustomBGM', instanceId = 'CustomBGM',
        key = binding, keyHint = keyHint,
        dock = 'right', theme = 'dark', ignoreLook = true,
        showClose = false, widthFrac = 0.24, topFrac = 0.10, bottomFrac = 0.12,
        canOpen = function() return true end,
    })
    ui.Register({ id = 'custombgm', title = L('panel_title'), items = {
        { type = 'label', id = 'status', label = L('lb_status') .. L('dash') },
        { type = 'label', id = 'hp',     label = L('hp_dash') },
        { type = 'label', id = 'src',    label = 'MusicSubsystem: -' },
        { type = 'label', id = 'player', label = L('player_ok') },
        { type = 'label', id = 'now',    label = L('lb_now') .. L('dash') },
        { type = 'label', id = 'files',  label = L('files_fmt', '-', '-', '-', '-') },
        { type = 'label', id = 'vols',   label = L('vols_dash') },
        { type = 'label', id = 'lowpct', label = L('lowpct_dash') },
        { type = 'label', id = 'bossline', label = L('boss_na') },
        { type = 'label', id = 'err',    label = ' ' },
        { type = 'separator' },
        { type = 'button', id = 'master', label = L('master_on'), onClick = function() sw.master = not sw.master; log('开关: 总开关 = ' .. tostring(sw.master)) end },
        { type = 'button', id = 'combat', label = L('combat_on'), onClick = function() sw.combat = not sw.combat; log('开关: 战斗曲 = ' .. tostring(sw.combat)) end },
        { type = 'button', id = 'low',    label = L('low_on'), onClick = function() sw.low = not sw.low; log('开关: 低血曲 = ' .. tostring(sw.low)) end },
        { type = 'button', id = 'death',  label = L('death_on'), onClick = function() sw.death = not sw.death; log('开关: 死亡曲 = ' .. tostring(sw.death)) end },
        { type = 'button', id = 'lowsticky', label = L('sticky_on'), onClick = function() sw.lowSticky = not sw.lowSticky; log('开关: 低血粘滞(播到战斗结束) = ' .. tostring(sw.lowSticky)) end },
        { type = 'button', id = 'boss', label = L('boss_on'), onClick = function() sw.boss = not sw.boss; log('开关: 决战曲 = ' .. tostring(sw.boss)) end },
        { type = 'separator' },
        { type = 'button', id = 'pv_combat', label = L('pv', L('pv_combat')), onClick = function() previewFile('combat') end },
        { type = 'button', id = 'pv_low',    label = L('pv', L('pv_low')), onClick = function() previewFile('low') end },
        { type = 'button', id = 'pv_death',  label = L('pv', L('pv_death')), onClick = function() previewFile('death') end },
        { type = 'button', id = 'pv_boss',   label = L('pv', L('pv_boss')), onClick = function() previewFile('boss') end },
        { type = 'separator' },
        { type = 'button', id = 'vol_down', label = L('vol_down'), onClick = function() adjustVol(-10) end },
        { type = 'button', id = 'vol_up',   label = L('vol_up'), onClick = function() adjustVol(10) end },
        { type = 'button', id = 'vol_save', label = L('vol_save'), onClick = function() saveVol() end },
        { type = 'button', id = 'pct_down', label = L('pct_down'), onClick = function() adjustLowPct(-5) end },
        { type = 'button', id = 'pct_up',   label = L('pct_up'), onClick = function() adjustLowPct(5) end },
        { type = 'button', id = 'pct_save', label = L('pct_save'), onClick = function() saveLowPct() end },
        { type = 'button', id = 'fixinput', label = L('fixinput'), onClick = function()
            -- 手柄/键盘被别的同框架 mod 卡死时的手动逃生口：
            -- 先收自己的壳，再无条件把输入模式拉回游戏层
            pcall(function() ui.Close() end)
            pcall(function()
                local im = require('PBZDummyMenu.core.inputmode')
                if im and im.SetActive then im.SetActive(false, 0) end
            end)
            log('已强制恢复输入模式（修复输入模式按钮）')
        end },
        { type = 'separator' },
        { type = 'button', id = 'stopall', label = L('stopall'), onClick = function() writeIpc('state=stop\n') end },
        { type = 'button', id = 'open_media', label = L('open_media'), onClick = function() openMusicFolder() end },
        { type = 'button', id = 'reload_ini', label = L('reload_ini'), onClick = function() pendingReload = true; mediaIniAt = 0 end },
        { type = 'button', id = 'lang', label = L('btn_lang'), onClick = function() toggleLang() end },
        { type = 'button', id = 'close', label = L('close'), onClick = function() ui.Close() end },
    } })
    ui.OnOpen(updateMenu)
    RegisterKeyBind(Key.ESCAPE, function()
        ExecuteInGameThread(function() if ui.IsOpen() then ui.Close() end end)
    end)
end

-- 换世界自动收面板：面板开着会把输入切到 UI 层（手柄 A 等被壳吞掉），
-- 若开着跨场景/跨 PC 重建，关闭时的恢复可能落在错误的 PlayerController 上。
-- （全局函数约定同 updateMenu：定义在 ui 之后，tick 运行期调用）
function AutoCloseShellOnWorldChange()
    if not ui or not ui.IsOpen or not ui.IsOpen() then return end
    log('检测到切换场景且面板开着 → 自动关闭，防止输入卡在 UI 层')
    pcall(function() ui.Close() end)
end

-- 输入残留看门狗（彻底解：同框架多 mod 共享 INPUT_SAVED/OPEN_COUNT，
-- BossMind 等别的壳没清干净时，正常状态会被"卡在 UI 层"污染 → 手柄 A 等失灵）。
-- 判据（不一致残留，无壳真开着）：本面板关闭 && INPUT_SAVED=true && OPEN_COUNT=0
-- 持续 8s → 强制 SetActive(false,0) 恢复。若 OPEN_COUNT>0 = 别的壳真开着，不碰、只记日志。
local mmShared, mmInputMode = nil, nil
local inputStuckSince, inputNoteAt = nil, 0
local function bindModMenuInternals()
    if mmShared and mmInputMode then return true end
    pcall(function() mmShared = require('PBZDummyMenu.core.shared') end)
    pcall(function() mmInputMode = require('PBZDummyMenu.core.inputmode') end)
    return (mmShared and mmInputMode) and true or false
end
function InputResidueWatchdog()
    if not ui or not ui.IsOpen or ui.IsOpen() then inputStuckSince = nil; return end
    if not bindModMenuInternals() then return end
    local saved, openN = false, -1
    pcall(function() saved = mmShared.Get(mmShared.INPUT_SAVED) == true end)
    pcall(function() openN = mmShared.Get(mmShared.OPEN_COUNT) or 0 end)
    if saved and openN == 0 then
        inputStuckSince = inputStuckSince or os.clock()
        if os.clock() - inputStuckSince >= 8 then
            pcall(function() mmInputMode.SetActive(false, 0) end)
            log('input-watchdog: INPUT_SAVED 残留且 OPEN_COUNT=0（同框架 mod 壳未清干净）→ 强制恢复输入模式')
            inputStuckSince = nil
        end
    elseif saved then
        -- 别的壳真开着（多半 BossMind 的 F8 面板）：不碰；每 30s 记一条状态供排障
        if os.time() - inputNoteAt >= 30 then
            inputNoteAt = os.time()
            log('input-watchdog: 检测到其他面板开着（OPEN_COUNT=' .. tostring(openN) .. '），游戏输入由其接管（手柄确认键此时不响应属预期）')
        end
        inputStuckSince = nil
    else
        inputStuckSince = nil
    end
end

--------------------------------------------------
-- 主循环
--------------------------------------------------
LoopInGameThreadWithDelay(opt.pollMs, tick)
log('loaded v0.6.7！音乐目录：' .. MEDIA .. '；菜单键：' .. opt.menuKey .. '；轮询：' .. opt.pollMs .. 'ms；低血阈值=' .. opt.lowPct .. '%；决战阈值=' .. opt.bossPct .. '%；死亡延时=' .. tostring(opt.deathHold) .. 's；语言=' .. opt.lang)
log('战斗/低血/死亡触发=哨兵只读；音乐=PBZPlayer.exe（PBZMusic 目录）')
