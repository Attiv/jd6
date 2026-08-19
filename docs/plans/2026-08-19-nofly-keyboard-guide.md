# No-Fly Keyboard Guide Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Chinese no-fly scheme guide and an edited keyboard diagram that show the canonical J/Q/X assignments, explain every conversion decision, and prioritize Windows testing instructions.

**Architecture:** A focused regression test defines the content and image contract. The supplied keyboard image is edited with the built-in image-generation tool while preserving its layout, then a Markdown guide ties the visual mapping to the already-generated no-fly dictionaries, conversion report, branch-root workflow, and existing test evidence.

**Tech Stack:** Markdown, PNG, built-in image generation/editing, Python 3 `unittest`, Git.

---

### Task 1: Define the guide and image contract

**Files:**
- Create: `tests/test_nofly_guide.py`
- Create later: `guide/无飞键版说明.md`
- Create later: `guide/xmjd6-nofly-keyboard.png`

**Step 1: Write the failing test**

Add a dependency-free Python test that asserts:

```python
assert GUIDE.exists()
assert IMAGE.exists()
assert "ch → J" in guide_text
assert "zh → Q" in guide_text
assert "uang → X" in guide_text
```

Parse the PNG IHDR header with `struct` and require a wide, documentation-sized
image. Assert that the guide contains the image link, Q/W/F/J/X/M mappings,
representative converted and native codes, conversion totals, the no-fly branch
name, and redeployment instructions.

**Step 2: Run the test to verify RED**

Run:

```bash
python3 tests/test_nofly_guide.py
```

Expected: FAIL because both guide artifacts are missing.

**Step 3: Commit the contract test**

```bash
git add -f tests/test_nofly_guide.py
git commit -m "test(nofly): define keyboard guide contract"
```

### Task 2: Generate and inspect the no-fly keyboard diagram

**Files:**
- Create: `guide/xmjd6-nofly-keyboard.png`

**Step 1: Edit the approved source image**

Use the built-in image-generation tool in precise edit mode with the supplied
image as a local reference. Preserve the original 2048 x 640 layout, colors,
fonts, symbols, and logo. Remove only:

- the pink `zh` label from F;
- the pink `ch` label from W;
- the blue `uang` final from M.

Keep Q `zh`, J `ch`, and X `iang uang` unchanged.

**Step 2: Save the generated image**

Copy the accepted generated asset to:

```text
guide/xmjd6-nofly-keyboard.png
```

**Step 3: Visually inspect the result**

Open the final file with the image viewer. Reject and regenerate if any
unchanged key label, icon, border, row alignment, or logo differs materially
from the reference.

**Step 4: Run the focused test**

Run `python3 tests/test_nofly_guide.py`. Expected: the image assertions pass
while the missing-guide assertions still fail.

### Task 3: Write the complete no-fly guide

**Files:**
- Create: `guide/无飞键版说明.md`

**Step 1: Add the mapping overview and image**

Explain the three canonical phonetic mappings and embed:

```markdown
![键道6无飞键版键盘图](xmjd6-nofly-keyboard.png)
```

Add a complete QWERTY mapping table. Mark U/I/O/A/V as unchanged
scheme-specific shape/function keys rather than inventing textual meanings for
their glyphs.

**Step 2: Explain the easily confused keys**

Give Q/W/F/J/X/M a dedicated table that distinguishes native initial, mapped
initial, and final roles. State explicitly that conversion operates on
phonetic slots and does not globally replace the letters W/J/F/Q/X/M.

**Step 3: Document examples and all implementation changes**

Include normalized examples (`超 jz`, `春 jwv`, `找 qz`, `中 qy`, `装 qx`,
`光 gx`) and unchanged native examples (`均 jw`, `无 wj`, `求 qq`, `服 fj`).

Document structural dictionary layouts, pinyin/comment/context resolution,
explicit ambiguity overrides, stable duplicate collapse, copied non-phonetic
dictionaries, preserved metadata/order, branch-root promotion, Windows default
selection, and the conversion totals from `conversion-report.txt`.

**Step 4: Add Windows-first testing instructions**

Explain branch checkout, Weasel redeployment, scheme selection, and manual
sample input. Add a shorter macOS Squirrel section and automated maintainer
commands.

**Step 5: Run the focused test and commit artifacts**

```bash
python3 tests/test_nofly_guide.py
git add -f guide/无飞键版说明.md guide/xmjd6-nofly-keyboard.png
git commit -m "docs(nofly): add keyboard guide and diagram"
```

Expected: PASS.

### Task 4: Run full verification and publish the branch

**Files:**
- No additional source changes expected.

**Step 1: Run no-fly tests**

```bash
python3 tests/test_nofly_guide.py
python3 tests/test_nofly_bundle.py
python3 tests/test_nofly_root_layout.py
```

Expected: all tests pass.

**Step 2: Check staged and local state isolation**

```bash
git diff --check
git status --short
git diff -- installation.yaml user.yaml
```

Expected: only the user's pre-existing local modifications to
`installation.yaml` and `user.yaml` remain uncommitted.

**Step 3: Push without opening a pull request**

```bash
git push origin feature/xmjd6-nofly
```

Expected: the remote no-fly branch advances; `main` is unchanged and no pull
request is created.
