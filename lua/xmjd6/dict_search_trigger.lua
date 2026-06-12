-- dict_search_trigger.lua
-- 拦截 ? 键：取当前首选文本，在指定词库中模糊搜索，把结果存全局
-- 然后在 input 末尾追加 ?，让 recognizer 识别为 dict_search 段，交给 lua_translator 显示
--
-- 内存说明：词条不再用 {text=, code=} 的逐条 table 缓存（6.5 万条实测 ~13.7MB Lua 堆），
-- 而是拼接成单个 "text\tcode\n" 大字符串（同数据实测 ~1MB），搜索直接在大字符串上
-- string.find（C 层扫描），比逐条 Lua 循环更快。

local mem_cleaner = require("xmjd6.mem_cleaner")

local kAccepted = 1
local kNoop = 2

-- sentinel keycode: XK_VoidSymbol = 0xFFFFFF
-- 由 iOS 端 RimeEngine.cleanupMemory() 在键盘收起时发送，触发统一释放所有 Lua 缓存。
-- VoidSymbol 是 X11 标准 noop keysym，正常 processor 都不会处理它。
local CLEAR_CACHE_KEYCODE = 0xFFFFFF

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
        blob = nil,        -- 所有词条拼成的大字符串，每行 "text\tcode"
        candidates = nil,  -- 最近一次搜索结果（dict_search.lua 读取）
        query = nil,
    }
end

-- 模块级注册：sentinel 到达时由 mem_cleaner 统一清空
mem_cleaner.register(function()
    local state = _G.__dict_search_state
    if state then
        state.blob = nil
        state.candidates = nil
        state.query = nil
    end
end)

local function load_blob()
    if _G.__dict_search_state.blob then return end
    local chunks = {}
    local n = 0
    local user_dir = rime_api.get_user_data_dir()
    local shared_dir = rime_api.get_shared_data_dir()
    for _, fname in ipairs(DICT_FILES) do
        -- 词库文件优先从 user_dir 读取（允许用户覆盖），
        -- 找不到时回退到 shared_dir（输入法发行版自带词库放在这里，例如 iOS App Group SharedData/Rime）
        local f = io.open(user_dir .. "/" .. fname, "r")
        if not f and shared_dir and shared_dir ~= "" then
            f = io.open(shared_dir .. "/" .. fname, "r")
        end
        if f then
            local in_data = false
            for line in f:lines() do
                if in_data then
                    local text, code = line:match("^([^\t]+)\t([^\t]+)")
                    if text and code and not text:match("^#") then
                        n = n + 1
                        chunks[n] = text .. "\t" .. code
                    end
                elseif line == "..." then
                    in_data = true
                end
            end
            f:close()
        end
    end
    _G.__dict_search_state.blob = table.concat(chunks, "\n")
end

local function search(query)
    load_blob()
    local blob = _G.__dict_search_state.blob
    local matches = {}
    local n = 0
    local pos = 1
    while n < MAX_CANDIDATES do
        local s = string.find(blob, query, pos, true)
        if not s then break end
        -- 回找行首、行尾，取出完整词条行
        local line_start = s
        while line_start > 1 and blob:byte(line_start - 1) ~= 10 do
            line_start = line_start - 1
        end
        local line_end = string.find(blob, "\n", s, true) or (#blob + 1)
        local line = blob:sub(line_start, line_end - 1)
        local text, code = line:match("^([^\t]+)\t([^\t]+)")
        -- 确认命中落在词条文本部分（而不是编码部分）
        if text and code and string.find(text, query, 1, true) then
            n = n + 1
            matches[n] = { text = text, code = code }
        end
        pos = line_end + 1 -- 跳到下一行，同一行内多次命中只取一次
    end
    return matches
end

local function dict_search_trigger(key, env)
    if key:release() then return kNoop end

    -- 收到清缓存 sentinel：统一释放所有注册过的 Lua 缓存（词库 blob、反查库、
    -- lazy_simplifier 字典、懒加载的时间模块等），触发 Lua GC。
    -- 在没有 composing/menu 的状态下到达（键盘扩展收起前调用），不会影响用户输入。
    if key.keycode == CLEAR_CACHE_KEYCODE then
        mem_cleaner.release_all()
        return kAccepted
    end

    if key.keycode ~= 0x3f then return kNoop end

    local context = env.engine.context
    if not context:has_menu() then return kNoop end

    local selected = context:get_selected_candidate()
    if not (selected and selected.text and selected.text ~= "") then
        return kNoop
    end

    local query = selected.text
    -- utf8.len 对非法 UTF-8 返回 nil，or 0 防止 nil 比较报错
    if (utf8.len(query) or 0) < 1 then return kNoop end

    _G.__dict_search_state.candidates = search(query)
    _G.__dict_search_state.query = query

    context:push_input("?")
    return kAccepted
end

return dict_search_trigger
