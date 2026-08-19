-- Bounded single-character-first filter.
-- Stable-partitions only the configured prefix, then streams the untouched suffix.

local M = {}

local DEFAULT_SCAN_LIMIT = 20
local CONFIG_PREFIX = "xmjd6_single_char/"

local function is_single_codepoint(text)
    if type(text) ~= "string" then return false end

    local size = #text
    if size < 1 or size > 4 then return false end

    local first = string.byte(text, 1)
    local width
    if first < 0x80 then
        width = 1
    elseif first >= 0xC2 and first <= 0xDF then
        width = 2
    elseif first >= 0xE0 and first <= 0xEF then
        width = 3
    elseif first >= 0xF0 and first <= 0xF4 then
        width = 4
    else
        return false
    end

    if size ~= width then return false end
    for index = 2, width do
        local byte = string.byte(text, index)
        if byte < 0x80 or byte > 0xBF then return false end
    end
    return true
end

local function passthrough(input)
    for cand in input:iter() do yield(cand) end
end

function M.init(env)
    local config = env.engine.schema.config
    local enabled = config:get_bool(CONFIG_PREFIX .. "enabled")
    local scan_limit = tonumber(config:get_int(CONFIG_PREFIX .. "scan_limit"))

    env.single_char_first_enabled = enabled ~= false
    env.single_char_first_scan_limit = math.max(0, scan_limit or DEFAULT_SCAN_LIMIT)
end

function M.func(input, env)
    if not input or type(input.iter) ~= "function" then return end

    local enabled = not env or env.single_char_first_enabled ~= false
    local scan_limit = env and env.single_char_first_scan_limit or DEFAULT_SCAN_LIMIT
    if not enabled or scan_limit < 2 then
        passthrough(input)
        return
    end

    local iter = input:iter()
    local words = {}
    local scanned = 0

    for cand in iter do
        scanned = scanned + 1
        if is_single_codepoint(cand and cand.text) then
            yield(cand)
        else
            words[#words + 1] = cand
        end
        if scanned >= scan_limit then break end
    end

    for index = 1, #words do yield(words[index]) end
    for cand in iter do yield(cand) end
end

M.is_single_codepoint = is_single_codepoint

return M
