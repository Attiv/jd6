--[[
    https://github.com/xkjd27/rime_jd27c/blob/e38a8c5d010d5a3933e6d6d8265c0cf7b56bfcca/rime/lua/jd27_hint.lua
    by TsFreddie
    - 简码 630 提示
    - 单字模式
--]]

local DEFAULT_MAX_HINT_CANDIDATES = 50   -- 0 表示不限
local DEFAULT_MAX_COMPLETION_CANDIDATES = 30

local function startswith(str, start)
    return string.sub(str, 1, string.len(start)) == start
end

local function hint(cand, input, env)
    -- 简码提示
    if utf8.len(cand.text) <= 1 then
        return 0
    end
    local reverse = env.reverse
    local pattern_sbb = env.pattern_sbb
    local pattern_short = env.pattern_short
    local pattern_ssb = env.pattern_ssb

    local lookup = " " .. reverse:lookup(cand.text) .. " "
    local sbb = pattern_sbb and string.match(lookup, pattern_sbb)
    local short = pattern_short and string.match(lookup, pattern_short)
    local ssb = pattern_ssb and string.match(lookup, pattern_ssb)

    if string.len(input) > 1 then
        if sbb and not startswith(sbb, input) then
            cand:get_genuine().comment = cand.comment .. "〔" .. sbb .. "〕"
            -- cand:get_genuine().comment = cand.comment .. "≈" .. sbb .. ""
            return 1
        end

        if short and not startswith(short, input) then
            cand:get_genuine().comment = cand.comment .. "〔" .. short .. "" .. "〕"
            return 2
        end

        if ssb and not startswith(ssb, input) then
            cand:get_genuine().comment = cand.comment .. "〔" .. ssb .. "〕"
            return 3
        end
    end

    return 0
end

local function commit_hint(cand, hint_text)
    -- 顶功提示
    cand:get_genuine().comment = hint_text .. cand.comment
end

local function is_danzi(cand)
    return utf8.len(cand.text) == 1
end

local function filter(input, env)
    local context = env.engine.context
    local is_hint_on = context:get_option('wxw_hint')
    local is_completion_on = context:get_option('completion')
    local is_danzi_on = context:get_option('danzi_mode')
    local input_text = context.input
    local no_commit = (input_text:len() < 4 and input_text:match("^[bcdefghjklmnpqrstwxyz]+$")) or
                          (input_text:match("^[avuio]+$"))
    local has_table = false
    local first = true
    local hint_text = env.hint_text or '✖'
    local hinted = 0
    local yielded_completion = 0
    local max_hint = env.max_hint_candidates or DEFAULT_MAX_HINT_CANDIDATES
    local max_completion = env.max_completion_candidates or DEFAULT_MAX_COMPLETION_CANDIDATES
    local gc_interval = env.hint_gc_interval or 50

    for cand in input:iter() do
        if no_commit and first then
            commit_hint(cand, hint_text)
        end
        first = false
        if cand.type == 'table' then
            if is_hint_on and (max_hint == 0 or hinted < max_hint) then
                local hinted_delta = hint(cand, input_text, env)
                if hinted_delta and hinted_delta > 0 then
                    hinted = hinted + 1
                    if gc_interval > 0 and hinted % gc_interval == 0 then
                        collectgarbage('step', 1)
                    end
                end
            end

            yield(cand)
            has_table = true
        elseif cand.type == 'completion' then
            local completion_allowed = (max_completion == 0) or (yielded_completion < max_completion)
            if not completion_allowed then
                return
            end

            if is_completion_on then
                if not is_danzi_on or is_danzi(cand) then
                    yield(cand)
                    yielded_completion = yielded_completion + 1
                end
            elseif not has_table then
                if not is_danzi_on or is_danzi(cand) then
                    yield(cand)
                    return
                end
            else
                return
            end
        else
            yield(cand)
        end
    end
end

local function init(env)
    local config = env.engine.schema.config
    local dict_name = config:get_string("translator/dictionary")
    env.b = config:get_string("topup/topup_with")
    env.s = config:get_string("topup/topup_this")
    env.pattern_sbb = " ([" .. env.s .. "][" .. env.b .. "]+) "
    env.pattern_short = " ([" .. env.s .. "][" .. env.s .. "]) "
    env.pattern_ssb = " ([" .. env.s .. "][" .. env.s .. "][" .. env.b .. "]+) "
    env.hint_text = config:get_string('hint_text') or '✖'
    local function read_conf_int(path, default)
        local ok, val = pcall(function()
            return config:get_int(path)
        end)
        val = ok and tonumber(val) or nil
        if not val or val < 0 then return default end
        return val
    end
    env.max_hint_candidates = read_conf_int('for_hint/max_hint_candidates', DEFAULT_MAX_HINT_CANDIDATES)
    env.max_completion_candidates = read_conf_int('for_hint/max_completion_candidates', DEFAULT_MAX_COMPLETION_CANDIDATES)
    env.hint_gc_interval = read_conf_int('for_hint/gc_interval', 50)
    env.gc = env.engine.context.commit_notifier:connect(function(ctx)
        collectgarbage('collect')
    end)
    -- env.reverse = ReverseDb("build/".. dict_name .. ".reverse.bin")
    -- 假设 ReverseDb 实例已经存在，则先释放它

    if not env.reverse then
        env.reverse = ReverseLookup(dict_name)
    end

end

local function fini(env)
    env.gc:disconnect()
    env.max_hint_candidates = nil
    env.max_completion_candidates = nil
    env.hint_gc_interval = nil
end

return {
    init = init,
    fini = fini,
    func = filter
}
