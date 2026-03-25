local M = {}

local function get_script_dir()
    local source = debug.getinfo(1).source or ""
    return source:match("@?(.*/)")
end

local function is_ascii_text(text)
    if not text or text == "" then
        return false
    end
    for i = 1, #text do
        if text:byte(i) > 127 then
            return false
        end
    end
    return true
end

local function parse_list(config, key)
    local items = {}
    if not config or not config.get_list then
        return items
    end

    local ok, list = pcall(function()
        return config:get_list(key)
    end)
    if not ok or not list then
        return items
    end

    for i = 0, list:size() - 1 do
        local value = list:get_value_at(i)
        local item = value and (value.value or value:get_string())
        if item and item ~= "" then
            items[#items + 1] = item
        end
    end

    return items
end

function M.load(config)
    local codes = {}
    local script_dir = get_script_dir()
    if not script_dir then
        return codes
    end

    local dict_names = parse_list(config, "topup/protected_dicts")
    for _, dict_name in ipairs(dict_names) do
        local path = string.format("%s../../%s.dict.yaml", script_dir, dict_name)
        local file = io.open(path, "r")
        if file then
            for line in file:lines() do
                local text, code = line:match("^([^\t]+)\t([a-z]+)")
                if text and code and is_ascii_text(text) then
                    codes[code] = true
                end
            end
            file:close()
        end
    end

    return codes
end

return M
