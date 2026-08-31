# Qianwen Update Control Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Back up the current Qianwen App, provide reversible update blocking, unblock updates now, and provide an App-only restoration command.

**Architecture:** Use independent shell entry points for snapshot, updater state, and restore. Reuse `scripts/rollback_qianwen.sh` for vendor-assisted App replacement while adding an explicit switch that prevents its historical Qime backup behavior.

**Tech Stack:** Bash 3.2-compatible shell, macOS `ditto`, `plutil`, `shasum`, and the existing Qianwen atomic-swap helper.

---

### Task 1: Add sandbox integration tests

**Files:**
- Create: `tests/test_qianwen_update_scripts.sh`

1. Create a disposable fake Qianwen App with an executable updater and minimal Info.plist.
2. Assert `qianwen_update_control.sh block`, `unblock`, and `status` transitions.
3. Assert `backup_qianwen_app.sh` creates a snapshot and restore pointer without copying a fake Qime sentinel.
4. Assert `restore_qianwen_app.sh --no-reload` restores App content without changing the Qime sentinel.
5. Run `bash tests/test_qianwen_update_scripts.sh` and confirm it fails because the new scripts do not exist.

### Task 2: Implement updater control

**Files:**
- Create: `scripts/qianwen_update_control.sh`

1. Implement `status`, `block`, and `unblock` with environment-overridable App and relauncher paths.
2. Reject missing and ambiguous updater states.
3. Run the integration test and confirm updater-control cases pass.

### Task 3: Implement App snapshot and restore

**Files:**
- Create: `scripts/backup_qianwen_app.sh`
- Create: `scripts/restore_qianwen_app.sh`
- Modify: `scripts/rollback_qianwen.sh`

1. Implement versioned snapshots, manifests, SHA-256 verification, and an atomic default-restore pointer.
2. Add `--skip-user-backup` and an explicit manifest-verified modified-source mode to the existing rollback installer.
3. Implement restore as checksum verification followed by the existing atomic App install with `--skip-user-backup`.
4. Run `bash tests/test_qianwen_update_scripts.sh` and confirm all cases pass.

### Task 4: Execute and verify on the installed App

**Files:**
- Runtime snapshot: `~/Library/Application Support/QianwenIME/Backups/AppSnapshots/`

1. Run `scripts/backup_qianwen_app.sh` against the installed App.
2. Validate the snapshot version, manifest, checksum, and disabled updater state.
3. Run `scripts/qianwen_update_control.sh unblock`.
4. Run `scripts/qianwen_update_control.sh status` and verify updates are enabled.
5. Run syntax checks and the complete integration test again, then review `git diff` without modifying the pre-existing `user.yaml` change.
