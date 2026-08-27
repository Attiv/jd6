# Candidate Order Management Panel Design

**Date:** 2026-08-27

## Goal

Let users inspect and undo runtime tuning rules from `candidate_order.txt`
through a portable Rime candidate panel.

## Interaction

- `=tp` lists all valid tuning records in file order.
- Text appended to `=tp` filters by promoted/displaced phrase or any involved
  code.
- Each row explains the target code, promoted phrase, displaced phrase, and
  generated fallback code.
- Pressing `0` once on a highlighted row opens confirmation.
- Pressing `0` again removes the selected rule and its dependent chain rules.
- Any other normal key cancels confirmation.
- Existing plain-code `0` tuning behavior remains unchanged.

## Architecture

`candidate_order_core.lua` owns three new side-effect-free/read-write APIs:

1. search records for the management query;
2. resolve a displayed source line back to a full record identity;
3. remove that exact record plus recursively dependent fallback-chain records.

`candidate_order.lua` renders management, confirmation, empty, and result
candidates before its existing normal-code translation path.

`candidate_order_processor.lua` handles literal `0` in `=tp` mode before its
existing candidate-promotion hotkey path. A dedicated global state table keeps
the pending record identity and short-lived result notice.

## Dependency-Aware Removal

Deleting only one physical line can leave generated fallback records hiding or
moving words. The removal API starts from the exact selected record and reuses
the existing chain-side-effect relation recursively. Unrelated records,
comments, and blank lines remain intact.

The pending identity contains every stored field, not only a line number. If a
sync or external edit changes the file between the two `0` presses, the second
press either finds the same record by full identity or reports that it no
longer exists.

## Error Handling

- Empty and invalid files produce informational candidates rather than writes.
- A stale displayed row is never allowed to delete a different current line.
- Write failures keep the management composition open and display the error.
- Management remains available even when runtime tuning display is disabled,
  so stale rules can still be removed.

## Testing

Lua tests cover record search, display formatting, double-`0` state changes,
exact removal, recursive chain cleanup, cancellation, stale identity handling,
write errors, and preservation of existing tuning/translation behavior.
