#!/usr/bin/env lua

package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./?.lua",
  package.path,
}, ";")

local bounded = require("xmjd6.xmjd6_single_char")

local rounds = tonumber(arg[1]) or 100000
if rounds < 1 then error("rounds must be a positive integer") end

local candidates = {}
for index = 1, 1000 do
  candidates[index] = {
    type = "table",
    text = "候选词" .. tostring(index),
    comment = "编码",
  }
end

local function make_stream(limit)
  local stream = { pulled = 0 }
  function stream:iter()
    local index = 0
    local function next_candidate(iterator_state)
      index = index + 1
      if index > limit then return nil end
      iterator_state.pulled = iterator_state.pulled + 1
      return candidates[index]
    end
    return next_candidate, self
  end
  return stream
end

local function passthrough(input)
  for cand in input:iter() do yield(cand) end
end

local function legacy_is_priority(cand)
  if not cand or not cand.text then return false end
  if cand.comment and #cand.comment == 0 then return true end
  if cand.text:match("^%d%d%d%d%-%d%d%-%d%d$") then return true end
  if cand.comment == "Unix时间戳" then return true end
  local length = utf8.len(cand.text)
  return length ~= nil and length == 1
end

local function legacy_filter(input)
  local yielded = 0
  local scanned = 0
  local buffer = {}

  local function emit(cand)
    if yielded >= 50 then return false end
    yield(cand)
    yielded = yielded + 1
    return true
  end

  for cand in input:iter() do
    scanned = scanned + 1
    if legacy_is_priority(cand) then
      if not emit(cand) then break end
    else
      buffer[#buffer + 1] = cand
    end
    if yielded >= 50 or scanned >= 100 then break end
  end

  if yielded >= 50 then return end
  for index = 1, #buffer do
    if not emit(buffer[index]) then break end
  end
end

local bounded_env = {
  single_char_first_enabled = true,
  single_char_first_scan_limit = 20,
}

local function bounded_filter(input)
  return bounded.func(input, bounded_env)
end

local FIRST_YIELD = {}

local function benchmark_first_output(name, func, expected_pulls)
  local total_pulls = 0
  local old_yield = _G.yield
  _G.yield = function() error(FIRST_YIELD, 0) end
  local started = os.clock()
  for _ = 1, rounds do
    local stream = make_stream(1000)
    local ok, err = pcall(func, stream)
    if ok or err ~= FIRST_YIELD then
      _G.yield = old_yield
      error(name .. " did not stop at the first yield")
    end
    total_pulls = total_pulls + stream.pulled
  end
  local elapsed = os.clock() - started
  _G.yield = old_yield

  local pulls = total_pulls / rounds
  if pulls ~= expected_pulls then
    error(string.format("%s: expected %.0f pulls, got %.2f", name, expected_pulls, pulls))
  end
  return {
    name = name,
    elapsed = elapsed,
    ns_per_op = elapsed * 1000000000 / rounds,
    pulls = pulls,
  }
end

local function benchmark_complete_twenty(name, func)
  local total_yielded = 0
  local old_yield = _G.yield
  _G.yield = function() total_yielded = total_yielded + 1 end
  local started = os.clock()
  for _ = 1, rounds do
    func(make_stream(20))
  end
  local elapsed = os.clock() - started
  _G.yield = old_yield

  if total_yielded ~= rounds * 20 then
    error(string.format("%s: expected %d yields, got %d", name, rounds * 20, total_yielded))
  end
  return {
    name = name,
    elapsed = elapsed,
    ns_per_op = elapsed * 1000000000 / rounds,
  }
end

local first_results = {
  benchmark_first_output("pass-through", passthrough, 1),
  benchmark_first_output("legacy scan 100", legacy_filter, 100),
  benchmark_first_output("bounded scan 20", bounded_filter, 20),
}

local complete_results = {
  benchmark_complete_twenty("pass-through", passthrough),
  benchmark_complete_twenty("legacy scan 100", legacy_filter),
  benchmark_complete_twenty("bounded scan 20", bounded_filter),
}

local function percent_change(value, base)
  return (value / base - 1) * 100
end

print(string.format("Lua %s | rounds=%d", _VERSION, rounds))
print("worst-case time to first output (1000 multi-character candidates):")
for _, result in ipairs(first_results) do
  print(string.format(
    "  %-16s pulls=%3.0f  total=%8.4fs  %9.1f ns/op",
    result.name,
    result.pulls,
    result.elapsed,
    result.ns_per_op
  ))
end

print("complete 20-candidate stream:")
for _, result in ipairs(complete_results) do
  print(string.format(
    "  %-16s total=%8.4fs  %9.1f ns/op",
    result.name,
    result.elapsed,
    result.ns_per_op
  ))
end

print(string.format(
  "bounded first-output CPU vs pass-through: %+.1f%%",
  percent_change(first_results[3].ns_per_op, first_results[1].ns_per_op)
))
print(string.format(
  "bounded first-output CPU vs legacy: %+.1f%%",
  percent_change(first_results[3].ns_per_op, first_results[2].ns_per_op)
))
print(string.format(
  "bounded complete-20 CPU vs pass-through: %+.1f%%",
  percent_change(complete_results[3].ns_per_op, complete_results[1].ns_per_op)
))
print("structural guarantee: worst-case prefetch is 20 instead of 100 (80.0% fewer pulls)")
