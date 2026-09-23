-- typing_stats.lua
-- 打字统计：按天聚合记录汉字数、击键数、上屏次数、退格数、会话均速与 10 秒峰速。
-- =stats 查看今日 / 近7天 / 累计的字数、码长、退格、均速与峰速。
--
-- 均速：两次输入活动间隔不超过 5 秒视为同一会话；会话至少 1 秒、2 个汉字才
-- 进入统计，全部有效会话累计不足 15 秒时不显示。时间优先使用毫秒时钟。
-- 峰速：连续输入满 10 秒结算一个非重叠窗口，保存每日最高字/分；不足 10 秒的
-- 短促输入不参与峰值。单次上屏超过 10 个汉字视作粘贴，不参与速度计算。
--
-- 存储：user_data_dir/typing_stats.txt，每天固定一行（当日行原地累加，非流水日志），
-- 仅保留最近 MAX_DAYS 行。原 8 列格式继续兼容；新版在末尾追加：
--   均速字数、均速毫秒、当日峰速。
-- 写盘策略：内存累计，每 FLUSH_EVERY 次上屏或距上次写盘超 FLUSH_IDLE 秒时落盘；
-- iOS 键盘收起时经 mem_cleaner 结算当前会话、落盘并释放历史缓存。

local mem_cleaner = require("xmjd6.mem_cleaner")

local M = {}

local kNoop = 2

local STATS_FILE = "typing_stats.txt"
local MAX_DAYS = 730
local FLUSH_EVERY = 20 -- 每 N 次上屏落盘一次
local FLUSH_IDLE = 60  -- 距上次落盘超过 N 秒也落盘

local XK_BACKSPACE = 0xff08

local AVERAGE_GAP_MS = 5000
local MINIMUM_AVERAGE_SESSION_MS = 1000
local MINIMUM_AVERAGE_TOTAL_MS = 15000
local PEAK_WINDOW_MS = 10000
local MAX_SPEED_COMMIT_LENGTH = 10

local function new_sample()
    return {
        started = nil,
        last_activity = nil,
        last_commit = nil,
        characters = 0,
    }
end

local function upgrade_runtime_row(row)
    if not row then return end
    if row.average_chars == nil then
        row.average_chars = row.timed_chars or 0
    end
    if row.average_ms == nil then
        row.average_ms = (row.active_secs or 0) * 1000
    end
    if row.peak_speed == nil then row.peak_speed = 0 end
end

local function ensure_runtime_state(st)
    st.average_sample = st.average_sample or new_sample()
    st.peak_sample = st.peak_sample or new_sample()
    -- 重新部署时 Lua 模块会重载，但 _G 状态可能继续存活；就地补齐旧行字段。
    if st.loaded then
        upgrade_runtime_row(st.today)
        for _, row in ipairs(st.history or {}) do upgrade_runtime_row(row) end
    end
end

local function state()
    if not _G.__typing_stats then
        _G.__typing_stats = {
            loaded = false,
            history = nil,
            today = nil,
            dirty = 0,
            last_flush = 0,
            average_sample = new_sample(),
            peak_sample = new_sample(),
        }
    end
    local st = _G.__typing_stats
    ensure_runtime_state(st)
    return st
end

local function stats_path()
    return rime_api.get_user_data_dir() .. "/" .. STATS_FILE
end

local function today_str()
    return os.date("%Y-%m-%d")
end

local function new_row(day)
    -- sent_chars 为旧版“连打字数”，已停止累计，仅为兼容旧文件保留列位。
    return {
        day = day,
        chars = 0,
        keys = 0,
        commits = 0,
        backspaces = 0,
        sent_chars = 0,
        active_secs = 0,
        timed_chars = 0,
        average_chars = 0,
        average_ms = 0,
        peak_speed = 0,
    }
end

