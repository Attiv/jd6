package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./?.lua",
  package.path,
}, ";")

local core = require("xmjd6.dynamic_phrase_core")
local mem_cleaner = require("xmjd6.mem_cleaner")

local tmp_path = os.tmpname()
os.remove(tmp_path)

local function cleanup()
  os.remove(tmp_path)
end

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", label or "assert_equal", tostring(expected), tostring(actual)), 2)
  end
end

local function assert_true(value, label)
  if not value then
    error(label or "assert_true failed", 2)
  end
end


local function write_file(path, body)
  local f = assert(io.open(path, "w"))
  f:write(body)
  f:close()
end

local function count_mem_releasers()
  local n = 0
  for _ in pairs(mem_cleaner.releasers or {}) do
    n = n + 1
  end
  return n
end

local function test_dynamic_phrase_cache_registers_mem_releaser()
  assert_true(count_mem_releasers() >= 1, "dynamic phrase cache should register a mem_cleaner releaser")
end

local function test_mem_cleaner_release_all_clears_dynamic_phrase_cache()
  local old_lfs = package.loaded["lfs"]
  package.loaded["lfs"] = { attributes = function() return 123456 end }
  core.clear_cache()

  write_file(tmp_path, "aa\tzz\n")
  local first = core.lookup("zz", tmp_path)
  assert_equal(first[1].text, "aa", "first cached text")

  write_file(tmp_path, "bb\tzz\n")
  local cached = core.lookup("zz", tmp_path)
  assert_equal(cached[1].text, "aa", "precondition: unchanged mtime keeps cache")

  mem_cleaner.release_all()
  local refreshed = core.lookup("zz", tmp_path)
  assert_equal(refreshed[1].text, "bb", "release_all clears dynamic phrase cache")

  package.loaded["lfs"] = old_lfs
end

local function test_add_single_code_uses_last_committed_text()
  local cmd = core.resolve_command("=add/wyy", "王宥宥")
  assert_equal(cmd.action, "add", "action")
  assert_equal(cmd.text, "王宥宥", "text from last commit")
  assert_equal(cmd.code, "wyy", "code")
  assert_true(cmd.from_last_commit, "marks last-commit shorthand")
end

local function test_add_chunk_count_joins_recent_commits()
  local history = { "王", "宥宥" }
  local cmd = core.resolve_command("=add/2/wyy", history)
  assert_equal(cmd.action, "add", "action")
  assert_equal(cmd.text, "王宥宥", "joined text")
  assert_equal(cmd.code, "wyy", "code")
  assert_equal(cmd.chunk_count, 2, "chunk count")
  assert_true(cmd.from_last_commit, "marks history shorthand")
end

