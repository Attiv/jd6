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
    cleanup()
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

local ok, err = pcall(test_search_entries_lists_and_filters_in_file_order)
cleanup()
if not ok then error(err, 0) end

print("dynamic phrase manager tests passed")
