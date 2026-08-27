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

local tests = {
  test_search_entries_lists_and_filters_in_file_order,
  test_translator_lists_and_filters_management_candidates,
  test_translator_renders_pending_confirmation,
  test_translator_shows_empty_store_and_preserves_explicit_commands,
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
