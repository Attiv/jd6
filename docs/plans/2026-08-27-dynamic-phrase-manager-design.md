# Dynamic Phrase Management Panel Design

**Date:** 2026-08-27

## Goal

Let users browse, filter, and precisely delete entries from
`dynamic_phrases.txt` inside the Rime candidate menu without redeploying the
schema or opening the file manually.

## Scope

This change implements the dynamic-phrase deletion panel only. A matching
dynamic-tuning manager is a future change and will use `=tp` as its entry
point.

## User Interaction

- Typing `=del/` lists every dynamic phrase in file order.
- Typing text or a code after `=del/` filters the list by phrase or code.
- Each management candidate displays the phrase as candidate text and its code
  in the comment.
- Pressing `0` on a highlighted management candidate enters confirmation.
- Pressing `0` again deletes that exact phrase/code pair.
- Pressing any other key cancels confirmation and lets that key continue
  through the normal Rime processor chain.
- Existing commands such as `=del/word/code;`, `=del/code;`, and
  `=del/word;` retain their current behavior.

Candidate tapping is deliberately not treated as deletion. Rime frontends
normally commit a tapped candidate, so the double-`0` interaction is the
portable Rime-only control.

## Architecture

### Core

`lua/xmjd6/dynamic_phrase_core.lua` exposes a query helper that returns entries
whose text or code contains the management query. Exact deletion continues to
use `delete_phrase(text, code, ...)`, preserving the existing cleanup of
related `candidate_order.txt` records and chain side effects.

### Translator

`lua/xmjd6/dynamic_phrase.lua` recognizes management inputs of the form
`=del/<single query>` without a semicolon or second slash. It emits typed
management candidates before falling back to the existing command preview.

Shared dynamic-phrase state holds only transient UI data:

- the pending exact phrase/code pair;
- the input that opened confirmation;
- a short result notice after deletion.

When confirmation is pending, the translator presents a confirmation candidate
and explains that another `0` confirms while any other key cancels.

### Processor

`lua/xmjd6/dynamic_phrase_processor.lua` handles `0` before its existing
space/Return/semicolon command path:

1. On the first `0`, read the selected management candidate and store its exact
   phrase/code identity.
2. Refresh the uncommitted composition so the confirmation state is visible.
3. On the second consecutive `0`, call the existing exact deletion API.
4. Refresh the same management input to show the result and remaining entries.
5. Clear pending confirmation when another key arrives or the input changes.

The processor already appears before `candidate_order_processor` in
`xmjd6.schema.yaml`, so accepting `0` in management mode does not conflict with
the existing tuning hotkey.

## Error Handling

- Failure to write `dynamic_phrases.txt` leaves the composition open and shows
  the returned error as a candidate notice.
- Invalid or stale selected candidates do not modify either runtime file.
- Deletion identity includes both phrase and code, so phrases with multiple
  codes are handled precisely.
- An empty store displays an informational candidate rather than silently
  falling through.

## Dynamic Tuning Manager Recommendation

A future `=tp` panel should list each `candidate_order.txt` rule in user-facing
language, for example:

```text
bklw: promote 避雷 (from bklwa), move 壁垒 down
```

It should support the same filter and double-`0` interaction. Removing a tuning
rule must remove dependent chain/fallback rules, not merely delete one physical
line. That dependency-aware removal belongs in `candidate_order_core.lua` and
is outside this change.

## Testing

Lua regression tests cover:

- listing and text/code filtering;
- exact candidate identity;
- first-press confirmation without file mutation;
- second-press exact deletion;
- cancellation by another key;
- preservation of existing semicolon and confirmation commands;
- cleanup of associated candidate-order records through the existing core.

The guide is updated with the new interaction and the planned `=tp` naming.
