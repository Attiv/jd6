# Dynamic Phrase Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an in-Rime `=del/` panel that lists, filters, confirms, and precisely deletes dynamic phrases with two presses of `0`.

**Architecture:** Extend the existing dynamic-phrase core with a side-effect-free query helper, let the existing translator render typed management/confirmation/status candidates, and let the existing processor own the double-`0` state machine. Exact deletion continues through `dynamic_phrase_core.delete_phrase`, preserving candidate-order cleanup.

**Tech Stack:** Lua, librime-lua `Candidate`/processor APIs, YAML schema integration, direct Lua regression tests.

---

### Task 1: Define management query behavior

**Files:**
- Create: `tests/test_dynamic_phrase_manager.lua`
- Modify: `lua/xmjd6/dynamic_phrase_core.lua`

**Step 1: Write the failing test**

Create a temporary `dynamic_phrases.txt` containing multiple phrases and assert
that the wished-for API behaves as follows:

```lua
local all = core.search_entries("", phrase_path)
assert_equal(#all, 3)

local by_code = core.search_entries("pkl", phrase_path)
assert_equal(by_code[1].text, "皮佬")

local by_text = core.search_entries("鱼", phrase_path)
assert_equal(by_text[1].code, "ynzqu")
```

Also verify that matching is a plain substring, preserves file order, and does
not return the mutable cached table itself.

**Step 2: Run test to verify it fails**

Run: `lua tests/test_dynamic_phrase_manager.lua`

Expected: FAIL because `core.search_entries` is undefined.

**Step 3: Write minimal implementation**

Add `M.search_entries(query, path)` beside the existing lookup helpers:

```lua
function M.search_entries(query, path)
    query = trim(query)
    local out = {}
    for _, entry in ipairs(M.load_entries(path)) do
        if query == ""
            or entry.text:find(query, 1, true)
            or entry.code:find(query:lower(), 1, true) then
            out[#out + 1] = { text = entry.text, code = entry.code }
        end
    end
    return out
end
```

**Step 4: Run test to verify it passes**

Run: `lua tests/test_dynamic_phrase_manager.lua`

Expected: query assertions PASS.

**Step 5: Commit**

```bash
git add -f tests/test_dynamic_phrase_manager.lua
git add lua/xmjd6/dynamic_phrase_core.lua
git commit -m "feat(xmjd6): query dynamic phrases for management"
```

### Task 2: Render the management and confirmation candidates

**Files:**
- Modify: `tests/test_dynamic_phrase_manager.lua`
- Modify: `lua/xmjd6/dynamic_phrase.lua`

**Step 1: Write the failing tests**

Stub librime-lua `Candidate` and `yield`, then assert:

- `=del/` yields every stored entry in file order;
- `=del/pkl` yields only matching text/code entries;
- management candidates have type `dynamic_phrase_manager` and expose the code
  without encoding identity into visible phrase text;
- a matching pending state yields one `dynamic_phrase_delete_confirm`
  candidate;
- an empty store yields an informational candidate;
- `=del/word/code` and semicolon commands still use the existing command
  preview path.

**Step 2: Run test to verify it fails**

Run: `lua tests/test_dynamic_phrase_manager.lua`

Expected: FAIL because `=del/` still yields only the usage preview.

**Step 3: Write minimal implementation**

In `dynamic_phrase.lua`:

- recognize `^=del/([^/;]*)$` as management input;
- read transient state from `_G.__dynamic_phrase_state`;
- yield management candidates with code comments and a `0` deletion hint;
- yield a confirmation candidate when `pending_delete.input == input`;
- yield status/empty candidates when appropriate;
- fall back to `command_candidate` for all other command shapes.

Expose the translator as the existing callable module so schema integration is
unchanged.

**Step 4: Run test to verify it passes**

Run: `lua tests/test_dynamic_phrase_manager.lua`

Expected: translator assertions PASS.

**Step 5: Commit**

```bash
git add -f tests/test_dynamic_phrase_manager.lua
git add lua/xmjd6/dynamic_phrase.lua
git commit -m "feat(xmjd6): show dynamic phrase deletion panel"
```

### Task 3: Implement double-0 confirmation and exact deletion

**Files:**
- Modify: `tests/test_dynamic_phrase_manager.lua`
- Modify: `lua/xmjd6/dynamic_phrase_processor.lua`

