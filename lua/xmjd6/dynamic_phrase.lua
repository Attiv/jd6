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

local function make_candidate(seg, text, comment, quality, cand_type)
    local cand = Candidate(cand_type or "dynamic_phrase", seg.start, seg._end, text, comment or "")
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

local function management_query(input)
    if type(input) ~= "string" then return nil end
    return input:match("^=del/([^/;]*)$")
end

local function yield_management_candidates(input, seg, env)
    local query = management_query(input)
    if query == nil then return false end

    local state = _G.__dynamic_phrase_state or {}
    local pending = state.pending_delete
    if pending and pending.input == input then
        yield(make_candidate(
            seg,
            "确认删除：" .. pending.text,
            pending.code .. "〔再按0确认，其他键取消〕",
            400000,
            "dynamic_phrase_delete_confirm"
        ))
        return true
    end

    local notice = state.manager_notice
    if notice and notice.input == input and notice.message and notice.message ~= "" then
        yield(make_candidate(
            seg,
            notice.message,
            notice.ok and "〔自造词管理〕" or "〔删除失败〕",
            500000,
            "dynamic_phrase_manager_notice"
        ))
    end

    local entries = core.search_entries(query, get_store_path(env))
    if #entries == 0 then
        if query == "" then
            yield(make_candidate(
                seg,
                "暂无自造词",
                "dynamic_phrases.txt 为空",
                400000,
                "dynamic_phrase_manager_empty"
            ))
        else
            local cmd_cand = command_candidate(input, seg)
            if cmd_cand then yield(cmd_cand) end
        end
        return true
    end

    for i, entry in ipairs(entries) do
        yield(make_candidate(
            seg,
            entry.text,
            entry.code .. "〔自造·按0删除〕",
            400000 - i,
            "dynamic_phrase_manager"
        ))
    end
    return true
end

local function translator(input, seg, env)
    if type(input) ~= "string" or input == "" then
        return
    end

    if yield_management_candidates(input, seg, env) then
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

    local store = get_store_path(env)

    -- 精确命中优先，保证完整编码的候选顺序与行为不变。
    local matches = core.lookup(input, store)
    for i, entry in ipairs(matches) do
        local cand = make_candidate(seg, entry.text, entry.code .. "〔自造〕", 250000 - i)
        yield(cand)
    end

    -- 前缀补全：让 wzfr / wzfru 这类不完整编码也能看到 wzfruu 的自造词。
    -- 仅在精确未命中时才补充。
    -- 排序规则：必须排在表译器正常精确候选（translator.initial_quality 为 0）
    -- 之下，否则码长的自造词会压到该前缀上真正的短码词前面，
    -- 例如 wzfr 上「嘲讽」应始终在「朝凤(wzfruu)」之上。
    -- 这里沿用 candidate_order.lua 对前缀补全的既定约定：quality = -10 - i。
    -- 门槛：少于 2 码不查前缀。键道6 最短有效码为 2 码，且 lookup_prefix
    -- 对单字符会退化为全表扫描，自造词变多后会拖慢每次按键。
    if #matches == 0 and #input >= 2 then
        local prefix_hits = core.lookup_prefix(input, store, 20)
        local shown = 0
        for _, entry in ipairs(prefix_hits) do
            if entry.code ~= input then
                shown = shown + 1
                local cand = make_candidate(
                    seg,
                    entry.text,
                    "~" .. entry.code:sub(#input + 1) .. "〔自造〕",
                    -10 - shown
                )
                yield(cand)
            end
        end
    end
end

return translator
