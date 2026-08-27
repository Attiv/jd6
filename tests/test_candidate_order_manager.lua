package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./?.lua",
  package.path,
}, ";")

local tmp_root = os.tmpname()
os.remove(tmp_root)
assert(os.execute("mkdir -p " .. string.format("%q", tmp_root)))

local old_rime_api = _G.rime_api
local old_candidate = _G.Candidate
local old_yield = _G.yield
local old_manager_state = _G.__candidate_order_manager_state
_G.rime_api = {
  get_user_data_dir = function() return tmp_root end,
}

local core = require("xmjd6.candidate_order_core")
local order_path = tmp_root .. "/candidate_order.txt"

local function cleanup()
  os.remove(order_path)
  os.execute("rmdir " .. string.format("%q", tmp_root))
  _G.rime_api = old_rime_api
  _G.Candidate = old_candidate
  _G.yield = old_yield
  _G.__candidate_order_manager_state = old_manager_state
  package.loaded["xmjd6.candidate_order"] = nil
  package.loaded["xmjd6.candidate_order_core"] = nil
end

local function write_file(body)
  local f = assert(io.open(order_path, "w"))
  f:write(body)
  f:close()
  core.clear_cache()
end

local function read_file()
  local f = assert(io.open(order_path, "r"))
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

local function seed_records()
  write_file(table.concat({
    "# xmjd6 candidate order",
    "# promoted<TAB>old_code<TAB>displaced<TAB>target_code<TAB>new_code",
    "皮佬\tpklz\t疲劳\tpklz\tpklzo",
    "疲劳\tpklz\t疲痨\tpklzo\tpklzoo",
    "",
    "AI\tai\t阝\tai",
    "",
  }, "\n"))
end

