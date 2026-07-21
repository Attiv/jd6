-- Switcher-controlled gate for entering apostrophe-prefixed sentence mode.
-- Apostrophes typed inside an existing composition remain ordinary delimiters.

local kAccepted = 1
local kNoop = 2

local function processor(key_event, env)
    if not key_event or (type(key_event.release) == "function" and key_event:release()) then
        return kNoop
    end
    if type(key_event.ctrl) == "function" and key_event:ctrl() then return kNoop end
    if type(key_event.alt) == "function" and key_event:alt() then return kNoop end
    if type(key_event.super) == "function" and key_event:super() then return kNoop end
    if type(key_event.repr) ~= "function" or key_event:repr() ~= "apostrophe" then
        return kNoop
    end

    local engine = env and env.engine
    local context = engine and engine.context
    if not context or tostring(context.input or "") ~= "" then
        return kNoop
    end
    if type(context.get_option) == "function" and context:get_option("sentence_mode_enabled") then
        return kNoop
    end
    if type(engine.commit_text) ~= "function" then
        return kNoop
    end
    engine:commit_text("'")
    return kAccepted
end

return { func = processor }
