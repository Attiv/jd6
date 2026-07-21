-- 空码状态下让数字和英文句点直接上屏，避免 fallback_segmentor
-- 把 2. 之类内容留在组合串中等待空格确认。

local kAccepted = 1
local kNoop = 2

local KEY_TEXT = {
    period = ".", comma = ",", colon = ":", semicolon = ";",
    question = "?", exclam = "!", exclamation = "!",
    minus = "-", plus = "+", slash = "/", backslash = "\\",
}

local function configured_symbols(env)
    if type(env and env.symbols) == "string" then return env.symbols end
    local config = env and env.engine and env.engine.schema and env.engine.schema.config
    if config and config.get_string then
        local ok, value = pcall(function() return config:get_string("direct_ascii/symbols") end)
        if ok and type(value) == "string" then return value end
    end
    return "."
end

local function digits_enabled(env)
    local config = env and env.engine and env.engine.schema and env.engine.schema.config
    if config and config.get_bool then
        local ok, value = pcall(function() return config:get_bool("direct_ascii/digits") end)
        if ok and type(value) == "boolean" then return value end
    end
    return true
end

local function processor(key_event, env)
    if key_event:release() or key_event:ctrl() or key_event:alt() or key_event:super() then
        return kNoop
    end

    local engine = env and env.engine
    local context = engine and engine.context
    if not engine or not engine.commit_text or not context then
        return kNoop
    end
    if context.input and context.input ~= "" then
        -- 有候选时数字仍用于选重，句点仍交给 punctuator。
        return kNoop
    end
    if context.get_option and context:get_option("ascii_mode") then
        return kNoop
    end

    local key = key_event:repr()
    local text = nil
    if type(key) == "string" and key:match("^[0-9]$") and digits_enabled(env) then
        text = key
    else
        local symbol = (#tostring(key) == 1 and key) or KEY_TEXT[key]
        if symbol and configured_symbols(env):find(symbol, 1, true) then text = symbol end
    end
    if not text then return kNoop end

    engine:commit_text(text)
    return kAccepted
end

return { func = processor }
