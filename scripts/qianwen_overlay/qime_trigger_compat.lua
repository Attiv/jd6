-- Compatibility shim for QianwenIME's direct-punctuation wrapper.
-- Qianwen clears and directly commits a one-byte punctuation composition after
-- Rime accepts it. Append an invisible three-byte pad so the trigger survives
-- that outer check without looking like an automatically paired symbol. On the
-- next real key we remove the pad before the original processors run.
local kAccepted, kNoop = 1, 2
local triggers = { ['=']=true, [';']=true, ['`']=true, ["'"]=true, ['\\']=true }
local pad = utf8.char(0x200B)

local function key_char(key)
  local code = key and key.keycode
  if code and code >= 0x20 and code < 0x7f then return string.char(code) end
  local repr = key and key.repr and key:repr() or ''
  if #repr == 1 then return repr end
  return ({ equal='=', semicolon=';', grave='`', apostrophe="'", backslash='\\' })[repr]
end

local function processor(key, env)
  if not key then return kNoop end
  local context = env and env.engine and env.engine.context
  if not context then return kNoop end

  local input = context.input or ''
  local first = input:sub(1, 1)
  if triggers[first] and input == first .. pad then
    -- pop_input counts UTF-8 bytes in this librime build.
    pcall(function() context:pop_input(3) end)
    return kNoop
  end

  if key:release() or key:ctrl() or key:alt() or key:super() then return kNoop end
  local ch = key_char(key)
  if ch == "'" and type(context.get_option) == 'function'
      and not context:get_option('sentence_mode_enabled') then
    return kNoop
  end
  if input == '' and triggers[ch] then
    local ok = pcall(function() context:push_input(ch .. pad) end)
    return ok and kAccepted or kNoop
  end
  return kNoop
end

return { func = processor }