local function split_tabs(line)
    local fields = {}
    for value in (line .. "\t"):gmatch("(.-)\t") do
        fields[#fields + 1] = value
    end
    return fields
end

local function load(st)
    if st.loaded then return end
    st.history = {}
    st.today = nil
    local today = today_str()
    local f = io.open(stats_path(), "r")
    if f then
        for line in f:lines() do
            local fields = split_tabs(line)
            local day = fields[1]
            if day and day:match("^%d%d%d%d%-%d%d%-%d%d$") then
                -- 旧 6 列文件无时长列；7 列过渡格式只有时长没有配对计速字数，
                -- 用它算速度会虚高，故从 8 列格式起才承认旧速度数据。
                local timed = tonumber(fields[8])
                local secs = timed and (tonumber(fields[7]) or 0) or 0
                local row = {
                    day = day,
                    chars = tonumber(fields[2]) or 0,
                    keys = tonumber(fields[3]) or 0,
                    commits = tonumber(fields[4]) or 0,
                    backspaces = tonumber(fields[5]) or 0,
                    sent_chars = tonumber(fields[6]) or 0,
                    active_secs = secs,
                    timed_chars = timed or 0,
                    -- 旧 8 列数据只能还原原先的估算均速；无法还原 10 秒峰值。
                    average_chars = tonumber(fields[9]) or timed or 0,
                    average_ms = tonumber(fields[10]) or secs * 1000,
                    peak_speed = tonumber(fields[11]) or 0,
                }
                if day == today then
                    st.today = row
                else
                    st.history[#st.history + 1] = row
                end
            end
        end
        f:close()
    end
    st.today = st.today or new_row(today)
    st.loaded = true
end

local function flush(st)
    if not st.loaded then return end
    while #st.history >= MAX_DAYS do
        table.remove(st.history, 1)
    end
    local f = io.open(stats_path(), "w")
    if not f then return end
    local function write_row(r)
        f:write(r.day, "\t", r.chars, "\t", r.keys, "\t", r.commits, "\t",
            r.backspaces, "\t", r.sent_chars or 0, "\t", r.active_secs or 0, "\t",
            r.timed_chars or 0, "\t", r.average_chars or 0, "\t",
            r.average_ms or 0, "\t", r.peak_speed or 0, "\n")
    end
    for _, row in ipairs(st.history) do write_row(row) end
    write_row(st.today)
    f:close()
    st.dirty = 0
    st.last_flush = os.time()
end

local function monotonic_ms()
    if rime_api and rime_api.get_time_ms then
        local ok, value = pcall(rime_api.get_time_ms)
        if ok and type(value) == "number" then return math.floor(value) end
    end
    return os.time() * 1000
end

local function reset_sample(sample)
    sample.started = nil
    sample.last_activity = nil
    sample.last_commit = nil
    sample.characters = 0
end

local function start_sample(sample, timestamp_ms)
    sample.started = timestamp_ms
    sample.last_activity = timestamp_ms
    sample.last_commit = nil
    sample.characters = 0
end

local function sample_values(sample, minimum_ms)
    if sample.started == nil or sample.last_commit == nil or sample.characters < 2 then
        return nil
    end
    local milliseconds = sample.last_commit - sample.started
    if milliseconds < minimum_ms then return nil end
    return sample.characters, milliseconds
end

local function finish_average(st)
    local characters, milliseconds = sample_values(
        st.average_sample, MINIMUM_AVERAGE_SESSION_MS)
    reset_sample(st.average_sample)
    if not characters then return false end
    st.today.average_chars = (st.today.average_chars or 0) + characters
    st.today.average_ms = (st.today.average_ms or 0) + milliseconds
    return true
end

local function calculate_speed(characters, milliseconds)
    return math.max(0, math.min(2000,
        math.floor(characters * 60000 / milliseconds + 0.5)))
end

local function finish_peak(st)
    local characters, milliseconds = sample_values(st.peak_sample, PEAK_WINDOW_MS)
    reset_sample(st.peak_sample)
    if not characters then return false end
    local speed = calculate_speed(characters, milliseconds)
    st.today.peak_speed = math.max(st.today.peak_speed or 0, speed)
    return true
end

local function finish_samples(st)
    finish_peak(st)
    finish_average(st)
end

local function ensure_sample(st, sample, timestamp_ms, gap_ms, finish)
    if sample.started ~= nil then
        local gap = timestamp_ms - (sample.last_activity or sample.started)
        if gap >= 0 and gap <= gap_ms then return end
        finish(st)
    end
    start_sample(sample, timestamp_ms)
end

local function observe_input_activity(st, timestamp_ms)
    ensure_sample(st, st.average_sample, timestamp_ms, AVERAGE_GAP_MS, finish_average)
    ensure_sample(st, st.peak_sample, timestamp_ms, AVERAGE_GAP_MS, finish_peak)
    st.average_sample.last_activity = timestamp_ms
    st.peak_sample.last_activity = timestamp_ms
end

local function commit_to_speed(st, timestamp_ms, characters)
    ensure_sample(st, st.average_sample, timestamp_ms, AVERAGE_GAP_MS, finish_average)
    ensure_sample(st, st.peak_sample, timestamp_ms, AVERAGE_GAP_MS, finish_peak)

    local average, peak = st.average_sample, st.peak_sample
    average.last_activity = timestamp_ms
    average.last_commit = timestamp_ms
    average.characters = average.characters + characters
    peak.last_activity = timestamp_ms
    peak.last_commit = timestamp_ms
    peak.characters = peak.characters + characters

    if peak.last_commit - peak.started >= PEAK_WINDOW_MS then
        finish_peak(st)
    end
end

-- 跨天前先把旧日样本写进旧日行，再把该行移入历史。
local function roll_day(st)
    local today = today_str()
    if st.today.day ~= today then
        finish_samples(st)
        st.history[#st.history + 1] = st.today
        st.today = new_row(today)
        flush(st)
    end
end

local function count_han(text)
    local n = 0
    local ok = pcall(function()
        for _, cp in utf8.codes(text) do
            if (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF) then
                n = n + 1
            end
        end
    end)
    if not ok then return 0 end
    return n
end

local function is_ascii_mode(env)
    local ctx = env and env.engine and env.engine.context
    if not ctx then return false end
    local ok, value = pcall(function() return ctx:get_option("ascii_mode") end)
    return ok and value == true
end

local function is_speed_activity(code, context)
    local input = context and context.input or ""
    if input:sub(1, 1) == "=" or (input == "" and code == string.byte("=")) then
        return false
    end
    return (code >= 0x41 and code <= 0x5a)
        or (code >= 0x61 and code <= 0x7a)
        or code == 0x3b
        or code == 0x27
        or (code == XK_BACKSPACE and input ~= "")
end

-- 计键 processor：始终 kNoop 透传，必须挂在所有可能吞键的 processor 之前。
function M.processor(key, env)
    if not key or key:release() or key:ctrl() or key:alt() or key:super() then
        return kNoop
    end
    if is_ascii_mode(env) then return kNoop end

    local code = tonumber(key.keycode or 0) or 0
    local is_backspace = (code == XK_BACKSPACE)
    if not is_backspace and not (code >= 0x20 and code < 0x7f) then return kNoop end

    local st = state()
    load(st)
    roll_day(st)

    local context = env and env.engine and env.engine.context
    if is_speed_activity(code, context) then
        observe_input_activity(st, monotonic_ms())
    end

    -- 保留原统计口径：退格单列；其余可见 ASCII 键进入击键数。
    if is_backspace then
        st.today.backspaces = st.today.backspaces + 1
    else
        st.today.keys = st.today.keys + 1
    end
    return kNoop
end

function M.on_commit(ctx)
    local st = state()
    if not st.loaded then return end -- 没打过键就 commit（如外部调用），不计
    local text = ""
    local ok, value = pcall(function() return ctx:get_commit_text() end)
    if ok then text = tostring(value or "") end
    if text == "" then return end

    roll_day(st)
    local han = count_han(text)
    st.today.commits = st.today.commits + 1
    st.today.chars = st.today.chars + han

    local raw_input = ctx.input or ""
    if raw_input:sub(1, 1) ~= "=" and han > 0 then
        if han <= MAX_SPEED_COMMIT_LENGTH then
            commit_to_speed(st, monotonic_ms(), han)
        else
            -- 粘贴/机器生成的大段文本不参与速度，且切断前后两个会话。
            finish_samples(st)
        end
    end

    st.dirty = st.dirty + 1
    if st.dirty >= FLUSH_EVERY or os.time() - (st.last_flush or 0) >= FLUSH_IDLE then
        flush(st)
    end
end

function M.init_processor(env)
    local ctx = env and env.engine and env.engine.context
    if ctx and ctx.commit_notifier then
        env.commit_connection = ctx.commit_notifier:connect(function(c)
            pcall(M.on_commit, c)
        end)
    end
    mem_cleaner.register(function()
        local st = state()
        if st.loaded then finish_samples(st) end
        flush(st)
        st.loaded = false
        st.history = nil
        st.today = nil
        reset_sample(st.average_sample)
        reset_sample(st.peak_sample)
    end)
end

function M.fini_processor(env)
    if env.commit_connection then
        pcall(function() env.commit_connection:disconnect() end)
        env.commit_connection = nil
    end
    local st = state()
    if st.loaded then finish_samples(st) end
    flush(st)
end

local function copy_row(row)
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    return copy
end

-- 报表读取进行中的有效样本，但不结束会话，避免查看 =stats 改变后续计速边界。
local function snapshot_today(st)
    local row = copy_row(st.today)
    local characters, milliseconds = sample_values(
        st.average_sample, MINIMUM_AVERAGE_SESSION_MS)
    if characters then
        row.average_chars = (row.average_chars or 0) + characters
        row.average_ms = (row.average_ms or 0) + milliseconds
    end
    characters, milliseconds = sample_values(st.peak_sample, PEAK_WINDOW_MS)
    if characters then
        row.peak_speed = math.max(row.peak_speed or 0,
            calculate_speed(characters, milliseconds))
    end
    return row
end

local function sum_rows(rows, from_day)
    local acc = new_row("")
    for _, row in ipairs(rows) do
        if not from_day or row.day >= from_day then
            acc.chars = acc.chars + row.chars
            acc.keys = acc.keys + row.keys
            acc.commits = acc.commits + row.commits
            acc.backspaces = acc.backspaces + row.backspaces
            acc.active_secs = acc.active_secs + (row.active_secs or 0)
            acc.timed_chars = acc.timed_chars + (row.timed_chars or 0)
            acc.average_chars = acc.average_chars + (row.average_chars or 0)
            acc.average_ms = acc.average_ms + (row.average_ms or 0)
            acc.peak_speed = math.max(acc.peak_speed or 0, row.peak_speed or 0)
        end
    end
    return acc
end

local function code_len(row)
    if row.chars == 0 then return "-" end
    return string.format("%.2f", row.keys / row.chars)
end

local function average_speed_str(row)
    local milliseconds = row.average_ms or 0
    local characters = row.average_chars or 0
    if milliseconds < MINIMUM_AVERAGE_TOTAL_MS or characters == 0 then return "-" end
    return string.format("约%d字/分", calculate_speed(characters, milliseconds))
end

local function peak_speed_str(row)
    local speed = row.peak_speed or 0
    if speed <= 0 then return "-" end
    return string.format("%d字/分", math.floor(speed + 0.5))
end

function M.translator(input, seg, env)
    if input ~= "=stats" then return end
    local st = state()
    load(st)
    roll_day(st)

    local today = snapshot_today(st)
    local all = {}
    for _, row in ipairs(st.history) do all[#all + 1] = row end
    all[#all + 1] = today

    local week_from = os.date("%Y-%m-%d", os.time() - 6 * 86400)
    local rows = {
        { "今日", today },
        { "近7天", sum_rows(all, week_from) },
        { "累计", sum_rows(all, nil) },
    }
    local first_day = st.history[1] and st.history[1].day or st.today.day
    for i, item in ipairs(rows) do
        local label, row = item[1], item[2]
        local text = string.format("%s %d 字 · 码长 %s", label, row.chars, code_len(row))
        local comment = string.format(
            "击键 %d · 上屏 %d · 退格 %d · 均速 %s · 峰速 %s",
            row.keys, row.commits, row.backspaces,
            average_speed_str(row), peak_speed_str(row))
        if label == "累计" then
            comment = comment .. " · 自 " .. first_day
        end
        local cand = Candidate("stats", seg.start, seg._end, text, comment)
        cand.quality = 600000 - i
        yield(cand)
    end
end

return M
