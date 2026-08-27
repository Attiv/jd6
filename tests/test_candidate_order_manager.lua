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
_G.rime_api = {
  get_user_data_dir = function() return tmp_root end,
}

local core = require("xmjd6.candidate_order_core")
local order_path = tmp_root .. "/candidate_order.txt"

local function cleanup()
  os.remove(order_path)
  os.execute("rmdir " .. string.format("%q", tmp_root))
  _G.rime_api = old_rime_api
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

local tests = {
  test_search_records_filters_all_fields_in_file_order,
  test_record_at_line_and_exact_removal_cleans_dependent_chain,
  test_exact_removal_rejects_stale_record_identity,
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
