# Candidate Order Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `=tp` candidate panel for listing, filtering, and dependency-safely undoing runtime candidate-order rules.

**Architecture:** Extend `candidate_order_core.lua` with management query and exact chain-aware removal APIs. Reuse the current candidate-order translator and processor for panel rendering and a double-`0` confirmation state machine, leaving ordinary code tuning unchanged.

**Tech Stack:** Lua, librime-lua candidates/processors, direct Lua regression tests.

---

### Task 1: Add record search and dependency-aware exact removal

**Files:**
- Create: `tests/test_candidate_order_manager.lua`
- Modify: `lua/xmjd6/candidate_order_core.lua`

1. Write failing tests for file-order search across words/codes and exact
   removal of a selected root plus recursive chain records.
2. Run `lua tests/test_candidate_order_manager.lua` and confirm the APIs are
   missing.
3. Implement `search_records`, `record_at_line`, and
   `remove_record_and_dependents` using full record identity.
4. Run the test and existing candidate-order core tests.
5. Commit the core and test changes.

### Task 2: Render `=tp` management candidates

**Files:**
- Modify: `tests/test_candidate_order_manager.lua`
- Modify: `lua/xmjd6/candidate_order.lua`

1. Write failing translator tests for list, filter, empty, confirmation, and
   result states.
2. Run the manager test and observe the missing candidates.
3. Render management candidates before the normal enabled/plain-code gates.
4. Run manager and existing translator tests.
5. Commit the translator changes.

### Task 3: Implement double-0 undo

**Files:**
- Modify: `tests/test_candidate_order_manager.lua`
- Modify: `lua/xmjd6/candidate_order_processor.lua`

1. Write failing processor tests for first-press confirmation, second-press
   chain-aware removal, cancellation, stale input, and failure notices.
2. Run the manager test and observe `0` following the old promotion path.
3. Add the management state machine before ordinary tuning.
4. Run manager, processor, translator, and core regressions.
5. Commit the processor changes.

### Task 4: Document and verify

**Files:**
- Modify: `guide/功能说明.md`
- Modify: `lua/xmjd6/xmjd6_tools.lua`

1. Add `=tp` to help and document filter/double-`0` behavior.
2. Run all relevant Lua regression suites and `git diff --check`.
3. Deploy locally and manually verify `=tp`, cancellation, exact undo, and
   ordinary code tuning.
4. Restore runtime `candidate_order.txt` after the smoke test.
5. Commit documentation and record final verification evidence.
