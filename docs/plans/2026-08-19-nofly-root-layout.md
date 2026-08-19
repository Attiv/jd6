# No-Fly Branch Root Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Promote the generated no-fly bundle into the root of `feature/xmjd6-nofly` so checking out the branch directly activates the no-fly source configuration after redeployment.

**Architecture:** A root-layout regression test defines the branch contract before files move. The tracked `xmjd6-nofly/` snapshot is then promoted over matching root runtime resources, the duplicate nested directory is removed, and branch-specific guidance replaces the standalone-package README. Local machine state files remain unstaged and unchanged.

**Tech Stack:** Git worktrees/branches, Python `unittest`, Rime YAML dictionaries, `rime_deployer`, Markdown.

---

### Task 1: Define the branch-root contract

**Files:**
- Create: `tests/test_nofly_root_layout.py`

**Step 1: Write the failing test**

Create a unittest that checks:

```python
assert "name: 键道6·无飞键版" in (ROOT / "xmjd6.schema.yaml").read_text("utf-8-sig")
assert not (ROOT / "xmjd6-nofly").exists()
```

Add representative dictionary assertions for normalized and native codes.

**Step 2: Run the test to verify it fails**

Run:

```bash
python3 tests/test_nofly_root_layout.py
```

Expected: FAIL because the root still contains the original schema and the nested bundle still exists.

**Step 3: Commit the contract test**

```bash
git add -f tests/test_nofly_root_layout.py
git commit -m "test(nofly): define branch-root scheme contract"
```

### Task 2: Promote the generated runtime files

**Files:**
- Replace: root runtime files matching `xmjd6-nofly/**`
- Delete: `xmjd6-nofly/`
- Preserve: `installation.yaml`
- Preserve: `user.yaml`

**Step 1: Copy bundle entries to the root**

Use a Python filesystem operation that copies every direct child of
`xmjd6-nofly/` over the corresponding root path. Do not read, write, stage, or
delete `installation.yaml` or `user.yaml`.

**Step 2: Remove the duplicate nested directory**

After a successful copy, remove only the tracked `xmjd6-nofly/` directory.

**Step 3: Run the root-layout test**

```bash
python3 tests/test_nofly_root_layout.py
```

Expected: PASS.

**Step 4: Verify local state isolation**

```bash
git diff -- installation.yaml user.yaml
git status --short
```

Expected: the two pre-existing local modifications remain unstaged; runtime
changes and deletion of the nested snapshot are the only new branch changes.

**Step 5: Commit**

```bash
git add -A
git restore --staged installation.yaml user.yaml
git commit -m "feat(nofly): promote no-fly scheme to branch root"
```

### Task 3: Update branch usage guidance

**Files:**
- Modify: `README.md`

**Step 1: Write the failing documentation assertion**

Extend `tests/test_nofly_root_layout.py` to require both branch-switch commands
and a redeployment reminder.

**Step 2: Verify RED**

Run the focused test. Expected: FAIL because the promoted standalone README
does not yet describe branch switching.

**Step 3: Update the README**

Document:

```bash
git checkout main
git checkout feature/xmjd6-nofly
```

Explain that Rime must be redeployed after every switch and that local state
files should not be committed.

**Step 4: Verify GREEN and commit**

```bash
python3 tests/test_nofly_root_layout.py
git add README.md tests/test_nofly_root_layout.py
git commit -m "docs(nofly): explain branch switching and verification"
```

### Task 4: Compile and verify the active root

**Files:**
- No tracked file changes expected.

**Step 1: Run no-fly tests**

```bash
python3 tests/test_nofly_bundle.py
python3 tests/test_nofly_root_layout.py
```

Expected: PASS.

**Step 2: Compile in an isolated directory**

Copy the branch root to a temporary user-data directory and run the local
`rime_deployer --compile` command. Require non-empty schema, table, prism, and
reverse artifacts in the temporary output only.

**Step 3: Verify source isolation**

```bash
git status --short
git diff -- installation.yaml user.yaml
```

Expected: only the pre-existing local state modifications remain.

**Step 4: Push the updated branch**

```bash
git push origin feature/xmjd6-nofly
```

Expected: the remote branch advances without creating a pull request.