**Step 1: Write the failing processor tests**

Build small key/context/engine mocks and verify:

1. First `0` on a `dynamic_phrase_manager` candidate returns accepted, stores
   `{input, text, code}`, refreshes composition, and does not alter the file.
2. Second `0` deletes exactly the stored phrase/code pair, including the case
   where the same phrase has another code.
3. A non-`0` key clears pending confirmation and returns no-op.
4. Changing `context.input` invalidates stale confirmation.
5. A delete write failure is surfaced as a notice and does not clear the
   composition.
6. Existing semicolon, space, and Return command execution still works.

**Step 2: Run test to verify it fails**

Run: `lua tests/test_dynamic_phrase_manager.lua`

Expected: FAIL because `0` is currently ignored by the dynamic phrase
processor.

**Step 3: Write minimal implementation**

Add a management branch before `is_confirm_key`:

```lua
if is_zero_key(key) then
    return handle_manager_zero(context, env)
end
cancel_stale_pending(context)
```

The first press validates `candidate.type == "dynamic_phrase_manager"` and
stores exact identity. The second press calls:

```lua
core.delete_phrase(
    pending.text,
    pending.code,
    get_store_path(env),
    get_candidate_order_store_path(env)
)
```

Store the returned message as a transient notice and call
`context:refresh_non_confirmed_composition()` through `pcall` after state
changes.

**Step 4: Run test to verify it passes**

Run: `lua tests/test_dynamic_phrase_manager.lua`

Expected: all manager state-machine assertions PASS.

**Step 5: Run existing dynamic phrase regressions**

Run:

```bash
lua tests/test_dynamic_phrase_core.lua
lua tests/test_dynamic_phrase_candidate_order_cleanup.lua
```

Expected: both existing suites PASS.

**Step 6: Commit**

```bash
git add -f tests/test_dynamic_phrase_manager.lua
git add lua/xmjd6/dynamic_phrase_processor.lua
git commit -m "feat(xmjd6): delete managed phrases with double zero"
```

### Task 4: Document and verify the integrated behavior

**Files:**
- Modify: `guide/功能说明.md`
- Modify: `lua/xmjd6/xmjd6_tools.lua`

**Step 1: Update user-facing help**

Document:

```text
=del/                 open the dynamic phrase manager
=del/query            filter by phrase or code
highlight + 0 + 0     precisely delete the selected phrase/code pair
```

Add the management entry to `=?` help. Mention that direct candidate tapping
commits text and is not the deletion action. Record `=tp` as the reserved name
for a future dynamic-tuning management panel, without registering a recognizer
or adding incomplete runtime behavior.

**Step 2: Run focused verification**

Run:

```bash
lua tests/test_dynamic_phrase_manager.lua
lua tests/test_dynamic_phrase_core.lua
lua tests/test_dynamic_phrase_candidate_order_cleanup.lua
lua tests/test_single_char_first.lua
```

Expected: all focused Lua suites PASS.

**Step 3: Check source/schema consistency**

Run:

```bash
rg -n "dynamic_phrase_processor|dynamic_phrase|=del/|=tp" \
  xmjd6.schema.yaml lua/xmjd6 guide/功能说明.md
git diff --check
```

Expected: processor ordering remains dynamic phrase before candidate order;
`=tp` is documentation-only; no whitespace errors.

**Step 4: Commit**

```bash
git add guide/功能说明.md lua/xmjd6/xmjd6_tools.lua
git commit -m "docs(xmjd6): explain dynamic phrase manager"
```

### Task 5: Final runtime smoke test

**Files:**
- No source changes expected.

**Step 1: Back up runtime files**

Copy `dynamic_phrases.txt` and `candidate_order.txt` to temporary files. Do not
stage or commit their runtime contents.

**Step 2: Deploy Rime configuration**

Use the project's normal local deployment command available on this machine.

**Step 3: Manually verify**

- Enter `=del/` and confirm the stored phrase appears.
- Press `0` once and confirm the panel asks for confirmation.
- Press a non-`0` key and confirm deletion is cancelled.
- Repeat and press `0` twice; confirm the exact phrase disappears.
- Restore runtime files from the backups and redeploy if necessary.

**Step 4: Record evidence**

Capture the deployment result, test command outputs, `git status --short`, and
the final diff summary. Do not claim completion unless these fresh checks pass.
