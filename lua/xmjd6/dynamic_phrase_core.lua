-- dynamic_phrase_core.lua
-- Pure Lua helpers for the xmjd6 dynamic personal phrase store.
-- Store format: one UTF-8 entry per line: text<TAB>code

local M = {}

-- Cache for indexed entries
local cache = {
    path = nil,
    mtime = nil,
    entries = nil,      -- 原始词条数组
    by_code = nil       -- 按编码索引: { [code] = { {text, code}, ... } }
}

M.default_filename = "dynamic_phrases.txt"

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function is_code_like(s)
    return type(s) == "string" and s:match("^[A-Za-z0-9;']+$") ~= nil
end

local function strip_execute_suffix(input)
    if type(input) ~= "string" then
        return input, false
    end
    if input:sub(-1) == ";" then
        return input:sub(1, -2), true
    end
    return input, false
end

local function path_separator()
    local cfg = package.config or "/"
    return cfg:sub(1, 1) == "\\" and "\\" or "/"
end

local function join_path(dir, name)
    if not dir or dir == "" then return name end
    local sep = path_separator()
    if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then
        return dir .. name
    end
    return dir .. sep .. name
end

local function normalize_commit_history(source)
    if type(source) == "table" then
        local out = {}
        for _, item in ipairs(source) do
            local s = trim(tostring(item or ""))
            if s ~= "" then
                out[#out + 1] = s
            end
        end
        return out
    end

    local s = trim(source)
    if s == "" then return {} end
    return { s }
end

function M.recent_commit_text(source, count)
    local history = normalize_commit_history(source)
    count = tonumber(count) or 1
    count = math.floor(count)
    if count < 1 then return "" end
    if #history == 0 then return "" end
    if count > #history then count = #history end

    local start = #history - count + 1
    local parts = {}
    for i = start, #history do
        parts[#parts + 1] = history[i]
    end
    return table.concat(parts)
end

function M.store_path(filename)
    filename = filename or M.default_filename
    if rime_api and rime_api.get_user_data_dir then
        local ok, dir = pcall(rime_api.get_user_data_dir)
        if ok and dir and dir ~= "" then
            return join_path(dir, filename)
        end
    end
    return filename
end

local function get_file_mtime(path)
    local lfs_ok, lfs = pcall(require, "lfs")
    if lfs_ok and lfs.attributes then
        local ok, attr = pcall(lfs.attributes, path, "modification")
        if ok and attr then
            return attr
        end
    end
    -- Fallback: use file size + existence as a simple cache key
    local f = io.open(path, "r")
    if not f then return 0 end
    local size = f:seek("end")
    f:close()
    return size or 0
end

local function build_code_index(entries)
    local index = {}
    for _, entry in ipairs(entries) do
        local code = entry.code
        if not index[code] then
            index[code] = {}
        end
        index[code][#index[code] + 1] = entry
    end
    return index
end

local function clear_cache()
    cache.path = nil
    cache.mtime = nil
    cache.entries = nil
    cache.by_code = nil
end

local function get_cached_entries(path)
    path = path or M.store_path()
    local mtime = get_file_mtime(path)

    if cache.path == path and cache.mtime == mtime and cache.entries then
        return cache.entries, cache.by_code
    end

    -- Cache miss or stale - reload and rebuild indexes
    local entries = M.load_entries_uncached(path)
    local by_code = build_code_index(entries)
    cache.path = path
    cache.mtime = mtime
    cache.entries = entries
    cache.by_code = by_code

    return entries, by_code
end

function M.is_dynamic_command(input)
    if type(input) ~= "string" then return false end
    input = strip_execute_suffix(input)
    return input == "=add" or input:match("^=add/") ~= nil
        or input == "=del" or input:match("^=del/") ~= nil
end

function M.parse_command(input)
    if type(input) ~= "string" then
        return nil, "命令为空"
    end

    local execute_suffix = false
    input, execute_suffix = strip_execute_suffix(input)

    if input == "=add" or input == "=add/" then
        return nil, "用法：先上屏词，再输入 =add/编码；或 =add/词/编码"
    end
    if input == "=del" or input == "=del/" then
        return nil, "用法：=del/词 或 =del/词/编码"
    end

    local pending_count = input:match("^=add/(%d+)$")
    if pending_count ~= nil then
        return nil, "继续输入 /编码：=add/" .. pending_count .. "/编码"
    end

    local count, code = input:match("^=add/(%d+)/([^/]+)$")
    if count ~= nil then
        code = trim(code)
        if code == "" then return nil, "编码不能为空" end
        return { action = "add", code = code, needs_last_commit = true, chunk_count = tonumber(count) or 1, execute_suffix = execute_suffix }
    end

    local text, code = input:match("^=add/(.-)/([^/]+)$")
    if text ~= nil then
        text = trim(text)
        code = trim(code)
        if text == "" then return nil, "词不能为空" end
        if code == "" then return nil, "编码不能为空" end
        return { action = "add", text = text, code = code, execute_suffix = execute_suffix }
    end

    code = input:match("^=add/([^/]+)$")
    if code ~= nil then
        code = trim(code)
        if code == "" then return nil, "编码不能为空" end
        return { action = "add", code = code, needs_last_commit = true, execute_suffix = execute_suffix }
    end

    local pending_count = input:match("^=del/(%d+)$")
    if pending_count ~= nil then
        return nil, "继续输入 /编码：=del/" .. pending_count .. "/编码；或末尾 ; 删除编码 " .. pending_count
    end

    local count, code = input:match("^=del/(%d+)/([^/]+)$")
    if count ~= nil then
        code = trim(code)
        if code == "" then return nil, "编码不能为空" end
        return { action = "del", code = code, needs_last_commit = true, chunk_count = tonumber(count) or 1, execute_suffix = execute_suffix }
    end

    text, code = input:match("^=del/(.-)/([^/]+)$")
    if text ~= nil then
        text = trim(text)
        code = trim(code)
        if text == "" then return nil, "词不能为空" end
        if code == "" then return nil, "编码不能为空" end
        return { action = "del", text = text, code = code, execute_suffix = execute_suffix }
    end

    text = input:match("^=del/(.+)$")
    if text ~= nil then
        text = trim(text)
        if text == "" then return nil, "词不能为空" end
        return { action = "del", text = text, single_arg = true, execute_suffix = execute_suffix }
    end

    if input:match("^=add/") then
        return nil, "用法：先上屏词，再输入 =add/编码；或 =add/词/编码"
    end
    if input:match("^=del/") then
        return nil, "用法：=del/词 或 =del/词/编码"
    end

    return nil, "未知命令"
end

function M.load_entries_uncached(path)
    path = path or M.store_path()
    local entries = {}
    local f = io.open(path, "r")
    if not f then
        return entries
    end

    for line in f:lines() do
        if line and line ~= "" and not line:match("^%s*#") then
            local text, code = line:match("^(.-)\t([^\t]+)")
            if text and code then
                text = trim(text)
                code = trim(code)
                if text ~= "" and code ~= "" then
                    entries[#entries + 1] = { text = text, code = code }
                end
            end
        end
    end
    f:close()
    return entries
end

function M.load_entries(path)
    local entries = get_cached_entries(path)
    return entries
end

function M.save_entries(entries, path)
    path = path or M.store_path()
    local f, err = io.open(path, "w")
    if not f then
        return false, err or "无法写入动态词库"
    end

    f:write("# xmjd6 dynamic phrases\n")
    f:write("# text<TAB>code; edited by =add/=del commands\n")
    for _, entry in ipairs(entries or {}) do
        if entry.text and entry.code and entry.text ~= "" and entry.code ~= "" then
            f:write(entry.text, "\t", entry.code, "\n")
        end
    end
    local ok, close_err = f:close()
    if ok == false then
        return false, close_err or "保存动态词库失败"
    end

    -- Clear cache after saving to force reload on next access
    clear_cache()

    return true
end

local function same_entry(a, b)
    return a.text == b.text and a.code == b.code
end

function M.add_phrase(text, code, path)
    text = trim(text)
    code = trim(code)
    if text == "" then return false, "词不能为空" end
    if code == "" then return false, "编码不能为空" end

    local entries = M.load_entries(path)
    local new_entry = { text = text, code = code }
    local exists = false
    for _, entry in ipairs(entries) do
        if same_entry(entry, new_entry) then
            exists = true
            break
        end
    end
    if not exists then
        entries[#entries + 1] = new_entry
    end

    local ok, err = M.save_entries(entries, path)
    if not ok then return false, err end
    if exists then
        return true, "已存在：" .. text .. " / " .. code, 0
    end
    return true, "已添加：" .. text .. " / " .. code, 1
end

function M.delete_phrase(text, code, path)
    text = trim(text)
    code = code and trim(code) or nil
    if text == "" then return false, "词不能为空" end
    if code == "" then return false, "编码不能为空" end

    local entries = M.load_entries(path)
    local kept = {}
    local removed = 0
    for _, entry in ipairs(entries) do
        local matches = entry.text == text and (not code or entry.code == code)
        if matches then
            removed = removed + 1
        else
            kept[#kept + 1] = entry
        end
    end

    local ok, err = M.save_entries(kept, path)
    if not ok then return false, err, removed end
    if removed == 0 then
        return true, "未找到：" .. text .. (code and (" / " .. code) or ""), 0
    end
    return true, "已删除" .. removed .. "条：" .. text .. (code and (" / " .. code) or ""), removed
end

function M.delete_by_code(code, path)
    code = trim(code)
    if code == "" then return false, "编码不能为空" end

    local entries = M.load_entries(path)
    local kept = {}
    local removed = 0
    for _, entry in ipairs(entries) do
        if entry.code == code then
            removed = removed + 1
        else
            kept[#kept + 1] = entry
        end
    end

    local ok, err = M.save_entries(kept, path)
    if not ok then return false, err, removed end
    if removed == 0 then
        return true, "未找到编码：" .. code, 0
    end
    return true, "已删除" .. removed .. "条编码：" .. code, removed
end

function M.resolve_command(input, commit_history)
    local cmd, err = M.parse_command(input)
    if not cmd then
        return nil, err or "命令格式错误"
    end
    if cmd.action == "add" and cmd.needs_last_commit then
        local text = M.recent_commit_text(commit_history, cmd.chunk_count or 1)
        if text == "" then
            return nil, "先打出要加的词，再输入 =add/编码；多段用 =add/2/编码"
        end
        cmd.text = text
        cmd.from_last_commit = true
    elseif cmd.action == "del" and cmd.needs_last_commit then
        local text = M.recent_commit_text(commit_history, cmd.chunk_count or 1)
        if text == "" then
            return nil, "先打出要删的词，再输入 =del/编码；多段用 =del/2/编码"
        end
        cmd.text = text
        cmd.from_last_commit = true
    elseif cmd.action == "del" and cmd.single_arg and is_code_like(cmd.text) then
        if cmd.execute_suffix then
            cmd.code = cmd.text
            cmd.text = nil
            cmd.by_code = true
        else
            local text = M.recent_commit_text(commit_history, 1)
            if text ~= "" then
                cmd.code = cmd.text
                cmd.text = text
                cmd.from_last_commit = true
            end
        end
    end
    return cmd
end

function M.apply_resolved_command(cmd, path)
    if not cmd then
        return false, "命令格式错误", 0
    end
    if cmd.action == "add" then
        return M.add_phrase(cmd.text, cmd.code, path)
    elseif cmd.action == "del" then
        if cmd.by_code then
            return M.delete_by_code(cmd.code, path)
        end
        return M.delete_phrase(cmd.text, cmd.code, path)
    end
    return false, "未知命令", 0
end

function M.apply_command(input, path, last_commit_text)
    local cmd, err = M.resolve_command(input, last_commit_text)
    if not cmd then
        return false, err or "命令格式错误", 0
    end
    return M.apply_resolved_command(cmd, path)
end

function M.lookup(code, path)
    code = trim(code)
    if code == "" then return {} end

    local _, by_code = get_cached_entries(path)
    return by_code[code] or {}
end

function M.lookup_prefix(prefix, path, limit)
    prefix = trim(prefix)
    if prefix == "" then return {} end
    limit = limit or 50

    -- Prefix lookup is not used by the input path. Keep it uncached and bounded
    -- to avoid retaining a second multi-prefix index for every dynamic phrase.
    local entries = M.load_entries(path)
    local matches = {}
    for _, entry in ipairs(entries) do
        if entry.code:sub(1, #prefix) == prefix then
            matches[#matches + 1] = entry
            if #matches >= limit then break end
        end
    end
    return matches
end

function M.command_preview(input, last_commit_text)
    local cmd, err = M.resolve_command(input, last_commit_text)
    if not cmd then
        return nil, err
    end
    if cmd.action == "add" then
        local prefix = cmd.from_last_commit and "添加刚上屏：" or "添加词："
        return prefix .. cmd.text, cmd.code
    elseif cmd.action == "del" then
        if cmd.by_code then
            return "删除编码：" .. cmd.code, "全部自造词"
        end
        local prefix = cmd.from_last_commit and "删除刚上屏：" or "删除词："
        return prefix .. cmd.text, cmd.code or "全部编码"
    end
    return nil, "未知命令"
end

-- Public API to manually clear cache (useful for debugging or external updates)
function M.clear_cache()
    clear_cache()
end

return M