local function test_apply_add_chunk_count_joins_recent_commits()
  local ok, message = core.apply_command("=add/2/wyy", tmp_path, { "王", "宥宥" })
  assert_true(ok, message)
  local matches = core.lookup("wyy", tmp_path)
  assert_equal(#matches, 1, "lookup count")
  assert_equal(matches[1].text, "王宥宥", "stored joined text")
end

local function test_delete_chunk_count_joins_recent_commits()
  local history = { "王", "宥宥" }
  assert_true(core.apply_command("=add/2/wyy", tmp_path, history))

  local cmd = core.resolve_command("=del/2/wyy", history)
  assert_equal(cmd.action, "del", "action")
  assert_equal(cmd.text, "王宥宥", "joined text")
  assert_equal(cmd.code, "wyy", "code")

  local ok, message, removed = core.apply_command("=del/2/wyy", tmp_path, history)
  assert_true(ok, message)
  assert_equal(removed, 1, "removed count")
  assert_equal(#core.lookup("wyy", tmp_path), 0, "deleted lookup")
end



local function test_add_count_without_code_is_incomplete_not_code_two()
  local preview, comment = core.command_preview("=add/2", { "王", "宥宥" })
  assert_equal(preview, nil, "preview should be incomplete")
  assert_equal(comment, "继续输入 /编码：=add/2/编码", "incomplete count hint")
end

local function test_delete_by_code_execute_suffix_removes_all_matching_dynamic_entries()
  assert_true(core.apply_command("=add/王宥宥/wyy", tmp_path))
  assert_true(core.apply_command("=add/汪又又/wyy", tmp_path))
  assert_true(core.apply_command("=add/别的词/byc", tmp_path))

  local ok, message, removed = core.apply_command("=del/wyy;", tmp_path, { "不是这个词" })
  assert_true(ok, message)
  assert_equal(removed, 2, "removed count")
  assert_equal(#core.lookup("wyy", tmp_path), 0, "wyy removed")
  assert_equal(#core.lookup("byc", tmp_path), 1, "other code remains")
end

local function test_parse_add_command_with_execute_suffix()
  local cmd = core.parse_command("=add/王宥宥/wyy;")
  assert_equal(cmd.action, "add", "action")
  assert_equal(cmd.text, "王宥宥", "text")
  assert_equal(cmd.code, "wyy", "code")
  assert_true(cmd.execute_suffix, "marks semicolon execute suffix")
end

local function test_resolve_chunk_count_with_execute_suffix()
  local history = { "王", "宥宥" }
  local cmd = core.resolve_command("=add/2/wyy;", history)
  assert_equal(cmd.action, "add", "action")
  assert_equal(cmd.text, "王宥宥", "joined text")
  assert_equal(cmd.code, "wyy", "code")
  assert_true(cmd.execute_suffix, "marks semicolon execute suffix")
end

local function test_parse_del_command_with_execute_suffix()
  local cmd = core.parse_command("=del/王宥宥/wyy;")
  assert_equal(cmd.action, "del", "action")
  assert_equal(cmd.text, "王宥宥", "text")
  assert_equal(cmd.code, "wyy", "code")
  assert_true(cmd.execute_suffix, "marks semicolon execute suffix")
end

local function test_parse_add_command_with_pasted_text_still_works()
  local cmd = core.parse_command("=add/王宥宥/wyy")
  assert_equal(cmd.action, "add", "action")
  assert_equal(cmd.text, "王宥宥", "text")
  assert_equal(cmd.code, "wyy", "code")
end

local function test_parse_del_command_with_optional_code()
  local cmd = core.parse_command("=del/AI搭子/aidz")
  assert_equal(cmd.action, "del", "action")
  assert_equal(cmd.text, "AI搭子", "text")
  assert_equal(cmd.code, "aidz", "code")

  local by_text = core.parse_command("=del/AI搭子")
  assert_equal(by_text.action, "del", "action by text")
  assert_equal(by_text.text, "AI搭子", "text by text")
  assert_equal(by_text.code, nil, "code by text")
end

local function test_add_phrase_and_lookup_by_code()
  local ok, message = core.apply_command("=add/王宥宥/wyy", tmp_path)
  assert_true(ok, message)

  local rows = core.load_entries(tmp_path)
  assert_equal(#rows, 1, "row count")
  assert_equal(rows[1].text, "王宥宥", "stored text")
  assert_equal(rows[1].code, "wyy", "stored code")

  local matches = core.lookup("wyy", tmp_path)
  assert_equal(#matches, 1, "lookup count")
  assert_equal(matches[1].text, "王宥宥", "lookup text")
end

local function test_add_updates_existing_text_code_instead_of_duplicating()
  assert_true(core.apply_command("=add/王宥宥/wyy", tmp_path))
  assert_true(core.apply_command("=add/王宥宥/wyy", tmp_path))

  local rows = core.load_entries(tmp_path)
  assert_equal(#rows, 1, "dedup row count")
end

local function test_delete_by_text_removes_all_codes_for_text()
  assert_true(core.apply_command("=add/王宥宥/wyy", tmp_path))
  assert_true(core.apply_command("=add/王宥宥/wyyv", tmp_path))

  local ok, message, removed = core.apply_command("=del/王宥宥", tmp_path)
  assert_true(ok, message)
  assert_equal(removed, 2, "removed count")
  assert_equal(#core.lookup("wyy", tmp_path), 0, "lookup after delete")
end

local function test_delete_by_text_and_code_is_precise()
  assert_true(core.apply_command("=add/AI搭子/aidz", tmp_path))
  assert_true(core.apply_command("=add/AI搭子/aidzv", tmp_path))

  local ok, message, removed = core.apply_command("=del/AI搭子/aidz", tmp_path)
  assert_true(ok, message)
  assert_equal(removed, 1, "removed count")

  local old = core.lookup("aidz", tmp_path)
  local remain = core.lookup("aidzv", tmp_path)
  assert_equal(#old, 0, "old removed")
  assert_equal(#remain, 1, "other code remains")
  assert_equal(remain[1].text, "AI搭子", "remaining text")
end

local tests = {
  test_dynamic_phrase_cache_registers_mem_releaser,
  test_mem_cleaner_release_all_clears_dynamic_phrase_cache,
  test_add_single_code_uses_last_committed_text,
  test_add_chunk_count_joins_recent_commits,
  test_apply_add_chunk_count_joins_recent_commits,
  test_delete_chunk_count_joins_recent_commits,
  test_add_count_without_code_is_incomplete_not_code_two,
  test_delete_by_code_execute_suffix_removes_all_matching_dynamic_entries,
  test_parse_add_command_with_execute_suffix,
  test_resolve_chunk_count_with_execute_suffix,
  test_parse_del_command_with_execute_suffix,
  test_parse_add_command_with_pasted_text_still_works,
  test_parse_del_command_with_optional_code,
  test_add_phrase_and_lookup_by_code,
  test_add_updates_existing_text_code_instead_of_duplicating,
  test_delete_by_text_removes_all_codes_for_text,
  test_delete_by_text_and_code_is_precise,
}

for i, test in ipairs(tests) do
  cleanup()
  local ok, err = pcall(test)
  cleanup()
  if not ok then
    io.stderr:write(string.format("not ok %d - %s\n%s\n", i, debug.getinfo(test, "n").name or "test", err))
    os.exit(1)
  end
  print(string.format("ok %d", i))
end

print(string.format("%d tests passed", #tests))
