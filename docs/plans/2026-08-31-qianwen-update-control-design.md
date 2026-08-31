# Qianwen Update Control and App Restore Design

## Scope

Preserve the currently installed Qianwen input-method application before allowing it to update. The snapshot and restore flow covers only `/Library/Input Methods/QianwenIME.app`; it must not copy, replace, or remove `~/Library/Application Support/QianwenIME/Qime`.

## Approach

Add three small shell entry points under `scripts/`:

- `backup_qianwen_app.sh` creates an immutable, versioned App snapshot plus a SHA-256 manifest and records it as the default restore source.
- `qianwen_update_control.sh` reports, blocks, or unblocks updates by toggling `Contents/Helpers/QianwenIMEUpdater` and `.disabled`.
- `restore_qianwen_app.sh` restores the recorded App snapshot through the existing `rollback_qianwen.sh` atomic swap implementation, with user-data backup disabled.

The existing vendor-signed `QianwenIMEAtomicSwap` path remains the single implementation for replacing App contents. Environment overrides and `--no-reload` permit isolated tests without touching the installed input method.

## Safety and Error Handling

- Refuse ambiguous updater states where both enabled and disabled files exist.
- Refuse incomplete or invalid App bundles.
- Never overwrite an existing snapshot.
- Verify snapshot metadata and hashes before recording it as restorable.
- Permit the existing rollback helper to accept a modified App only through an explicit flag after the restore wrapper has verified the snapshot manifest; ordinary stock-App restores still require a valid vendor signature.
- Restore only the App. Qime user data is an explicit invariant and remains untouched.
- Preserve the current updater state inside the snapshot so restoration returns to the exact pre-update App state.

## Verification

Shell integration tests construct disposable fake App bundles and verify status transitions, snapshot creation, checksum validation, and App-only restoration. A live verification then records the installed `1.1.5 (1.1.5.23)` App, unblocks its updater, and checks that `QianwenIMEUpdater` is executable while `.disabled` is absent.
