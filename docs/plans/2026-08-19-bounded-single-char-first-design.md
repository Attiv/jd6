# Bounded Single-Character-First Filter Design

## Goal

Restore single-character-first candidate ordering without the severe latency of
the previous global-looking Lua filter. The default behavior should reorder
only the first 20 candidates, remain configurable, preserve every candidate,
and add effectively constant work regardless of the total candidate-stream
size.

## Existing Problem

`lua/xmjd6/xmjd6_single_char.lua` currently permits a 100-candidate scan and a
50-candidate output cap. On large completion streams such as `bq` and `te`, it
can pull many candidates through reverse lookup and hint filters before useful
output appears. It also drops the rest of the stream after reaching its output
limit. The filter is disabled in `xmjd6.schema.yaml` because the resulting
interactive latency is unacceptable.

A true global partition cannot be both lazy and low-latency: finding every
single character requires exhausting the entire upstream translation. The new
contract therefore applies only to a bounded prefix.

## Candidate-Flow Design

The filter reads at most `scan_limit` candidates from the upstream iterator.
The default is 20.

Within that prefix it performs a stable partition:

1. Single-character candidates are yielded in their original relative order.
2. Non-single candidates are temporarily buffered, then yielded in their
   original relative order after the prefix has been examined.
3. Every candidate after the bounded prefix is passed through immediately and
   unchanged.

If a single character is encountered while scanning, it can be yielded
immediately. The filter does not need to wait for all 20 candidates before
producing that single. If the prefix contains no single character, the worst
case is a fixed 20-candidate prefetch before the first word is emitted.

No output limit remains. The filter never intentionally drops a candidate.

## Configuration

Add this schema section:

```yaml
xmjd6_single_char:
  enabled: true
  scan_limit: 20
```

Configuration is read once in the Lua component `init` hook and cached in the
environment. When disabled, or when `scan_limit` is less than 2, the component
uses a direct pass-through path.

The filter is placed at the beginning of the schema filter list so its bounded
prefetch does not force reverse lookup, pinyin hint, lazy OpenCC, or embedded
candidate work for all scanned candidates. Downstream filters continue to see
the reordered stream normally.

## Single-Codepoint Detection

Rime candidate text is valid UTF-8. The hot path determines whether text is one
Unicode code point from the first byte's UTF-8 sequence width and the string's
byte length. This is constant-time and avoids a full `utf8.len()` traversal for
each inspected candidate. Empty strings and multi-codepoint emoji sequences are
not treated as single characters; four-byte CJK characters remain supported.

## Compatibility

- Candidate objects are yielded unchanged; comments, quality, types, and
  genuine-candidate links are preserved.
- Stable ordering is preserved within both the single-character and other
  groups.
- Candidate 21 and later retain their original order.
- Existing candidate-order, hint, simplifier, and uniquifier components remain
  enabled and run downstream.
- The user's untracked `default.yaml` and modified `installation.yaml` and
  `user.yaml` are unrelated local state and must not be staged or committed.

## Performance Verification

Add a deterministic Lua test harness and benchmark:

- Verify the first 20 candidates are stably partitioned.
- Verify the suffix is passed through and no candidates are lost.
- Verify a very large lazy input is never prefetched beyond 20 before the
  buffered prefix is released.
- Verify configuration values and the disabled fast path.
- Benchmark pass-through, the former algorithm, and the bounded algorithm over
  repeatable candidate fixtures.

Report both elapsed CPU time and structural limits. The key guarantee is more
important than a noisy wall-clock percentage: additional classification and
buffering are capped at 20 candidates, so the new ordering overhead does not
grow with a 100-, 10,000-, or million-candidate upstream stream.
