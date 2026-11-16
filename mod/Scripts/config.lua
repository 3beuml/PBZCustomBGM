-- CustomBGM 配置与工具模块（v0.1）
local M = {}

-- 简易 INI 解析：支持 [section]、key = value、# ; 注释、值引号剥离
function M.loadIni(path)
    local t = {}
    local f = io.open(path, 'r')
    if not f then return t end
    local section = t
    for line in f:lines() do
        local s = line:gsub('%s+$', ''):gsub('^%s+', '')
        if s:sub(1, 1) == '[' and s:sub(-1) == ']' then
            local nm = s:sub(2, -2):lower()
            t[nm] = t[nm] or {}
            section = t[nm]
        else
            local k, v = s:match('^([^=#;][^=]-)%s*=%s*(.*)$')
            if k and v then
                k = k:gsub('^%s+', ''):gsub('%s+$', ''):lower()
                v = v:gsub('^%s+', ''):gsub('%s+$', ''):gsub('^"(.*)"$', '%1')
                section[k] = v
            end
        end
    end
    f:close()
    return t
end

-- 上溯 n 层目录（dir 以分隔符结尾）
function M.parent(dir, n)
    local d = dir
    for _ = 1, n do
        d = d:gsub('[/\\][^/\\]+[/\\]$', '/')
    end
    return d
end

function M.fileExists(p)
    if not p then return false end
    local f = io.open(p, 'rb')
    if f then f:close() return true end
    return false
end

-- 字符串->布尔（'1'/'true'/'on' 视为开）
function M.bool(v, default)
    if type(v) == 'string' then
        v = v:lower()
        if v == '1' or v == 'true' or v == 'on' or v == 'yes' then return true end
        if v == '0' or v == 'false' or v == 'off' or v == 'no' then return false end
    end
    return default
end

function M.num(v, default, lo, hi)
    local n = tonumber(v)
    if not n then return default end
    if lo and n < lo then n = lo end
    if hi and n > hi then n = hi end
    return n
end

return M
