local root = (... and ... ~= "") and ... or "."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local now_ms = 0
local data_dir = os.tmpname()
os.remove(data_dir)
local yielded = {}
local cleanup_callback

package.preload["xmjd6.mem_cleaner"] = function()
    return {
        register = function(fn) cleanup_callback = fn end,
    }
end

_G.rime_api = {
    get_user_data_dir = function() return data_dir end,
    get_time_ms = function() return now_ms end,
}

_G.Candidate = function(kind, start_pos, end_pos, text, comment)
    return {
        type = kind,
        start = start_pos,
        _end = end_pos,
        text = text,
        comment = comment,
    }
end

_G.yield = function(candidate)
    yielded[#yielded + 1] = candidate
end

local function fail(message)
    error(message, 2)
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        fail(string.format("%s: expected %s, got %s",
            message or "values differ", tostring(expected), tostring(actual)))
    end
end

local function assert_contains(value, needle, message)
    if type(value) ~= "string" or not value:find(needle, 1, true) then
        fail(string.format("%s: expected %q to contain %q",
            message or "substring missing", tostring(value), needle))
    end
end

local function split_tabs(line)
    local fields = {}
    for value in (line .. "\t"):gmatch("(.-)\t") do
        fields[#fields + 1] = value
    end
    return fields
end

local function reset_dir()
    os.execute("rm -rf " .. data_dir)
    assert(os.execute("mkdir -p " .. data_dir))
end

local function write_stats(content)
    local file = assert(io.open(data_dir .. "/typing_stats.txt", "w"))
    file:write(content)
    file:close()
end

local function read_stats()
    local file = assert(io.open(data_dir .. "/typing_stats.txt", "r"))
    local content = file:read("*a")
    file:close()
    return content
end

local function context()
    local ctx = {
        input = "",
        commit_text = "",
        ascii_mode = false,
    }
    function ctx:get_option(name)
        return name == "ascii_mode" and self.ascii_mode or false
    end
    function ctx:get_commit_text()
        return self.commit_text
    end
    return ctx
end

local function key_event(code)
    local event = { keycode = code }
    function event:release() return false end
    function event:ctrl() return false end
    function event:alt() return false end
    function event:super() return false end
    return event
end

local function fresh_module()
    package.loaded["xmjd6.typing_stats"] = nil
    _G.__typing_stats = nil
    yielded = {}
    cleanup_callback = nil
    now_ms = 0
    return require("xmjd6.typing_stats")
end

local function make_env(ctx)
    return { engine = { context = ctx } }
end

local function type_and_commit(stats, env, ctx, timestamp_ms, text, input)
    now_ms = timestamp_ms
    ctx.input = input or ""
    stats.processor(key_event(string.byte("a")), env)
    ctx.input = (input or "") .. "a"
    ctx.commit_text = text
    stats.on_commit(ctx)
    ctx.input = ""
    ctx.commit_text = ""
end

local function report(stats, env)
    yielded = {}
    stats.translator("=stats", { start = 0, _end = 6 }, env)
    assert_equal(#yielded, 3, "=stats candidate count")
    return yielded
end

local tests = {}

function tests.legacy_eight_column_rows_seed_average_but_not_peak()
    reset_dir()
    local today = os.date("%Y-%m-%d")
    write_stats(string.format("%s\t60\t120\t20\t2\t0\t30\t60\n", today))
    local stats = fresh_module()
    local ctx = context()
    local rows = report(stats, make_env(ctx))
    assert_contains(rows[1].comment, "均速 约120字/分", "legacy average")
    assert_contains(rows[1].comment, "峰速 -", "legacy peak")
end

function tests.hot_reload_upgrades_an_already_loaded_legacy_state()
    reset_dir()
    package.loaded["xmjd6.typing_stats"] = nil
    local today = os.date("%Y-%m-%d")
    _G.__typing_stats = {
        loaded = true,
        history = {},
        today = {
            day = today,
            chars = 60,
            keys = 120,
            commits = 20,
            backspaces = 2,
            sent_chars = 0,
            active_secs = 30,
            timed_chars = 60,
        },
        dirty = 0,
        last_flush = 0,
    }
    local stats = require("xmjd6.typing_stats")
    local rows = report(stats, make_env(context()))
    assert_contains(rows[1].comment, "均速 约120字/分", "hot reload average")
    assert_contains(rows[1].comment, "峰速 -", "hot reload peak")
end

function tests.continuous_trace_reports_session_average_and_ten_second_peak()
    reset_dir()
    local stats = fresh_module()
    local ctx = context()
    local env = make_env(ctx)
    type_and_commit(stats, env, ctx, 0, "一二三")
    type_and_commit(stats, env, ctx, 5000, "四五六")
    type_and_commit(stats, env, ctx, 10000, "七八九")
    type_and_commit(stats, env, ctx, 15000, "十天地")
    local rows = report(stats, env)
    assert_contains(rows[1].comment, "均速 约48字/分", "precise average")
    assert_contains(rows[1].comment, "峰速 54字/分", "ten-second peak")
end

function tests.idle_gap_is_not_included_in_average_duration()
    reset_dir()
    local stats = fresh_module()
    local ctx = context()
    local env = make_env(ctx)
    type_and_commit(stats, env, ctx, 0, "一二三四五")
    type_and_commit(stats, env, ctx, 5000, "六七八九十")
    type_and_commit(stats, env, ctx, 11000, "天地玄黄宇")
    type_and_commit(stats, env, ctx, 16000, "宙洪荒日月")
    type_and_commit(stats, env, ctx, 21000, "盈昃辰宿列")
    local rows = report(stats, env)
    assert_contains(rows[1].comment, "均速 约100字/分", "idle gap exclusion")
    assert_contains(rows[1].comment, "峰速 90字/分", "second-session peak")
end

function tests.stats_command_does_not_start_a_speed_sample()
    reset_dir()
    local stats = fresh_module()
    local ctx = context()
    local env = make_env(ctx)

    now_ms = 0
    ctx.input = ""
    stats.processor(key_event(string.byte("=")), env)
    now_ms = 500
    ctx.input = "="
    stats.processor(key_event(string.byte("s")), env)

    type_and_commit(stats, env, ctx, 1000, "一二三")
    type_and_commit(stats, env, ctx, 6000, "四五六")
    type_and_commit(stats, env, ctx, 11000, "七八九")
    type_and_commit(stats, env, ctx, 16000, "十天地")
    local rows = report(stats, env)
    assert_contains(rows[1].comment, "均速 约48字/分", "command exclusion average")
    assert_contains(rows[1].comment, "峰速 54字/分", "command exclusion peak")
end

function tests.large_commit_is_excluded_and_splits_speed_sessions()
    reset_dir()
    local stats = fresh_module()
    local ctx = context()
    local env = make_env(ctx)
    type_and_commit(stats, env, ctx, 0, "一二三")
    type_and_commit(stats, env, ctx, 5000, "四五六")
    type_and_commit(stats, env, ctx, 7000, "天地玄黄宇宙洪荒日月盈")
    type_and_commit(stats, env, ctx, 8000, "七八九")
    type_and_commit(stats, env, ctx, 13000, "十天地")
    type_and_commit(stats, env, ctx, 18000, "玄黄宇")
    type_and_commit(stats, env, ctx, 23000, "宙洪荒")
    local rows = report(stats, env)
    assert_contains(rows[1].comment, "均速 约54字/分", "large commit exclusion")
    assert_contains(rows[1].comment, "峰速 54字/分", "post-paste peak")
end

function tests.speed_aggregates_survive_flush_and_reload()
    reset_dir()
    local stats = fresh_module()
    local ctx = context()
    local env = make_env(ctx)
    type_and_commit(stats, env, ctx, 0, "一二三")
    type_and_commit(stats, env, ctx, 5000, "四五六")
    type_and_commit(stats, env, ctx, 10000, "七八九")
    type_and_commit(stats, env, ctx, 15000, "十天地")
    stats.fini_processor(env)

    local line = read_stats():match("([^\n]+)")
    local fields = split_tabs(line)
    assert_equal(#fields, 11, "persisted TSV column count")
    assert_equal(tonumber(fields[9]), 12, "persisted average characters")
    assert_equal(tonumber(fields[10]), 15000, "persisted average milliseconds")
    assert_equal(tonumber(fields[11]), 54, "persisted peak")

    stats = fresh_module()
    ctx = context()
    local rows = report(stats, make_env(ctx))
    assert_contains(rows[1].comment, "均速 约48字/分", "reloaded average")
    assert_contains(rows[1].comment, "峰速 54字/分", "reloaded peak")
end

function tests.failed_flush_keeps_dirty_stats_and_last_good_file()
    reset_dir()
    local stats=fresh_module()
    local ctx=context()
    local env=make_env(ctx)
    type_and_commit(stats,env,ctx,0,"甲")
    local before=read_stats()
    type_and_commit(stats,env,ctx,1000,"乙")
    local rename=os.rename
    os.rename=function() return nil,"injected rename failure" end
    stats.fini_processor(env)
    os.rename=rename
    assert_equal(read_stats(),before,"last good stats")
    assert_equal(_G.__typing_stats.dirty,1,"failed write retains dirty counter")
    stats.fini_processor(env)
    assert_equal(_G.__typing_stats.dirty,0,"retry saves pending stats")
    assert_equal(tonumber(split_tabs(read_stats():match("([^\n]+)"))[2]),2,"retry retains both characters")
end

function tests.automatic_flush_saves_an_active_average_sample_without_ending_it()
    reset_dir()
    local stats=fresh_module(); local ctx=context(); local env=make_env(ctx)
    for i=0,20 do type_and_commit(stats,env,ctx,i*1000,"甲") end
    local f=split_tabs(read_stats():match("([^\n]+)"))
    assert_equal(tonumber(f[9]),21,"checkpoint characters")
    assert_equal(tonumber(f[10]),20000,"checkpoint milliseconds")
    assert_equal(_G.__typing_stats.average_sample.characters,21,"save must not finish the live sample")
    stats=fresh_module()
    assert_contains(report(stats,make_env(context()))[1].comment,"均速 约63字/分","checkpoint survives restart")
end

function tests.malformed_today_row_cannot_replace_a_valid_row()
    reset_dir()
    local day=os.date("%Y-%m-%d")
    write_stats(day.."\t50\t150\t20\t2\t0\n"..day.."\tbroken\n")
    local rows=report(fresh_module(),make_env(context()))
    assert_contains(rows[1].text,"50 字","skip malformed duplicate")
end

function tests.fractional_negative_and_nonfinite_counters_are_rejected()
    reset_dir()
    local day=os.date("%Y-%m-%d")
    write_stats(day.."\t1.5\t3\t1\t0\t0\n"..day.."\t-1\t3\t1\t0\t0\n"..day.."\t1e999\t3\t1\t0\t0\n")
    assert_contains(report(fresh_module(),make_env(context()))[1].text,"0 字","invalid numeric rows skipped")
end

function tests.ratio_is_labelled_as_keys_per_han_not_exact_code_length()
    reset_dir(); local stats=fresh_module(); local ctx=context(); local env=make_env(ctx)
    type_and_commit(stats,env,ctx,0,"甲")
    assert_contains(report(stats,env)[1].text,"键/汉字","honest denominator label")
end

function tests.generated_candidates_do_not_contribute_to_speed()
    for _,kind in ipairs({"date","code_preview"}) do
        reset_dir(); local stats=fresh_module(); local ctx=context(); local env=make_env(ctx)
        function ctx:get_selected_candidate() return {type=kind} end
        for i=0,20 do type_and_commit(stats,env,ctx,i*1000,"年月日","rq") end
        assert_contains(report(stats,env)[1].comment,"均速 -",kind.." excluded from typing speed")
    end
end

local passed, failed = 0, 0
for name, test in pairs(tests) do
    io.write("TEST ", name, " ... ")
    local ok, err = xpcall(test, debug.traceback)
    if ok then
        passed = passed + 1
        io.write("PASS\n")
    else
        failed = failed + 1
        io.write("FAIL\n", err, "\n")
    end
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.execute("rm -rf " .. data_dir)
if failed > 0 then os.exit(1) end
