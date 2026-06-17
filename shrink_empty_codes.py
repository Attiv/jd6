#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find and optionally apply safe one-character code shortening for Rime dicts.

Default mode is dry-run: write a report only. Use --apply to rewrite safe rows.
"""

from __future__ import annotations

import argparse
import fnmatch
import shutil
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

DEFAULT_REPORT = "shrink_empty_codes_report.txt"
DEFAULT_PATTERN = "*.dict.yaml"
# Keep this deliberately conservative so English definitions / reverse-lookup
# annotations are not mistaken for codes.
CODE_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789;`'./_-")


@dataclass(frozen=True)
class Entry:
    path: Path
    line_no: int
    word: str
    code: str


@dataclass(frozen=True)
class Candidate:
    entry: Entry
    new_code: str


@dataclass(frozen=True)
class PassSummary:
    pass_no: int
    scanned_files: int
    parsed_entries: int
    safe_candidates: int
    conflict_groups: int
    conflict_entries: int
    applied_changes: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "List or apply one-character code shortening when the shorter "
            "code is empty across scanned Rime dictionaries."
        )
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Rewrite safe non-conflicting rows. Without this, only writes report.",
    )
    parser.add_argument(
        "--report",
        default=DEFAULT_REPORT,
        help=f"Report output path (default: {DEFAULT_REPORT}).",
    )
    parser.add_argument(
        "--glob",
        dest="patterns",
        action="append",
        default=None,
        help=(
            "Dictionary glob to scan. Can be used multiple times. "
            f"Default: {DEFAULT_PATTERN}"
        ),
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help=(
            "Filename or glob pattern to exclude. Can be used multiple times, "
            "for example --exclude 'english.*'."
        ),
    )
    parser.add_argument(
        "--min-length",
        type=int,
        default=5,
        help="Only codes with at least this length are considered (default: 5).",
    )
    parser.add_argument(
        "--repeat",
        action="store_true",
        help=(
            "With --apply, keep rescanning and shortening until no safe "
            "one-character shrink remains."
        ),
    )
    parser.add_argument(
        "--max-passes",
        type=int,
        default=20,
        help="Maximum passes when --repeat is used with --apply (default: 20).",
    )
    return parser.parse_args()


def code_like(value: str) -> bool:
    """Return True when value looks like a plain Rime code, not a definition."""
    return bool(value) and all(ch in CODE_CHARS for ch in value)


def split_line_ending(line: str) -> tuple[str, str]:
    if line.endswith("\r\n"):
        return line[:-2], "\r\n"
    if line.endswith("\n"):
        return line[:-1], "\n"
    if line.endswith("\r"):
        return line[:-1], "\r"
    return line, ""


def parse_entry(line: str) -> tuple[str, str] | None:
    """Parse a text<TAB>code row.

    Comments, blank rows, YAML delimiters, and rows whose second field does not
    look like a code are ignored. Extra tab-separated columns are preserved by
    apply mode but are not part of the decision.
    """
    body, _ending = split_line_ending(line)
    stripped = body.strip()
    if not stripped or stripped.startswith("#") or stripped in {"---", "..."}:
        return None
    if "\t" not in body:
        return None

    parts = body.split("\t")
    if len(parts) < 2:
        return None

    word = parts[0].strip()
    code = parts[1].strip()
    if not word or not code_like(code):
        return None
    return word, code


def iter_dictionary_paths(patterns: Iterable[str], excludes: Iterable[str]) -> list[Path]:
    paths: set[Path] = set()
    for pattern in patterns:
        paths.update(Path(".").glob(pattern))

    exclude_patterns = list(excludes)
    result: list[Path] = []
    for path in sorted(paths):
        if not path.is_file():
            continue
        name = path.name
        rel = path.as_posix()
        if any(fnmatch.fnmatch(name, pat) or fnmatch.fnmatch(rel, pat) for pat in exclude_patterns):
            continue
        result.append(path)
    return result


def scan_entries(paths: Iterable[Path]) -> tuple[list[Entry], dict[Path, list[str]]]:
    entries: list[Entry] = []
    file_lines: dict[Path, list[str]] = {}

    for path in paths:
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        lines = text.splitlines(keepends=True)
        file_lines[path] = lines

        in_body = False
        has_delimiter = any(line.strip() == "..." for line in lines)
        for line_no, line in enumerate(lines, 1):
            if has_delimiter and not in_body:
                if line.strip() == "...":
                    in_body = True
                continue

            parsed = parse_entry(line)
            if parsed is None:
                continue
            word, code = parsed
            entries.append(Entry(path=path, line_no=line_no, word=word, code=code))

    return entries, file_lines


def find_candidates(entries: list[Entry], min_length: int) -> tuple[list[Candidate], dict[str, list[Candidate]]]:
    occupied_codes = {entry.code for entry in entries}
    grouped: dict[str, list[Candidate]] = defaultdict(list)

    for entry in entries:
        if len(entry.code) < min_length:
            continue
        new_code = entry.code[:-1]
        if new_code in occupied_codes:
            continue
        grouped[new_code].append(Candidate(entry=entry, new_code=new_code))

    safe: list[Candidate] = []
    conflicts: dict[str, list[Candidate]] = {}
    for new_code in sorted(grouped):
        group = grouped[new_code]
        if len(group) == 1:
            safe.append(group[0])
        else:
            conflicts[new_code] = group

    safe.sort(key=lambda cand: (cand.entry.path.as_posix(), cand.entry.line_no, cand.entry.code))
    return safe, conflicts


def format_candidate(candidate: Candidate) -> str:
    entry = candidate.entry
    return f"{entry.path.as_posix()}:{entry.line_no}\t{entry.word}\t{entry.code}\t{candidate.new_code}"


def write_report(
    report_path: Path,
    paths: list[Path],
    entries: list[Entry],
    safe: list[Candidate],
    conflicts: dict[str, list[Candidate]],
    applied_count: int,
    apply_mode: bool,
    repeat_mode: bool = False,
    pass_summaries: list[PassSummary] | None = None,
) -> None:
    conflict_entry_count = sum(len(group) for group in conflicts.values())
    lines: list[str] = []
    lines.append("# Shrink Empty Codes Report")
    lines.append("")
    if apply_mode and repeat_mode:
        mode = "apply-repeat"
    else:
        mode = "apply" if apply_mode else "dry-run"
    lines.append(f"mode: {mode}")
    lines.append(f"scanned_files: {len(paths)}")
    lines.append(f"parsed_entries: {len(entries)}")
    lines.append(f"safe_candidates: {len(safe)}")
    lines.append(f"conflict_groups: {len(conflicts)}")
    lines.append(f"conflict_entries: {conflict_entry_count}")
    lines.append(f"applied_changes: {applied_count}")
    lines.append("")

    if pass_summaries:
        lines.append("## Pass Summaries")
        lines.append(
            "pass\tscanned_files\tparsed_entries\tsafe_candidates\t"
            "conflict_groups\tconflict_entries\tapplied_changes"
        )
        for summary in pass_summaries:
            lines.append(
                f"{summary.pass_no}\t{summary.scanned_files}\t"
                f"{summary.parsed_entries}\t{summary.safe_candidates}\t"
                f"{summary.conflict_groups}\t{summary.conflict_entries}\t"
                f"{summary.applied_changes}"
            )
        lines.append("")

    lines.append("## Scanned Files")
    for path in paths:
        lines.append(f"- {path.as_posix()}")
    lines.append("")

    lines.append("## SAFE CANDIDATES")
    lines.append("file:line\tword\told_code\tnew_code")
    if safe:
        lines.extend(format_candidate(candidate) for candidate in safe)
    else:
        lines.append("(none)")
    lines.append("")

    lines.append("## CONFLICTS")
    if conflicts:
        for new_code in sorted(conflicts):
            lines.append(f"### target: {new_code}")
            lines.append("file:line\tword\told_code\tnew_code")
            for candidate in sorted(
                conflicts[new_code],
                key=lambda cand: (cand.entry.path.as_posix(), cand.entry.line_no, cand.entry.code),
            ):
                lines.append(format_candidate(candidate))
            lines.append("")
    else:
        lines.append("(none)")

    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def replace_code_in_line(line: str, new_code: str) -> str:
    body, ending = split_line_ending(line)
    parts = body.split("\t")
    if len(parts) < 2:
        return line
    parts[1] = new_code
    return "\t".join(parts) + ending


def apply_candidates(
    file_lines: dict[Path, list[str]],
    safe: list[Candidate],
    backed_up_paths: set[Path] | None = None,
) -> int:
    by_file: dict[Path, list[Candidate]] = defaultdict(list)
    for candidate in safe:
        by_file[candidate.entry.path].append(candidate)

    applied_count = 0
    for path, candidates in by_file.items():
        lines = list(file_lines[path])
        backup_path = path.with_name(path.name + ".bak")
        if backed_up_paths is None or path not in backed_up_paths:
            shutil.copyfile(path, backup_path)
            if backed_up_paths is not None:
                backed_up_paths.add(path)

        for candidate in candidates:
            idx = candidate.entry.line_no - 1
            old_line = lines[idx]
            parsed = parse_entry(old_line)
            if parsed is None:
                continue
            _word, current_code = parsed
            if current_code != candidate.entry.code:
                continue
            lines[idx] = replace_code_in_line(old_line, candidate.new_code)
            applied_count += 1

        path.write_text("".join(lines), encoding="utf-8")

    return applied_count


def scan_once(
    patterns: Iterable[str],
    excludes: Iterable[str],
    min_length: int,
) -> tuple[list[Path], list[Entry], dict[Path, list[str]], list[Candidate], dict[str, list[Candidate]]]:
    paths = iter_dictionary_paths(patterns, excludes)
    entries, file_lines = scan_entries(paths)
    safe, conflicts = find_candidates(entries, min_length)
    return paths, entries, file_lines, safe, conflicts


def main() -> int:
    args = parse_args()
    patterns = args.patterns or [DEFAULT_PATTERN]
    if args.min_length < 2:
        raise SystemExit("--min-length must be >= 2")
    if args.max_passes < 1:
        raise SystemExit("--max-passes must be >= 1")

    pass_summaries: list[PassSummary] = []
    applied_count = 0

    if args.apply and args.repeat:
        backed_up_paths: set[Path] = set()
        final_state: tuple[
            list[Path],
            list[Entry],
            dict[Path, list[str]],
            list[Candidate],
            dict[str, list[Candidate]],
        ] | None = None

        for pass_no in range(1, args.max_passes + 1):
            paths, entries, file_lines, safe, conflicts = scan_once(
                patterns, args.exclude, args.min_length
            )
            pass_applied = apply_candidates(file_lines, safe, backed_up_paths=backed_up_paths)
            applied_count += pass_applied
            pass_summaries.append(
                PassSummary(
                    pass_no=pass_no,
                    scanned_files=len(paths),
                    parsed_entries=len(entries),
                    safe_candidates=len(safe),
                    conflict_groups=len(conflicts),
                    conflict_entries=sum(len(group) for group in conflicts.values()),
                    applied_changes=pass_applied,
                )
            )
            final_state = (paths, entries, file_lines, safe, conflicts)
            if pass_applied == 0:
                break
        else:
            print(f"warning: reached --max-passes={args.max_passes}; more shrink passes may remain")

        assert final_state is not None
        paths, entries, file_lines, safe, conflicts = final_state
    else:
        if args.repeat and not args.apply:
            print("note: --repeat only changes apply mode; running a single dry-run")
        paths, entries, file_lines, safe, conflicts = scan_once(
            patterns, args.exclude, args.min_length
        )
        if args.apply:
            applied_count = apply_candidates(file_lines, safe)

    report_path = Path(args.report)
    write_report(
        report_path=report_path,
        paths=paths,
        entries=entries,
        safe=safe,
        conflicts=conflicts,
        applied_count=applied_count,
        apply_mode=args.apply,
        repeat_mode=args.repeat,
        pass_summaries=pass_summaries,
    )

    conflict_entry_count = sum(len(group) for group in conflicts.values())
    if pass_summaries:
        print(f"passes: {len(pass_summaries)}")
        for summary in pass_summaries:
            print(
                f"pass {summary.pass_no}: safe candidates {summary.safe_candidates}, "
                f"applied changes {summary.applied_changes}"
            )
    print(f"scanned files: {len(paths)}")
    print(f"parsed entries: {len(entries)}")
    print(f"safe candidates: {len(safe)}")
    print(f"conflict groups: {len(conflicts)} ({conflict_entry_count} entries)")
    print(f"applied changes: {applied_count}")
    print(f"report: {report_path}")
    if not args.apply:
        print("dry-run only; use --apply to rewrite safe candidates")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
