# Qianwen Double-Pinyin Keydao Overlay Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Preserve Qianwen full pinyin while replacing Qianwen double pinyin with Keydao 6.

**Architecture:** Retarget the existing alias-generation and compiled-table mapping from `qw` to `qw_double`. Keep the rest of the deployment, backup, engine compatibility, and atomic-swap workflow unchanged.

**Tech Stack:** Bash, Python schema transformation embedded in Bash, Rime deployment artifacts, macOS Qianwen helpers.

---

### Task 1: Define the target behavior in the integration fixture

1. Add separate vendor `qw` and `qw_double` source/build fixtures.
2. Require the `qw` files to remain byte-identical after sync.
3. Require the generated Keydao schema and table artifacts under `qw_double`.
4. Run `bash tests/test_sync_qianwen_rime.sh` and confirm the old implementation fails.

### Task 2: Retarget the overlay

1. Generalize the schema generator for `qw_double`.
2. Change compiled aliases from `qw.*.bin` to `qw_double.*.bin`.
3. Generate source and built aliases at `qw_double.schema.yaml`.
4. Change `status` to validate `qw_double`.
5. Run the isolated sync tests and confirm they pass.

### Task 3: Update handoff documentation and deploy

1. Update `修改日志.md` to state that `qw` is preserved and `qw_double` is replaced.
2. Run syntax and integration tests.
3. Run `scripts/sync_qianwen_rime.sh sync` on the installed App.
4. Verify the installed source and built schemas, compiled artifacts, status output, and preserved full-pinyin hashes.
