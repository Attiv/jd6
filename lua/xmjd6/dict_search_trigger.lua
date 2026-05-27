-- dict_search_trigger.lua
-- 拦截 ? 键：取当前首选文本，在指定词库中模糊搜索，把结果存全局
-- 然后在 input 末尾追加 ?，让 recognizer 识别为 dict_search 段，交给 lua_translator 显示

local kAccepted = 1
local kNoop = 2

-- 要搜索的词库列表：要禁用某个词库，在它前面加 -- 注释掉即可
local DICT_FILES = {
    -- ============ 最初的 3 个核心词库 ============
    "xkjd6.tangshi.dict.yaml",    -- 唐诗 (3.5k 行)
    "xkjd6.jisuanji.dict.yaml",   -- 计算机 (73 行)
    "xkjd6.yixue.dict.yaml",      -- 医学 (29.6k 行)
    "xkjd6.liuxing.dict.yaml",    -- 流行 (29k 行)
    "xkjd6.qiche.dict.yaml",      -- 汽车 (128 行)
    "xkjd6.kaifa.dict.yaml",      -- 开发 (134 行)

    -- ============ xkjd6.* 其他词库 ============
    -- "xkjd6.changyong.dict.yaml",  -- 常用 (859 行)
    -- "xkjd6.hanyu.dict.yaml",      -- 汉语 (33 行)

    -- "xkjd6.lanlao.dict.yaml",     -- 兰佬 (104k 行)
    -- "xkjd6.lanlao2.dict.yaml",    -- 兰佬2 (406k 行 ★大)
    -- "xkjd6.liangzi.dict.yaml",    -- 量子 (190k 行 ★大)

    -- "xkjd6.ssb1.dict.yaml",       -- 声笔笔 (22 行)
    "xkjd6.wanne.dict.yaml",      -- 离谱诗词 (1.9k 行)
    -- "xkjd6.yingwen.dict.yaml",    -- 英文 (135 行)
    "xkjd6.yinyang.dict.yaml",    -- 阴阳 (129 行)

    -- ============ xmjd6.* 词库 ============
    -- "xmjd6.buchong.dict.yaml",    -- 补充 (272 行)
    -- "xmjd6.chaojizici.dict.yaml", -- 超级字词 (428 行)
    -- "xmjd6.cizu.dict.yaml",       -- 词组 (121k 行 ★大)
    -- "xmjd6.cx.dict.yaml",         -- 反查 (41k 行)
    -- "xmjd6.danzi.dict.yaml",      -- 单字 (33k 行)
    -- "xmjd6.en.dict.yaml",      -- 英文 (569k 行 ★★超大，默认关闭；中文搜索意义不大)
    -- "xmjd6.extended.dict.yaml",   -- 扩展 (126 行)
    -- "xmjd6.fjcy.dict.yaml",       -- 附加词语 (294k 行 ★大)
    -- "xmjd6.fuhao.dict.yaml",      -- 符号 (180 行)
    -- "xmjd6.gbk.dict.yaml",        -- GBK (24k 行)
    "xmjd6.lianjie.dict.yaml",    -- 链接 (17 行)
    "xmjd6.user.dict.yaml",       -- 用户 (763 行)
    -- "xmjd6.wxw.dict.yaml",        -- 525声笔笔词组 (636 行)
    -- "xmjd6.wxwdanzi.dict.yaml",   -- 声笔笔单字 (614 行)
    -- "xmjd6.yingwen.dict.yaml",    -- 英文 (132 行)
    "xmjd6.zidingyi.dict.yaml",   -- 自定义 (249 行)
}

local MAX_CANDIDATES = 200

if not _G.__dict_search_state then
    _G.__dict_search_state = {
        entries = nil,
        candidates = nil,
        query = nil,
    }
end

local function load_entries()
    if _G.__dict_search_state.entries then return end
    local entries = {}
    local user_dir = rime_api.get_user_data_dir()
    for _, fname in ipairs(DICT_FILES) do
        local path = user_dir .. "/" .. fname
        local f = io.open(path, "r")
        if f then
            local in_data = false
            for line in f:lines() do
                if in_data then
                    local text, code = line:match("^([^\t]+)\t([^\t]+)")
                    if text and code and not text:match("^#") then
                        table.insert(entries, { text = text, code = code })
                    end
                elseif line == "..." then
                    in_data = true
                end
            end
            f:close()
        end
    end
    _G.__dict_search_state.entries = entries
end

local function search(query)
    load_entries()
    local matches = {}
    local n = 0
    for _, entry in ipairs(_G.__dict_search_state.entries) do
        if string.find(entry.text, query, 1, true) then
            n = n + 1
            matches[n] = entry
            if n >= MAX_CANDIDATES then break end
        end
    end
    return matches
end

local function dict_search_trigger(key, env)
    if key:release() then return kNoop end
    if key.keycode ~= 0x3f then return kNoop end

    local context = env.engine.context
    if not context:has_menu() then return kNoop end

    local selected = context:get_selected_candidate()
    if not (selected and selected.text and selected.text ~= "") then
        return kNoop
    end

    local query = selected.text
    if utf8.len(query) < 1 then return kNoop end

    _G.__dict_search_state.candidates = search(query)
    _G.__dict_search_state.query = query

    context:push_input("?")
    return kAccepted
end

return dict_search_trigger
