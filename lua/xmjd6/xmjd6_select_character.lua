-- 以词定字
-- 来源 https://github.com/BlindingDark/rime-lua-select-character
-- 删除了默认按键 [ ]，和方括号翻页冲突，需要在 key_binder 下指定才能生效
-- 20230526195910 不再错误地获取commit_text，而是直接获取get_selected_candidate().text。
-- http://lua-users.org/lists/lua-l/2014-04/msg00590.html
local function utf8_sub(s, i, j)
    i = i or 1
    j = j or -1

    if i < 1 or j < 1 then
        local n = utf8.len(s)
        if not n then
            return nil
        end
        if i < 0 then
            i = n + 1 + i
        end
        if j < 0 then
            j = n + 1 + j
        end
        if i < 0 then
            i = 1
        elseif i > n then
            i = n
        end
        if j < 0 then
            j = 1
        elseif j > n then
            j = n
        end
    end

    if j < i then
        return ""
    end

    i = utf8.offset(s, i)
    j = utf8.offset(s, j + 1)

    if i and j then
        return s:sub(i, j - 1)
    elseif i then
        return s:sub(i)
    else
        return ""
    end
end

local function first_character(s)
    return utf8_sub(s, 1, 1)
end

local function last_character(s)
    return utf8_sub(s, -1, -1)
end

local function get_commit_text(context, fun)
    local candidate_text = context:get_selected_candidate().text
    local selected_character = fun(candidate_text)

    context:clear_previous_segment()
    local commit_text = context:get_commit_text()

    context:clear()

    return commit_text .. selected_character
end

local function select_character(key, env)
    local engine = env.engine
    local context = engine.context
    local config = engine.schema.config

    local first_key = config:get_string('key_binder/select_first_character') or 'bracketleft'
    local last_key = config:get_string('key_binder/select_last_character') or 'bracketright'

    local commit_text = context:get_commit_text()

    if (key:repr() == first_key and commit_text ~= "") then
        engine:commit_text(get_commit_text(context, first_character))

        return 1 -- kAccepted
    end

    if (key:repr() == last_key and commit_text ~= "") then
        engine:commit_text(get_commit_text(context, last_character))

        return 1 -- kAccepted
    end

    return 2 -- kNoop
end

return select_character
