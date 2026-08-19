# Bounded Single-Character-First Filter Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable a configurable Lua filter that stably promotes single-character candidates within the first 20 results while adding bounded, near-constant latency and never dropping the remaining stream.

**Architecture:** Replace the current scan-and-truncate implementation with a prefix-only stable partition. Read `enabled` and `scan_limit` once during component initialization, classify at most 20 UTF-8 candidate texts before streaming the untouched suffix, and place the filter first in the schema chain so prefetch does not multiply downstream filter work. A pure Lua regression harness and benchmark measure ordering, pull counts, and CPU overhead.

**Tech Stack:** Lua 5.4-compatible librime-lua component, Rime schema YAML, pure Lua tests and microbenchmark, isolated `rime_deployer` compile.

---

### Task 1: Define bounded ordering and lazy-pull contracts

**Files:**
- Create: `tests/test_single_char_first.lua`
- Modify later: `lua/xmjd6/xmjd6_single_char.lua`

**Step 1: Write the failing test harness**

Create candidate and stream helpers that expose how many upstream candidates
have been pulled:

```lua
local function candidate(text)
  return { type = "table", text = text, comment = "" }
end

local function stream(texts)
  local state = { pulled = 0 }
  function state:iter()
    local index = 0
    return function()
      index = index + 1
      local text = texts[index]
      if not text then return nil end
      state.pulled = state.pulled + 1
      return candidate(text)
    end
  end
  return state
end
```

Load the planned table API:

```lua
local filter = require("xmjd6.xmjd6_single_char")
assert(type(filter.init) == "function")
assert(type(filter.func) == "function")
assert(type(filter.is_single_codepoint) == "function")
```

Add focused tests for:

- ASCII, three-byte CJK, and four-byte CJK single code points.
- Empty strings, phrases, and joined emoji sequences as non-single text.
- Stable partition of the first 20 candidates.
- Candidate 21 and every suffix candidate retaining relative order.
- No lost candidates.
- Disabled and `scan_limit < 2` direct pass-through.
- A no-single prefix pulling exactly 20 candidates before first output.
- An early single at position 2 yielding after only two pulls.

Use a sentinel error from the test's global `yield` function to stop at the
first emitted candidate and inspect `state.pulled` without exhausting the
stream.

**Step 2: Run the test to verify RED**

Run:

```bash
lua tests/test_single_char_first.lua
```

Expected: FAIL because the current module returns a bare function and does not
implement the bounded stream contract.

**Step 3: Commit the contract test**

```bash
git add -f tests/test_single_char_first.lua
git commit -m "test(xmjd6): define bounded single-char ordering"
```

### Task 2: Implement the bounded Lua filter

**Files:**
- Modify: `lua/xmjd6/xmjd6_single_char.lua`
- Test: `tests/test_single_char_first.lua`

**Step 1: Add constant-time UTF-8 classification**

Implement a first-byte width check and validate continuation bytes:

```lua
local function is_single_codepoint(text)
  if type(text) ~= "string" then return false end
  local size = #text
  if size < 1 or size > 4 then return false end
  local first = string.byte(text, 1)
  local width
  if first < 0x80 then width = 1
  elseif first >= 0xC2 and first <= 0xDF then width = 2
  elseif first >= 0xE0 and first <= 0xEF then width = 3
  elseif first >= 0xF0 and first <= 0xF4 then width = 4
  else return false end
  if size ~= width then return false end
  for index = 2, width do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte > 0xBF then return false end
  end
  return true
end
```

**Step 2: Cache configuration in `init`**

Read fixed schema keys once:

```lua
function M.init(env)
  local config = env.engine.schema.config
  local enabled = config:get_bool("xmjd6_single_char/enabled")
  local limit = config:get_int("xmjd6_single_char/scan_limit")
  env.single_char_first_enabled = enabled ~= false
  env.single_char_first_scan_limit = math.max(0, tonumber(limit) or 20)
end
```

Avoid `pcall` and config lookup in the candidate hot path.

**Step 3: Implement prefix-only stable partitioning**

Use one iterator instance for both the prefix and suffix:

```lua
function M.func(input, env)
  if not input or type(input.iter) ~= "function" then return end
  local limit = env and env.single_char_first_scan_limit or 20
  if env and env.single_char_first_enabled == false or limit < 2 then
    for cand in input:iter() do yield(cand) end
    return
  end

  local iter = input:iter()
  local words = {}
  local scanned = 0
  for cand in iter do
    scanned = scanned + 1
    if is_single_codepoint(cand and cand.text) then
      yield(cand)
    else
      words[#words + 1] = cand
    end
    if scanned >= limit then break end
  end
  for index = 1, #words do yield(words[index]) end
  for cand in iter do yield(cand) end
end
```

Return `M` with `init`, `func`, and the testable classifier.

**Step 4: Run the focused test to verify GREEN**

Run `lua tests/test_single_char_first.lua`.

