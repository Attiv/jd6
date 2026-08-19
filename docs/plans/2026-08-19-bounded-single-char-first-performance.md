# Bounded Single-Character-First Performance Record

## Environment

- Date: 2026-08-19
- Machine: Intel Core i9-9880H 2.30 GHz, x86_64
- OS: macOS 26.6.2
- Runtime: Lua 5.4.8
- Command: `lua scripts/benchmark_single_char_first.lua 100000`
- Repetitions: 100,000 per measured path

This is a pure Lua microbenchmark with reusable candidate objects. It measures
filter CPU and lazy-stream pull counts, not end-to-end Rime UI latency.

## Results

### Worst-Case Time to First Output

The fixture contains 1,000 multi-character candidates with non-empty comments,
so neither the old nor new filter can emit an early single character.

| Path | Upstream pulls | Total time | Time per operation |
| --- | ---: | ---: | ---: |
| Direct pass-through | 1 | 0.1764 s | 1,764.2 ns |
| Legacy scan-100 filter | 100 | 4.2319 s | 42,319.4 ns |
| New bounded scan-20 filter | 20 | 0.6242 s | 6,241.8 ns |

The bounded filter reduces worst-case upstream prefetch from 100 to 20
candidates, an 80% structural reduction. Its measured first-output CPU is
85.3% lower than the legacy implementation.

Compared with no filter, the bounded filter adds approximately 4.48
microseconds in this intentionally worst-case fixture. The percentage increase
looks large because direct pass-through is only 1.76 microseconds; the absolute
Lua cost remains below 0.01 milliseconds on this machine.

### Complete 20-Candidate Stream

| Path | Total time | Time per operation |
| --- | ---: | ---: |
| Direct pass-through | 0.2612 s | 2,612.3 ns |
| Legacy scan-100 filter | 1.1314 s | 11,314.4 ns |
| New bounded scan-20 filter | 0.7499 s | 7,498.7 ns |

Processing and yielding all 20 candidates adds approximately 4.89
microseconds over pass-through and uses at most 20 candidate references.

## Interpretation

The primary performance guarantee is structural rather than dependent on one
machine's timer:

- Classification work is capped by `scan_limit`, which defaults to 20.
- Buffer memory is capped at 20 candidate references.
- Candidate 21 and later are never inspected ahead of demand.
- If a single character occurs early, it is yielded immediately instead of
  waiting for the complete window.
- The filter is first in the schema chain, so bounded prefetch does not force
  later reverse-lookup, pinyin-hint, lazy OpenCC, or presentation filters to run
  ahead for all 20 candidates.

Actual Rime latency varies with translators, dictionaries, device performance,
and the requested menu page. The benchmark is reproducible and intentionally
contains no pass/fail timing threshold because shared-machine timing noise
would make such a regression test unreliable.
