-- dynamic_phrase.lua
-- Dynamic personal phrases for xmjd6.
-- Commands:
--   =add/词/编码   add phrase and commit the phrase once
--   =del/词        delete all dynamic entries for the phrase
--   =del/词/编码   delete one exact phrase-code entry
--   Append ; to execute on Android/Trime, e.g. =add/2/wyy;

local core = require("xmjd6.dynamic_phrase_core")

local function get_commit_history()
    local state = _G.__dynamic_phrase_state
    if not state then return {} end
    return state.commit_history or (state.last_commit_text and { state.last_commit_text }) or {}
end

local function get_store_path(env)
    local file = nil
    if env and env.engine and env.engine.schema and env.engine.schema.config then
        file = env.engine.schema.config:get_string("dynamic_phrase/store_file")
    end
    return core.store_path(file or core.default_filename)
end

local function make_candidate(seg, text, comment, quality)
    local cand = Candidate("dynamic_phrase", seg.start, seg._end, text, comment or "")
    cand.quality = quality or 200000
    return cand
end

local function command_candidate(input, seg)
    local preview, comment = core.command_preview(input, get_commit_history())
    if preview then
        return make_candidate(seg, preview, (comment or "") .. "  末尾加 ; 执行；空格/回车也可", 300000)
    end

    if core.is_dynamic_command(input) then
        local _, err = core.parse_command(input)
        return make_candidate(seg, err or "动态词命令", "单段 =add/码；多段 =add/2/码；末尾 ; 执行", 300000)
    end

    return nil
end

local function translator(input, seg, env)
    if type(input) ~= "string" or input == "" then
        return
    end

    local cmd_cand = command_candidate(input, seg)
    if cmd_cand then
        yield(cmd_cand)
        return
    end

    -- Do not treat non-code special commands as dynamic phrase codes.
    local first = input:sub(1, 1)
    if first == "=" or first == "\\" or first == "&" or first == "/" then
        return
    end

    local matches = core.lookup(input, get_store_path(env))
    for i, entry in ipairs(matches) do
        local cand = make_candidate(seg, entry.text, entry.code .. "〔自造〕", 250000 - i)
        yield(cand)
    end
end

return translator
