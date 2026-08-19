package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./?.lua",
  package.path,
}, ";")

local filter = require("xmjd6.xmjd6_single_char")

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format(
      "%s: expected %q, got %q",
      label or "assert_equal",
      tostring(expected),
      tostring(actual)
    ), 2)
  end
end

local function assert_true(value, label)
  if not value then error(label or "assert_true failed", 2) end
end

local function candidate(text, id)
  return { type = "table", text = text, comment = "", id = id or text }
end

local function make_stream(texts)
  local state = { pulled = 0 }

  function state:iter()
    local index = 0
    return function()
      index = index + 1
      local text = texts[index]
      if text == nil then return nil end
      self.pulled = self.pulled + 1
      return candidate(text, index)
    end
  end

  return state
end

local function make_env(enabled, scan_limit)
  local config = {}

  function config:get_bool(path)
    assert_equal(path, "xmjd6_single_char/enabled", "enabled config path")
    return enabled
  end

  function config:get_int(path)
    assert_equal(path, "xmjd6_single_char/scan_limit", "scan-limit config path")
    return scan_limit
  end

  return {
    engine = {
      schema = { config = config },
    },
  }
end

local function run_filter(texts, enabled, scan_limit)
  local stream = make_stream(texts)
  local env = make_env(enabled, scan_limit)
  filter.init(env)

  local output = {}
  local old_yield = _G.yield
  _G.yield = function(cand)
    output[#output + 1] = cand
  end
  local ok, err = pcall(filter.func, stream, env)
  _G.yield = old_yield
  if not ok then error(err, 0) end
  return output, stream, env
end

local function first_output(texts, enabled, scan_limit)
  local stream = make_stream(texts)
  local env = make_env(enabled, scan_limit)
  filter.init(env)

  local sentinel = {}
  local first
  local old_yield = _G.yield
  _G.yield = function(cand)
    first = cand
    error(sentinel, 0)
  end
  local ok, err = pcall(filter.func, stream, env)
  _G.yield = old_yield
  assert_true(not ok and err == sentinel, "filter must stop at first sentinel yield")
  return first, stream.pulled, env
end

local function ids(candidates)
  local result = {}
  for index, cand in ipairs(candidates) do result[index] = cand.id end
  return table.concat(result, ",")
end

local function test_module_exposes_component_api()
  assert_equal(type(filter), "table", "module type")
  assert_equal(type(filter.init), "function", "init API")
  assert_equal(type(filter.func), "function", "filter API")
  assert_equal(type(filter.is_single_codepoint), "function", "classifier API")
end

local function test_single_codepoint_detection()
  for _, text in ipairs({ "A", "字", "𠀀" }) do
    assert_true(filter.is_single_codepoint(text), text .. " is one codepoint")
  end
  for _, text in ipairs({ "", "词语", "AB", "👨‍👩‍👧‍👦" }) do
    assert_true(not filter.is_single_codepoint(text), text .. " is not one codepoint")
  end
end

local function test_first_twenty_are_stably_partitioned_and_suffix_is_untouched()
  local texts = {}
  for index = 1, 25 do texts[index] = "词" .. tostring(index) end
  texts[3] = "甲"
  texts[7] = "乙"
  texts[20] = "𠀀"
  texts[21] = "丙"

  local output, stream = run_filter(texts, true, 20)
  assert_equal(#output, 25, "candidate count")
  assert_equal(stream.pulled, 25, "complete stream pull count")

  local expected = { 3, 7, 20 }
  for index = 1, 20 do
    if index ~= 3 and index ~= 7 and index ~= 20 then
      expected[#expected + 1] = index
    end
  end
  for index = 21, 25 do expected[#expected + 1] = index end
  assert_equal(ids(output), table.concat(expected, ","), "stable bounded ordering")
end

local function test_no_single_prefix_pulls_only_twenty_before_first_word()
  local texts = {}
  for index = 1, 1000 do texts[index] = "词" .. tostring(index) end
  texts[21] = "甲"

  local first, pulled = first_output(texts, true, 20)
  assert_equal(first.id, 1, "first buffered word")
  assert_equal(pulled, 20, "bounded worst-case prefetch")
end

local function test_early_single_yields_without_waiting_for_full_window()
  local first, pulled = first_output({ "词语", "甲", "后续词", "更多词" }, true, 20)
  assert_equal(first.id, 2, "early single candidate")
  assert_equal(pulled, 2, "early single pull count")
end

local function test_disabled_filter_is_direct_passthrough()
  local output, _, env = run_filter({ "词语", "甲", "后续词" }, false, 20)
  assert_equal(ids(output), "1,2,3", "disabled order")
  assert_equal(env.single_char_first_enabled, false, "cached enabled setting")

  local first, pulled = first_output({ "词语", "甲" }, false, 20)
  assert_equal(first.id, 1, "disabled first candidate")
  assert_equal(pulled, 1, "disabled prefetch")
end

local function test_small_or_zero_window_is_direct_passthrough()
  for _, limit in ipairs({ 0, 1 }) do
    local output, _, env = run_filter({ "词语", "甲", "后续词" }, true, limit)
    assert_equal(ids(output), "1,2,3", "limit " .. limit .. " order")
    assert_equal(env.single_char_first_scan_limit, limit, "cached limit " .. limit)
  end
end

local function test_default_configuration_uses_twenty()
  local env = make_env(nil, nil)
  filter.init(env)
  assert_equal(env.single_char_first_enabled, true, "default enabled")
  assert_equal(env.single_char_first_scan_limit, 20, "default scan limit")
end

local tests = {
  test_module_exposes_component_api,
  test_single_codepoint_detection,
  test_first_twenty_are_stably_partitioned_and_suffix_is_untouched,
  test_no_single_prefix_pulls_only_twenty_before_first_word,
  test_early_single_yields_without_waiting_for_full_window,
  test_disabled_filter_is_direct_passthrough,
  test_small_or_zero_window_is_direct_passthrough,
  test_default_configuration_uses_twenty,
}

for _, test in ipairs(tests) do test() end

print("single-char-first tests passed")
