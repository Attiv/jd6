package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./?.lua",
  package.path,
}, ";")

local core = require("xmjd6.dynamic_phrase_core")

local tmp_root = os.tmpname()
os.remove(tmp_root)
assert(os.execute("mkdir -p " .. string.format("%q", tmp_root)))

local phrase_path = tmp_root .. "/dynamic_phrases.txt"
local order_path = tmp_root .. "/candidate_order.txt"

local function cleanup()
  os.remove(phrase_path)
  os.remove(order_path)
  os.execute("rmdir " .. string.format("%q", tmp_root))
end

local function write_file(path, body)
  local f = assert(io.open(path, "w"))
  f:write(body)
  f:close()
  core.clear_cache()
end

local function read_file(path)
  local f = assert(io.open(path, "r"))
  local body = f:read("*a")
  f:close()
  return body
end

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

local function assert_contains(body, needle, label)
  assert_true(body:find(needle, 1, true), (label or "assert_contains") .. ": " .. body)
end

local function assert_not_contains(body, needle, label)
  assert_true(not body:find(needle, 1, true), (label or "assert_not_contains") .. ": " .. body)
end

local function test_search_entries_lists_and_filters_in_file_order()
  write_file(phrase_path, table.concat({
    "# xmjd6 dynamic phrases",
    "皮佬\tpklz",
    "鱼你在一起\tynzqu",
    "皮老板\tpklza",
    "",
  }, "\n"))

  local all = core.search_entries("", phrase_path)
  assert_equal(#all, 3, "all entries")
  assert_equal(all[1].text, "皮佬", "file order first")
  assert_equal(all[3].text, "皮老板", "file order last")

  local by_code = core.search_entries("PKL", phrase_path)
  assert_equal(#by_code, 2, "case-insensitive code matches")
  assert_equal(by_code[1].text, "皮佬", "code match first")
  assert_equal(by_code[2].text, "皮老板", "code match second")

  local by_text = core.search_entries("鱼", phrase_path)
  assert_equal(#by_text, 1, "text match count")
  assert_equal(by_text[1].code, "ynzqu", "text match code")

  all[1].text = "mutated"
  local fresh = core.search_entries("", phrase_path)
  assert_equal(fresh[1].text, "皮佬", "results do not expose cached entries")
end

local function manager_env()
  return {
    engine = {
      schema = {
        config = {
          get_string = function(_, key)
            if key == "dynamic_phrase/store_file" then
              return "dynamic_phrases.txt"
            end
            return nil
          end,
        },
      },
    },
  }
end

local function run_translator(input, state)
  local old_candidate = _G.Candidate
  local old_yield = _G.yield
  local old_rime_api = _G.rime_api
  local old_state = _G.__dynamic_phrase_state
  local yielded = {}

  _G.rime_api = {
    get_user_data_dir = function() return tmp_root end,
  }
  _G.__dynamic_phrase_state = state or {}
  _G.Candidate = function(cand_type, start_pos, end_pos, text, comment)
    return {
      type = cand_type,
      start = start_pos,
      _end = end_pos,
      text = text,
      comment = comment,
    }
  end
  _G.yield = function(cand)
    yielded[#yielded + 1] = cand
  end

  package.loaded["xmjd6.dynamic_phrase"] = nil
  local translator = require("xmjd6.dynamic_phrase")
  translator(input, { start = 0, _end = #input }, manager_env())

  _G.Candidate = old_candidate
  _G.yield = old_yield
  _G.rime_api = old_rime_api
  _G.__dynamic_phrase_state = old_state
  return yielded
end

local function seed_manager_phrases()
  write_file(phrase_path, table.concat({
    "# xmjd6 dynamic phrases",
    "皮佬\tpklz",
    "鱼你在一起\tynzqu",
    "皮老板\tpklza",
    "",
  }, "\n"))
end

local function test_translator_lists_and_filters_management_candidates()
  seed_manager_phrases()

  local all = run_translator("=del/")
  assert_equal(#all, 3, "management candidate count")
  assert_equal(all[1].type, "dynamic_phrase_manager", "management candidate type")
  assert_equal(all[1].text, "皮佬", "management first text")
  assert_equal(all[1].comment, "pklz〔自造·按0删除〕", "management code comment")
  assert_equal(all[3].text, "皮老板", "management file order")

  local filtered = run_translator("=del/PKL")
  assert_equal(#filtered, 2, "filtered management count")
  assert_equal(filtered[1].text, "皮佬", "filtered first")
  assert_equal(filtered[2].text, "皮老板", "filtered second")
end

local function test_translator_renders_pending_confirmation()
  seed_manager_phrases()
  local state = {
    pending_delete = {
      input = "=del/",
      text = "皮佬",
      code = "pklz",
    },
  }

  local candidates = run_translator("=del/", state)
  assert_equal(#candidates, 1, "confirmation replaces list")
  assert_equal(candidates[1].type, "dynamic_phrase_delete_confirm", "confirmation type")
  assert_equal(candidates[1].text, "确认删除：皮佬", "confirmation text")
  assert_equal(candidates[1].comment, "pklz〔再按0确认，其他键取消〕", "confirmation comment")
end

local function test_translator_shows_empty_store_and_preserves_explicit_commands()
  write_file(phrase_path, "# xmjd6 dynamic phrases\n")
  local empty = run_translator("=del/")
  assert_equal(#empty, 1, "empty candidate count")
  assert_equal(empty[1].type, "dynamic_phrase_manager_empty", "empty candidate type")
  assert_equal(empty[1].text, "暂无自造词", "empty candidate text")

  local explicit = run_translator("=del/皮佬/pklz")
  assert_equal(#explicit, 1, "explicit command candidate count")
  assert_equal(explicit[1].type, "dynamic_phrase", "explicit command preview type")

  local semicolon = run_translator("=del/pklz;")
  assert_equal(#semicolon, 1, "semicolon command candidate count")
  assert_equal(semicolon[1].type, "dynamic_phrase", "semicolon command preview type")
end

local function make_key(ch)
  return {
    keycode = string.byte(ch),
    release = function() return false end,
    ctrl = function() return false end,
    alt = function() return false end,
    super = function() return false end,
    repr = function() return ch end,
  }
end

local function make_context(input, selected)
  local context = {
    input = input,
    selected = selected,
    refresh_count = 0,
    clear_count = 0,
  }
  function context:get_selected_candidate()
    return self.selected
  end
  function context:refresh_non_confirmed_composition()
    self.refresh_count = self.refresh_count + 1
  end
  function context:clear()
    self.clear_count = self.clear_count + 1
    self.input = ""
  end
  return context
end

local function make_processor_env(context, dynamic_file)
  return {
    engine = {
      context = context,
      schema = {
        config = {
          get_string = function(_, key)
            if key == "dynamic_phrase/store_file" then
              return dynamic_file or "dynamic_phrases.txt"
            elseif key == "candidate_order/store_file" then
              return "candidate_order.txt"
            end
            return nil
          end,
        },
      },
      commit_text = function() end,
    },
  }
end

local function load_processor(state)
  _G.__dynamic_phrase_state = state
  package.loaded["xmjd6.dynamic_phrase_processor"] = nil
  return require("xmjd6.dynamic_phrase_processor")
end

local function selected_manager(text, code)
  return {
    type = "dynamic_phrase_manager",
    text = text,
    comment = code .. "〔自造·按0删除〕",
  }
end

local function test_processor_requires_two_zero_presses_for_exact_delete()
  _G.rime_api = { get_user_data_dir = function() return tmp_root end }
  write_file(phrase_path, table.concat({
    "# xmjd6 dynamic phrases",
    "皮佬\tpklz",
    "皮佬\tpklza",
    "鱼你在一起\tynzqu",
    "",
  }, "\n"))
  write_file(order_path, table.concat({
    "# xmjd6 candidate order",
    "皮佬\tpklz\t疲劳\tpklz\tpklzo",
    "别词\tbc\t别字\tbc\tbca",
    "",
  }, "\n"))

  local state = {}
  local processor = load_processor(state)
  local context = make_context("=del/", selected_manager("皮佬", "pklz"))
  local env = make_processor_env(context)

  local before = read_file(phrase_path)
  assert_equal(processor.func(make_key("0"), env), 1, "first zero accepted")
  assert_equal(read_file(phrase_path), before, "first zero does not mutate file")
  assert_equal(state.pending_delete.input, "=del/", "pending input")
  assert_equal(state.pending_delete.text, "皮佬", "pending text")
  assert_equal(state.pending_delete.code, "pklz", "pending code")
  assert_equal(context.refresh_count, 1, "first zero refreshes confirmation")

  assert_equal(processor.func(make_key("0"), env), 1, "second zero accepted")
  assert_equal(state.pending_delete, nil, "pending cleared after delete")
  assert_true(state.manager_notice ~= nil, "deletion notice stored")
  assert_contains(state.manager_notice.message, "已删除1条：皮佬 / pklz", "deletion notice")
  assert_equal(context.refresh_count, 2, "second zero refreshes list")

  local phrases = read_file(phrase_path)
  assert_not_contains(phrases, "皮佬\tpklz\n", "selected exact code removed")
  assert_contains(phrases, "皮佬\tpklza", "other code for same phrase remains")
  assert_contains(phrases, "鱼你在一起\tynzqu", "unrelated phrase remains")

  local orders = read_file(order_path)
  assert_not_contains(orders, "皮佬", "related tuning record removed")
  assert_contains(orders, "别词\tbc", "unrelated tuning remains")

  local refreshed = run_translator("=del/", state)
  assert_equal(refreshed[1].type, "dynamic_phrase_manager_notice", "notice candidate type")
  assert_contains(refreshed[1].text, "已删除1条", "notice candidate text")
end

local function test_processor_cancels_pending_delete_on_other_key_or_changed_input()
  _G.rime_api = { get_user_data_dir = function() return tmp_root end }
  seed_manager_phrases()

  local state = {}
  local processor = load_processor(state)
  local context = make_context("=del/", selected_manager("皮佬", "pklz"))
  local env = make_processor_env(context)

  assert_equal(processor.func(make_key("0"), env), 1, "first zero accepted before cancel")
  assert_equal(processor.func(make_key("x"), env), 2, "other key continues normally")
  assert_equal(state.pending_delete, nil, "other key cancels pending")
  assert_equal(context.refresh_count, 2, "cancel refreshes normal list")
  assert_contains(read_file(phrase_path), "皮佬\tpklz", "cancel keeps phrase")

  assert_equal(processor.func(make_key("0"), env), 1, "new first zero accepted")
  context.input = "=del/p"
  assert_equal(processor.func(make_key("0"), env), 1, "stale confirmation zero swallowed")
  assert_equal(state.pending_delete, nil, "changed input clears stale pending")
  assert_contains(read_file(phrase_path), "皮佬\tpklz", "stale confirmation keeps phrase")
end

local function test_processor_reports_write_failure_without_clearing_composition()
  _G.rime_api = { get_user_data_dir = function() return tmp_root end }
  local state = {}
  local processor = load_processor(state)
  local context = make_context("=del/", selected_manager("坏词", "hc"))
  local env = make_processor_env(context, "missing/dynamic_phrases.txt")

  assert_equal(processor.func(make_key("0"), env), 1, "failure first zero accepted")
  assert_equal(processor.func(make_key("0"), env), 1, "failure second zero accepted")
  assert_equal(context.input, "=del/", "failure keeps composition")
  assert_equal(context.clear_count, 0, "failure does not clear context")
  assert_true(state.manager_notice ~= nil, "failure notice stored")
  assert_contains(state.manager_notice.message, "删除失败", "failure notice message")
end

local function test_existing_semicolon_delete_command_still_executes()
  _G.rime_api = { get_user_data_dir = function() return tmp_root end }
  seed_manager_phrases()
  local state = {}
  local processor = load_processor(state)
  local context = make_context("=del/pklz", nil)
  local env = make_processor_env(context)

  assert_equal(processor.func(make_key(";"), env), 1, "semicolon command accepted")
  assert_equal(context.clear_count, 1, "semicolon command clears context")
  assert_not_contains(read_file(phrase_path), "皮佬\tpklz", "semicolon command still deletes by code")
  assert_contains(read_file(phrase_path), "鱼你在一起\tynzqu", "semicolon preserves other codes")
end

local tests = {
  test_search_entries_lists_and_filters_in_file_order,
  test_translator_lists_and_filters_management_candidates,
  test_translator_renders_pending_confirmation,
  test_translator_shows_empty_store_and_preserves_explicit_commands,
  test_processor_requires_two_zero_presses_for_exact_delete,
  test_processor_cancels_pending_delete_on_other_key_or_changed_input,
  test_processor_reports_write_failure_without_clearing_composition,
  test_existing_semicolon_delete_command_still_executes,
}

for _, test in ipairs(tests) do
  core.clear_cache()
  local ok, err = pcall(test)
  if not ok then
    cleanup()
    error(err, 0)
  end
end

cleanup()

print("dynamic phrase manager tests passed")
