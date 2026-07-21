#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find and optionally apply safe one-character code shortening for Rime dicts.

Default mode is dry-run: write a report only. Use --apply to rewrite safe rows.

Key safety rules:
- Only shorten one character at a time.
- Only shorten when the shorter code is empty across all scanned dictionaries.
- If several entries already share the same old code, they may move together to
  the same empty shorter code. This preserves an existing duplicate group rather
  than creating a new one.
- If different old codes want the same shorter code, they are reported as
  conflicts and are not applied automatically.
- --apply does not create .bak files unless --backup is also provided.
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
DEFAULT_PROTECT = "shrink_empty_codes_protect.txt"
MAIN_DICT_EXCLUDES = [
    "english.dict.yaml",
    "pinyin_simp.dict.yaml",
    "liangfen.dict.yaml",
    "xmjd6.en.dict.yaml",
    "xmjd6.gbk.dict.yaml",
]

# Deliberately conservative so English definitions / reverse-lookup annotations
# are not mistaken for codes.
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
        "--repeat",
        action="store_true",
        help=(
            "With --apply, keep rescanning and applying safe candidates until "
            "no more safe one-character shortenings remain."
        ),
    )
    parser.add_argument(
        "--backup",
        action="store_true",
        help="With --apply, write .bak files before modifying dictionaries.",
    )
    parser.add_argument(
        "--main",
        action="store_true",
        help=(
            "Use the recommended main-dictionary scope by excluding English, "
            "Pinyin, Liangfen, xmjd6.en, and xmjd6.gbk dictionaries."
        ),
    )
    parser.add_argument(
        "--report",
        default=DEFAULT_REPORT,
        help=f"Report output path (default: {DEFAULT_REPORT}).",
    )
    parser.add_argument(
        "--protect",
        default=DEFAULT_PROTECT,
        help=(
            "Protected word-code list to skip, one 'word<TAB>code' per line. "
            f"Default: {DEFAULT_PROTECT}. Use empty string to disable."
        ),
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


def load_protected_entries(path_text: str) -> set[tuple[str, str]]:
    if not path_text:
        return set()

    path = Path(path_text)
    if not path.exists():
        return set()

    protected: set[tuple[str, str]] = set()
    for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "\t" not in line:
            continue
        word, code, *_rest = line.split("\t")
        word = word.strip()
        code = code.strip()
        if word and code:
            protected.add((word, code))
    return protected


def find_candidates(
    entries: list[Entry],
    min_length: int,
    protected: set[tuple[str, str]] | None = None,
) -> tuple[list[Candidate], dict[str, list[Candidate]]]:
    protected = protected or set()
    occupied_codes = {entry.code for entry in entries}
    grouped: dict[str, list[Candidate]] = defaultdict(list)

    for entry in entries:
        if (entry.word, entry.code) in protected:
            continue
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
        old_codes = {candidate.entry.code for candidate in group}
        if len(old_codes) == 1:
            safe.extend(group)
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
    pass_summaries: list[tuple[int, int, int]],
) -> None:
    conflict_entry_count = sum(len(group) for group in conflicts.values())
    lines: list[str] = []
    lines.append("# Shrink Empty Codes Report")
    lines.append("")
    lines.append(f"mode: {'apply' if apply_mode else 'dry-run'}")
    lines.append(f"scanned_files: {len(paths)}")
    lines.append(f"parsed_entries: {len(entries)}")
    lines.append(f"safe_candidates: {len(safe)}")
    lines.append(f"conflict_groups: {len(conflicts)}")
    lines.append(f"conflict_entries: {conflict_entry_count}")
    lines.append(f"applied_changes: {applied_count}")
    lines.append("")

    if pass_summaries:
        lines.append("## Apply Passes")
        lines.append("pass\tsafe_candidates_before_pass\tconflict_groups\tconflict_entries")
        for index, (safe_count, conflict_group_count, conflict_count) in enumerate(pass_summaries, 1):
            lines.append(f"{index}\t{safe_count}\t{conflict_group_count}\t{conflict_count}")
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


def apply_candidates(file_lines: dict[Path, list[str]], safe: list[Candidate], backup: bool) -> int:
    by_file: dict[Path, list[Candidate]] = defaultdict(list)
    for candidate in safe:
        by_file[candidate.entry.path].append(candidate)

    applied_count = 0
    for path, candidates in by_file.items():
        lines = list(file_lines[path])
        if backup:
            backup_path = path.with_name(path.name + ".bak")
            shutil.copyfile(path, backup_path)

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


def main() -> int:
    args = parse_args()
    patterns = args.patterns or [DEFAULT_PATTERN]
    if args.main:
        args.exclude = list(args.exclude) + MAIN_DICT_EXCLUDES
    if args.min_length < 2:
        raise SystemExit("--min-length must be >= 2")
    if args.repeat and not args.apply:
        raise SystemExit("--repeat only makes sense together with --apply")

    paths = iter_dictionary_paths(patterns, args.exclude)
    protected = load_protected_entries(args.protect)
    applied_count = 0
    pass_summaries: list[tuple[int, int, int]] = []

    if args.apply:
        pass_no = 1
        while True:
            entries, file_lines = scan_entries(paths)
            safe, conflicts = find_candidates(entries, args.min_length, protected)
            conflict_entry_count = sum(len(group) for group in conflicts.values())
            pass_summaries.append((len(safe), len(conflicts), conflict_entry_count))

            if not safe:
                break

            applied_this_pass = apply_candidates(file_lines, safe, backup=args.backup)
            applied_count += applied_this_pass
            print(f"pass {pass_no}: applied {applied_this_pass} safe shortenings")

            if not args.repeat:
                break
            pass_no += 1

        # Re-scan after writes so the final report reflects current state.
        entries, _file_lines = scan_entries(paths)
        safe, conflicts = find_candidates(entries, args.min_length, protected)
    else:
        entries, _file_lines = scan_entries(paths)
        safe, conflicts = find_candidates(entries, args.min_length, protected)

    report_path = Path(args.report)
    write_report(
        report_path=report_path,
        paths=paths,
        entries=entries,
        safe=safe,
        conflicts=conflicts,
        applied_count=applied_count,
        apply_mode=args.apply,
        pass_summaries=pass_summaries,
    )

    conflict_entry_count = sum(len(group) for group in conflicts.values())
    print(f"scanned files: {len(paths)}")
    print(f"parsed entries: {len(entries)}")
    print(f"safe candidates: {len(safe)}")
    print(f"conflict groups: {len(conflicts)} ({conflict_entry_count} entries)")
    print(f"applied changes: {applied_count}")
    if pass_summaries:
        print(f"apply passes: {len(pass_summaries)}")
    print(f"report: {report_path}")
    if not args.apply:
        print("dry-run only; use --apply to rewrite safe candidates")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