local function test_search_records_filters_all_fields_in_file_order()
  seed_records()

  local all = core.search_records("", "candidate_order.txt")
  assert_equal(#all, 3, "all record count")
  assert_equal(all[1].promoted, "皮佬", "file order first")
  assert_equal(all[1].line_no, 3, "source line number")
  assert_equal(all[3].promoted, "AI", "file order last")

  local by_text = core.search_records("疲痨", "candidate_order.txt")
  assert_equal(#by_text, 1, "displaced text match count")
  assert_equal(by_text[1].target_code, "pklzo", "displaced text match")

  local by_code = core.search_records("PKLZO", "candidate_order.txt")
  assert_equal(#by_code, 2, "case-insensitive code match count")
  assert_equal(by_code[1].promoted, "皮佬", "new-code match first")
  assert_equal(by_code[2].promoted, "疲劳", "target-code match second")

  local by_ascii_text = core.search_records("ai", "candidate_order.txt")
  assert_equal(#by_ascii_text, 1, "case-insensitive ASCII text match")
  assert_equal(by_ascii_text[1].promoted, "AI", "ASCII promoted match")

  all[1].promoted = "mutated"
  local fresh = core.search_records("", "candidate_order.txt")
  assert_equal(fresh[1].promoted, "皮佬", "search results are copies")
end

local function test_record_at_line_and_exact_removal_cleans_dependent_chain()
  seed_records()

  local selected = core.record_at_line(3, "candidate_order.txt")
  assert_equal(selected.promoted, "皮佬", "record at source line")
  assert_equal(selected.new_code, "pklzo", "record at line keeps fallback")

  local ok, removed = core.remove_record_and_dependents(selected, order_path)
  assert_true(ok, "exact removal succeeds")
  assert_equal(removed, 2, "root and dependent chain removed")

  local body = read_file()
  assert_contains(body, "# xmjd6 candidate order", "header preserved")
  assert_not_contains(body, "皮佬\tpklz", "selected root removed")
  assert_not_contains(body, "疲劳\tpklz\t疲痨", "dependent chain removed")
  assert_contains(body, "AI\tai\t阝\tai", "unrelated rule preserved")
end

local function test_exact_removal_rejects_stale_record_identity()
  seed_records()
  local stale = core.record_at_line(3, "candidate_order.txt")
  local before = read_file():gsub("皮佬\tpklz\t疲劳\tpklz\tpklzo", "皮老\tpklz\t疲劳\tpklz\tpklzo")
  write_file(before)

  local ok, removed = core.remove_record_and_dependents(stale, order_path)
  assert_true(ok, "stale removal is a safe no-op")
  assert_equal(removed, 0, "stale record removes nothing")
  assert_equal(read_file(), before, "stale identity leaves current file unchanged")
end

local function translator_env(enabled)
  return {
    engine = {
      context = {
        get_option = function() return enabled ~= false end,
      },
      schema = {
        config = {
          get_string = function(_, key)
            if key == "candidate_order/store_file" then return "candidate_order.txt" end
            return nil
          end,
          get_bool = function() return enabled ~= false end,
        },
      },
    },
  }
end

local function run_translator(input, state, enabled)
  local yielded = {}
  _G.__candidate_order_manager_state = state or {}
  _G.Candidate = function(cand_type, start_pos, end_pos, text, comment)
    return {
      type = cand_type,
      start = start_pos,
      _end = end_pos,
      text = text,
      comment = comment or "",
      quality = 0,
    }
  end
  _G.yield = function(cand)
    yielded[#yielded + 1] = cand
  end
  package.loaded["xmjd6.candidate_order"] = nil
  local translator = require("xmjd6.candidate_order")
  translator(input, { start = 0, _end = #input }, translator_env(enabled))
  return yielded
end

local function test_translator_lists_and_filters_tuning_records()
  seed_records()

  local all = run_translator("=tp")
  assert_equal(#all, 3, "tuning management candidate count")
  assert_equal(all[1].type, "candidate_order_manager", "tuning manager type")
  assert_equal(all[1].text, "pklz：皮佬置顶", "tuning manager text")
  assert_equal(
    all[1].comment,
    "原码pklz；疲劳→pklzo〔调频·第3行·按0撤销〕",
    "tuning manager details"
  )
  assert_equal(all[3].text, "ai：AI置顶", "tuning manager file order")

  local filtered = run_translator("=tp疲痨")
  assert_equal(#filtered, 1, "tuning manager filtered count")
  assert_equal(filtered[1].text, "pklzo：疲劳置顶", "tuning manager filtered result")
end

local function test_translator_shows_confirmation_notice_and_empty_states()
  seed_records()
  local pending_state = {
    pending_delete = {
      input = "=tp",
      record = core.record_at_line(3, "candidate_order.txt"),
    },
  }
  local pending = run_translator("=tp", pending_state)
  assert_equal(#pending, 1, "tuning confirmation replaces list")
  assert_equal(pending[1].type, "candidate_order_delete_confirm", "tuning confirmation type")
  assert_equal(pending[1].text, "确认撤销：pklz / 皮佬", "tuning confirmation text")
  assert_equal(pending[1].comment, "恢复疲劳〔再按0确认，其他键取消〕", "tuning confirmation comment")

  local notice_state = {
    manager_notice = { input = "=tp", message = "已撤销调频，共清理2条", ok = true },
  }
  local notice = run_translator("=tp", notice_state)
  assert_equal(notice[1].type, "candidate_order_manager_notice", "tuning notice type")
  assert_equal(notice[1].text, "已撤销调频，共清理2条", "tuning notice text")
  assert_equal(notice[2].type, "candidate_order_manager", "records follow notice")

  write_file("# xmjd6 candidate order\n")
  local empty = run_translator("=tp")
  assert_equal(#empty, 1, "empty tuning candidate count")
  assert_equal(empty[1].type, "candidate_order_manager_empty", "empty tuning type")
  assert_equal(empty[1].text, "暂无动态调频", "empty tuning text")
end

local function test_management_remains_available_when_runtime_tuning_is_disabled()
  seed_records()
  local manager = run_translator("=tp", nil, false)
  assert_equal(#manager, 3, "disabled runtime still exposes manager")

  local normal = run_translator("pklz", nil, false)
  assert_equal(#normal, 0, "disabled runtime still hides normal tuning candidates")
end

local tests = {
  test_search_records_filters_all_fields_in_file_order,
  test_record_at_line_and_exact_removal_cleans_dependent_chain,
  test_exact_removal_rejects_stale_record_identity,
  test_translator_lists_and_filters_tuning_records,
  test_translator_shows_confirmation_notice_and_empty_states,
  test_management_remains_available_when_runtime_tuning_is_disabled,
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
print("candidate order manager tests passed")