Expected: all ordering, preservation, configuration, and pull-count tests pass.

**Step 5: Commit**

```bash
git add lua/xmjd6/xmjd6_single_char.lua
git add -f tests/test_single_char_first.lua
git commit -m "perf(xmjd6): bound single-char candidate ordering"
```

### Task 3: Enable the filter and expose configuration

**Files:**
- Modify: `xmjd6.schema.yaml`
- Modify: `tests/test_single_char_first.lua`

**Step 1: Add failing schema assertions**

Read `xmjd6.schema.yaml` in the Lua test and require:

```lua
assert(schema:find("lua_filter@%*xmjd6/xmjd6_single_char"))
assert(schema:find("xmjd6_single_char:"))
assert(schema:find("enabled: true"))
assert(schema:find("scan_limit: 20"))
```

Also compare the filter line position with `- simplifier` and require the
single-character filter to appear first.

**Step 2: Run the test to verify RED**

Expected: FAIL because the filter line is commented and no config section
exists.

**Step 3: Update the schema**

At the beginning of `engine/filters`, add:

```yaml
    - lua_filter@*xmjd6/xmjd6_single_char # 前20候选内单字稳定优先，后续候选流式透传
```

Remove the obsolete disabled line. Near other Lua component settings add:

```yaml
xmjd6_single_char:
  enabled: true
  scan_limit: 20
```

**Step 4: Verify GREEN and compile syntax**

Run:

```bash
lua tests/test_single_char_first.lua
luac -p lua/xmjd6/xmjd6_single_char.lua
```

Expected: PASS.

**Step 5: Commit**

```bash
git add xmjd6.schema.yaml
git add -f tests/test_single_char_first.lua
git commit -m "feat(xmjd6): enable bounded single-char priority"
```

### Task 4: Measure and document performance

**Files:**
- Create: `scripts/benchmark_single_char_first.lua`
- Modify: `guide/功能说明.md`
- Create: `docs/plans/2026-08-19-bounded-single-char-first-performance.md`

**Step 1: Add a deterministic benchmark**

Implement three first-output paths over reusable fixture candidates:

- direct pass-through;
- the legacy 100-candidate scan behavior;
- the new configurable 20-candidate filter.

Use a no-single prefix so each implementation's worst-case prefetch is visible.
Stop at the first yielded candidate with a sentinel and report:

```text
pass-through: pulls=1, ns/op=...
legacy scan 100: pulls=100, ns/op=...
bounded scan 20: pulls=20, ns/op=...
```

Also benchmark complete 20-candidate streams to isolate Lua classification and
buffering overhead without comparing different output counts. Accept an
optional rounds argument and default to enough repetitions for stable output.
Do not add timing thresholds to regression tests.

**Step 2: Run the benchmark**

Run:

```bash
lua scripts/benchmark_single_char_first.lua 100000
```

Record hardware/runtime, rounds, elapsed values, percentage versus direct
pass-through, and the structural 80% prefetch reduction versus the former 100
candidate scan.

**Step 3: Update user documentation**

In `guide/功能说明.md`, document:

- the first-20 stable-partition behavior;
- why it is not a global scan;
- the `enabled` and `scan_limit` settings;
- `scan_limit: 0` as a pass-through option;
- the measured benchmark caveat that real Rime latency depends on upstream
  translators and the machine.

Write the exact local measurement to the performance record.

**Step 4: Commit**

```bash
git add scripts/benchmark_single_char_first.lua guide/功能说明.md
git add -f docs/plans/2026-08-19-bounded-single-char-first-performance.md
git commit -m "docs(xmjd6): benchmark single-char priority"
```

### Task 5: Run regressions and isolated Rime compilation

**Files:**
- No planned source changes.

**Step 1: Run focused and neighboring Lua tests**

```bash
lua tests/test_single_char_first.lua
lua tests/test_for_hint.lua
lua tests/test_cx_pinyin_hint.lua
lua tests/test_candidate_order_filter.lua 2>/dev/null || true
```

Run every available neighboring test directly; do not treat a nonexistent test
as a product failure.

**Step 2: Run Lua syntax checks**

```bash
luac -p lua/xmjd6/xmjd6_single_char.lua
```

Expected: exit zero.

**Step 3: Compile the schema in an isolated temporary directory**

Copy tracked Rime source files to a temporary user-data directory, excluding
`build/`, user databases, `installation.yaml`, `user.yaml`, and the user's
untracked `default.yaml`. Run the local Squirrel `rime_deployer --compile` and
require non-empty schema/table/prism/reverse artifacts.

**Step 4: Verify local-state isolation**

```bash
git status --short
git diff -- installation.yaml user.yaml
```

Expected: the pre-existing modified `installation.yaml`, modified `user.yaml`,
and untracked `default.yaml` remain untouched and uncommitted.

**Step 5: Push main only after all verification passes**

```bash
git push origin main
```

Expected: the remote main branch advances without force and without a pull
request.
