-- 顶功处理器
local protected_codes = require("xmjd6.protected_codes")
local candidate_order_ok, candidate_order_core = pcall(require, "xmjd6.candidate_order_core")

-- 调试开关：存在 /tmp/xmjd6_topup_debug 时才写日志，平时只多一次布尔判断。
local kDebugFlag = "/tmp/xmjd6_topup_debug"
local kDebugLog = "/tmp/xmjd6_topup.log"

local function debug_log(env, message)
    if not env.debug_log then return end
    local file = io.open(env.debug_log, "a")
    if not file then return end
    file:write(message, "\n")
    file:close()
end

local function string2set(str)
    local t = {}
    if type(str) ~= "string" then return t end
    for i = 1, #str do
        t[str:sub(i,i)] = true
    end
    return t
end

local function topup(env)
    local ctx = env.engine.context
    local selected = ctx:get_selected_candidate()
    debug_log(env, string.format("  topup selected=%s", selected and (selected.text or "?") or "nil"))
    if selected then
        ctx:commit()
    elseif env.auto_clear then
        ctx:clear()
    end
end

local function processor(key_event, env)
    if key_event:release() or key_event:ctrl() or key_event:alt() then
        return 2
    end

    local ch = key_event.keycode
    if ch < 0x20 or ch >= 0x7f then
        return 2
    end

    local context = env.engine.context
    local input = context.input
    if not input then return 2 end

    debug_log(env, string.format("key=%s input=%q", string.char(ch), input))

    -- 功能引导符开头的输入（=计算器/工具、\转字体、&Unicode）不参与顶功，
    -- 否则 =uuid、=floor(2) 这类字母输入会在第4码被强制上屏截断
    local lead = input:sub(1, 1)
    if lead == "=" or lead == "\\" or lead == "&" then
        return 2
    end

    local key = string.char(ch)
    if not env.alphabet[key] then
        debug_log(env, "  skip: not in alphabet")
        return 2
    end

    local next_code = input .. key
    if env.protected_codes[next_code] then
        debug_log(env, "  skip: protected code")
        return 2
    end
    if candidate_order_ok and candidate_order_core
        and candidate_order_core.is_enabled(env)
        and candidate_order_core.has_code_prefix
        and candidate_order_core.has_code_prefix(next_code) then
        debug_log(env, "  skip: candidate_order prefix")
        return 2
    end

    local first = #input > 0 and input:sub(1, 1) or key
    if env.topup_command and env.topup_set[first] then
        debug_log(env, "  skip: topup_command")
        return 2
    end

    local input_len = utf8.len(input) or 0
    local prev = #input > 0 and input:sub(-1) or ""
    local is_topup = env.topup_set[key]
    local is_prev_topup = env.topup_set[prev]

    local min_len = context:get_option('danzi_mode')
        and env.topup_min_danzi
        or env.topup_min

    debug_log(env, string.format("  len=%d min=%d max=%d prev=%q is_topup=%s is_prev_topup=%s",
        input_len, min_len, env.topup_max, prev, tostring(is_topup), tostring(is_prev_topup)))

    if is_prev_topup and not is_topup then
        topup(env)
    elseif not is_prev_topup and not is_topup and input_len >= min_len then
        topup(env)
    elseif input_len >= env.topup_max then
        topup(env)
    else
        debug_log(env, "  no topup condition met")
    end

    return 2
end

local function init(env)
    local config = env.engine.schema.config
    env.topup_set = string2set(config:get_string("topup/topup_with") or "")
    env.alphabet = string2set(config:get_string("speller/alphabet") or "abcdefghijklmnopqrstuvwxyz")
    env.topup_min = math.max(1, config:get_int("topup/min_length") or 4)
    env.topup_min_danzi = math.max(1, config:get_int("topup/min_length_danzi") or env.topup_min)
    env.topup_max = math.max(env.topup_min, config:get_int("topup/max_length") or 6)
    env.auto_clear = config:get_bool("topup/auto_clear")
    env.topup_command = config:get_bool("topup/topup_command")
    env.protected_codes = protected_codes.load()

    env.debug_log = nil
    local flag = io.open(kDebugFlag, "r")
    if flag then
        flag:close()
        env.debug_log = kDebugLog
        debug_log(env, string.format("=== init topup min=%d min_danzi=%d max=%d topup_with=%q auto_clear=%s",
            env.topup_min, env.topup_min_danzi, env.topup_max,
            config:get_string("topup/topup_with") or "", tostring(env.auto_clear)))
    end
end

local function fini(env)
    env.topup_set = nil
    env.alphabet = nil
    env.protected_codes = nil
    env.debug_log = nil
end

return { init = init, func = processor, fini = fini }
