#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Reorder same-code entries so shorter words appear before longer words.

This only reorders entries inside each individual *.dict.yaml file. It does not
move entries across files and does not touch Lua.
"""

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

DEFAULT_REPORT = "same_code_length_order_report.txt"
MAIN_DICT_EXCLUDES = {
    "english.dict.yaml",
    "pinyin_simp.dict.yaml",
    "liangfen.dict.yaml",
    "xmjd6.en.dict.yaml",
    "xmjd6.gbk.dict.yaml",
}


@dataclass
class EntryLine:
    index: int
    line_no: int
    line: str
    word: str
    code: str


def parse_entry(line: str) -> tuple[str, str] | None:
    body = line.rstrip("\r\n")
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
    if not word or not code:
        return None
    return word, code


def active_import_files() -> list[Path]:
    path = Path("xmjd6.extended.dict.yaml")
    if not path.exists():
        return sorted(p for p in Path(".").glob("*.dict.yaml") if p.name not in MAIN_DICT_EXCLUDES)

    files: list[Path] = []
    in_import = False
    for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if line.strip() == "import_tables:":
            in_import = True
            continue
        if not in_import:
            continue
        match = re.match(r"^\s*-\s*([A-Za-z0-9_.]+)\b", line)
        if match:
            dict_path = Path(match.group(1) + ".dict.yaml")
            if dict_path.exists() and dict_path.name not in MAIN_DICT_EXCLUDES:
                files.append(dict_path)
    return files


def has_length_inversion(entries: list[EntryLine]) -> bool:
    min_after = 10**9
    for entry in reversed(entries):
        length = len(entry.word)
        if length > min_after:
            return True
        min_after = min(min_after, length)
    return False


def sorted_group(entries: list[EntryLine]) -> list[EntryLine]:
    return sorted(entries, key=lambda entry: (len(entry.word), entry.index))


def scan_file(path: Path) -> tuple[list[str], dict[str, list[EntryLine]], list[tuple[str, list[EntryLine]]]]:
    lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines(keepends=True)
    groups: dict[str, list[EntryLine]] = defaultdict(list)
    for index, line in enumerate(lines):
        parsed = parse_entry(line)
        if parsed is None:
            continue
        word, code = parsed
        groups[code].append(EntryLine(index=index, line_no=index + 1, line=line, word=word, code=code))

    bad_groups = [(code, entries) for code, entries in groups.items() if len(entries) > 1 and has_length_inversion(entries)]
    return lines, groups, bad_groups


def reorder_file(path: Path) -> tuple[int, int, list[str]]:
    lines, _groups, bad_groups = scan_file(path)
    changed_groups = 0
    changed_lines = 0
    details: list[str] = []

    for code, entries in bad_groups:
        ordered = sorted_group(entries)
        old_lines = [entry.line for entry in entries]
        new_lines = [entry.line for entry in ordered]
        if old_lines == new_lines:
            continue
        for target_entry, new_line in zip(entries, new_lines):
            if lines[target_entry.index] != new_line:
                changed_lines += 1
            lines[target_entry.index] = new_line
        changed_groups += 1
        before = " | ".join(f"{entry.word}({len(entry.word)})@{entry.line_no}" for entry in entries[:12])
        after = " | ".join(f"{entry.word}({len(entry.word)})" for entry in ordered[:12])
        details.append(f"{path}:{code}\n  before: {before}\n  after:  {after}")

    if changed_groups:
        path.write_text("".join(lines), encoding="utf-8")
    return changed_groups, changed_lines, details


def scan_global(files: Iterable[Path]) -> list[tuple[str, list[tuple[Path, int, str, int]]]]:
    by_code: dict[str, list[tuple[Path, int, str, int]]] = defaultdict(list)
    for path in files:
        for line_no, line in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
            parsed = parse_entry(line)
            if parsed is None:
                continue
            word, code = parsed
            by_code[code].append((path, line_no, word, len(word)))

    bad: list[tuple[str, list[tuple[Path, int, str, int]]]] = []
    for code, entries in by_code.items():
        min_after = 10**9
        has_bad = False
        for _path, _line_no, _word, length in reversed(entries):
            if length > min_after:
                has_bad = True
                break
            min_after = min(min_after, length)
        if has_bad:
            bad.append((code, entries))
    return bad


def write_report(report: Path, files: list[Path], changed_details: list[str], remaining_in_file: list[str], global_bad) -> None:
    lines: list[str] = []
    lines.append("# Same Code Length Order Report")
    lines.append("")
    lines.append(f"scanned_files: {len(files)}")
    lines.append(f"changed_groups: {len(changed_details)}")
    lines.append(f"remaining_in_file_groups: {len(remaining_in_file)}")
    lines.append(f"global_cross_file_bad_groups: {len(global_bad)}")
    lines.append("")
    lines.append("## Changed In-File Groups")
    lines.extend(changed_details or ["(none)"])
    lines.append("")
    lines.append("## Remaining In-File Groups")
    lines.extend(remaining_in_file or ["(none)"])
    lines.append("")
    lines.append("## Global / Cross-File Groups Still Needing Policy")
    if not global_bad:
        lines.append("(none)")
    else:
        for code, entries in global_bad[:500]:
            lines.append(f"### {code}")
            for path, line_no, word, length in entries[:80]:
                lines.append(f"{path}:{line_no}\t{word}\tlen={length}")
            if len(entries) > 80:
                lines.append(f"... {len(entries) - 80} more")
            lines.append("")
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Rewrite in-file groups. Without this, report only.")
    parser.add_argument("--report", default=DEFAULT_REPORT)
    args = parser.parse_args()

    files = active_import_files()
    changed_details: list[str] = []

    if args.apply:
        total_groups = total_lines = 0
        for path in files:
            groups, lines, details = reorder_file(path)
            total_groups += groups
            total_lines += lines
            changed_details.extend(details)
        print(f"changed in-file groups: {total_groups}")
        print(f"changed lines: {total_lines}")
    else:
        for path in files:
            _lines, _groups, bad_groups = scan_file(path)
            for code, entries in bad_groups:
                before = " | ".join(f"{entry.word}({len(entry.word)})@{entry.line_no}" for entry in entries[:12])
                after = " | ".join(f"{entry.word}({len(entry.word)})" for entry in sorted_group(entries)[:12])
                changed_details.append(f"{path}:{code}\n  before: {before}\n  after:  {after}")
        print(f"in-file groups needing reorder: {len(changed_details)}")

    remaining_in_file: list[str] = []
    for path in files:
        _lines, _groups, bad_groups = scan_file(path)
        for code, entries in bad_groups:
            preview = " | ".join(f"{entry.word}({len(entry.word)})@{entry.line_no}" for entry in entries[:12])
            remaining_in_file.append(f"{path}:{code}\n  {preview}")

    global_bad = scan_global(files)
    write_report(Path(args.report), files, changed_details, remaining_in_file, global_bad)
    print(f"remaining in-file groups: {len(remaining_in_file)}")
    print(f"global/cross-file bad groups: {len(global_bad)}")
    print(f"report: {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
