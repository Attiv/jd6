#!/usr/bin/env python3
"""Solidify candidate_order.txt into xmjd6.candidate_order.dict.yaml.

Runtime format per non-comment line:
    promoted_text<TAB>promoted_old_code<TAB>displaced_text<TAB>target_code[<TAB>displaced_new_code]

Example:
    边骂    bmmsa   编码    bmms

Default is dry-run. Use --apply to write output and remove old entries.
"""
from __future__ import annotations

import argparse
import dataclasses
import shutil
from datetime import datetime
import re
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
ORDER_FILE = ROOT / "candidate_order.txt"
OUTPUT_FILE = ROOT / "xmjd6.candidate_order.dict.yaml"
CODE_RE = re.compile(r"^[a-z]+$")
ORDER_HEADER = (
    "# xmjd6 candidate order\n"
    "# promoted<TAB>old_code<TAB>displaced<TAB>target_code\n"
)

EXCLUDED_REMOVE_FILES = {
    "xmjd6.extended.dict.yaml",
    "xmjd6.dict.yaml",
    "xmjd6.cx.dict.yaml",
    "xmjd6.candidate_order.dict.yaml",
}


@dataclasses.dataclass
class Order:
    promoted: str
    old_code: str
    displaced: str
    target_code: str
    line_no: int
    same_code: bool = False
    new_code: str | None = None
    full_code: str | None = None


def strip_comment(line: str) -> str:
    # candidate_order 里的 # 用作行内注释；词条里确实需要 # 时请用脚本前临时转义/手改。
    return re.sub(r"\s+#.*$", "", line.rstrip("\n\r")).strip()


def parse_order_file(path: Path) -> list[Order]:
    orders: list[Order] = []
    if not path.exists():
        return orders
    for line_no, raw in enumerate(path.read_text("utf-8", errors="ignore").splitlines(), 1):
        body = strip_comment(raw)
        if not body or body.startswith("#"):
            continue
        parts = [p.strip() for p in body.split("\t")]
        if len(parts) < 4:
            parts = body.split()
        if len(parts) < 4:
            raise SystemExit(f"{path}:{line_no}: 格式应为：提到前面的词<TAB>原码<TAB>被挤下来的词<TAB>目标码")
        promoted, old_code, displaced, target_code = parts[:4]
        old_code = old_code.lower()
        target_code = target_code.lower()
        new_code = parts[4].lower() if len(parts) >= 5 else None
        if not promoted or not displaced or not CODE_RE.fullmatch(old_code) or not CODE_RE.fullmatch(target_code):
            raise SystemExit(f"{path}:{line_no}: 存在空字段或非法编码")
        if new_code and not CODE_RE.fullmatch(new_code):
            raise SystemExit(f"{path}:{line_no}: 补码非法")
        orders.append(Order(promoted, old_code, displaced, target_code, line_no, old_code == target_code, new_code))
    return orders


def iter_dict_entries(path: Path) -> Iterable[tuple[int, str, str, str]]:
    for no, line in enumerate(path.read_text("utf-8", errors="ignore").splitlines(), 1):
        if not line or line.startswith("#") or "\t" not in line:
            continue
        text, rest = line.split("\t", 1)
        fields = rest.split()
        if not fields:
            continue
        code = fields[0].split("〔", 1)[0]
        if text and CODE_RE.fullmatch(code or ""):
            yield no, text, code, line


def load_char_codes(root: Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for name in ("xmjd6.cx.dict.yaml", "xmjd6.danzi.dict.yaml"):
        path = root / name
        if not path.exists():
            continue
        for _, text, code, _ in iter_dict_entries(path):
            if len(text) != 1 or code.startswith("o"):
                continue
            result.setdefault(text, [])
            if code not in result[text]:
                result[text].append(code)
    for codes in result.values():
        codes.sort(key=lambda c: (-len(c), c))
    return result


def choose_char_code(char_codes: dict[str, list[str]], ch: str, prefix: str | None = None) -> str | None:
    codes = char_codes.get(ch) or []
    if prefix:
        for code in codes:
            if code.startswith(prefix):
                return code
    return codes[0] if codes else None


def third(code: str) -> str:
    return code[2:3]


def phrase_full_code(text: str, target_code: str, char_codes: dict[str, list[str]]) -> str | None:
    chars = list(text)
    n = len(chars)
    if n == 0:
        return None

    codes: list[str | None] = []
    if n == 2 and len(target_code) >= 4:
        codes = [
            choose_char_code(char_codes, chars[0], target_code[:2]),
            choose_char_code(char_codes, chars[1], target_code[2:4]),
        ]
    else:
        codes = [choose_char_code(char_codes, ch) for ch in chars]
    if any(c is None for c in codes):
        return None
    c = [x or "" for x in codes]

    if n == 1:
        return c[0]
    if n == 2:
        return c[0][:2] + c[1][:2] + third(c[0]) + third(c[1])
    if n == 3:
        return c[0][:1] + c[1][:1] + c[2][:1] + third(c[0]) + third(c[1]) + third(c[2])
    return c[0][:1] + c[1][:1] + c[2][:1] + c[-1][:1] + third(c[0]) + third(c[1])


def dict_files(root: Path) -> list[Path]:
    return sorted(p for p in root.glob("xmjd6*.dict.yaml") if p.name not in EXCLUDED_REMOVE_FILES)


def load_occupied_codes(root: Path, exclude_pairs: set[tuple[str, str]]) -> dict[str, set[str]]:
    occupied: dict[str, set[str]] = {}
    for path in dict_files(root):
        for _, text, code, _ in iter_dict_entries(path):
            if (text, code) in exclude_pairs:
                continue
            occupied.setdefault(code, set()).add(text)
    return occupied


def candidate_new_codes(target_code: str, full_code: str) -> list[str]:
    if full_code.startswith(target_code) and len(full_code) > len(target_code):
        return [full_code[:i] for i in range(len(target_code) + 1, len(full_code) + 1)]
    return [full_code]


def assign_new_codes(orders: list[Order], char_codes: dict[str, list[str]], occupied: dict[str, set[str]]) -> list[str]:
    warnings: list[str] = []
    reserved = {(o.promoted, o.target_code) for o in orders}
    for order in orders:
        if order.new_code:
            occupied.setdefault(order.new_code, set()).add(order.displaced)
            reserved.add((order.displaced, order.new_code))
            continue
        full = phrase_full_code(order.displaced, order.target_code, char_codes)
        order.full_code = full
        if not full:
            warnings.append(f"第 {order.line_no} 行：无法根据单字码生成“{order.displaced}”的新码，跳过补码")
            continue
        candidates = candidate_new_codes(order.target_code, full)
        chosen = candidates[-1]
        for code in candidates:
            occupants = occupied.get(code, set())
            # 允许占用者正好是会被移走的 promoted，或已经固化在该补码上的 displaced。
            if not occupants or occupants <= {order.promoted, order.displaced}:
                chosen = code
                break
        order.new_code = chosen
        occupied.setdefault(chosen, set()).add(order.displaced)
        reserved.add((order.displaced, chosen))
        if chosen == candidates[-1] and occupied.get(chosen, set()) - {order.displaced, order.promoted}:
            warnings.append(f"第 {order.line_no} 行：“{order.displaced}”生成 {chosen} 仍有同码，请检查")
    return warnings


def output_entries(orders: list[Order]) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for order in orders:
        key = (order.promoted, order.target_code)
        if key not in seen:
            entries.append((order.promoted, order.target_code))
            seen.add(key)
        if order.new_code:
            key = (order.displaced, order.new_code)
            if key not in seen:
                entries.append((order.displaced, order.new_code))
                seen.add(key)
    return entries


def load_candidate_entries(path: Path) -> list[tuple[str, str]]:
    if not path.exists():
        return []
    return [(text, code) for _, text, code, _ in iter_dict_entries(path)]


def merge_candidate_entries(
    existing: list[tuple[str, str]], orders: list[Order]
) -> list[tuple[str, str]]:
    remove_pairs: set[tuple[str, str]] = set()
    for order in orders:
        remove_pairs.add((order.promoted, order.old_code))
        remove_pairs.add((order.displaced, order.target_code))

    entries: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for entry in existing:
        if entry in remove_pairs or entry in seen:
            continue
        entries.append(entry)
        seen.add(entry)
    for entry in output_entries(orders):
        if entry not in seen:
            entries.append(entry)
            seen.add(entry)
    return entries


def write_candidate_dict(path: Path, entries: list[tuple[str, str]]) -> None:
    lines = [
        "# Rime dictionary",
        "# encoding: utf-8",
        "# 由 scripts/apply_candidate_order.py 根据 candidate_order.txt 生成。",
        "",
        "---",
        "name: xmjd6.candidate_order",
        'version: "2026-07-03"',
        "sort: original",
        "columns:",
        "  - text",
        "  - code",
        "...",
        "",
    ]
    for text, code in entries:
        lines.append(f"{text}\t{code}")
    path.write_text("\n".join(lines) + "\n", "utf-8")


def default_order_backup_path(path: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return path.with_name(f"{path.name}.{timestamp}.bak")


def clear_order_file(path: Path, backup_path: Path | None = None) -> Path | None:
    backup: Path | None = None
    if path.exists():
        backup = backup_path or default_order_backup_path(path)
        shutil.copy2(path, backup)
    path.write_text(ORDER_HEADER, "utf-8")
    return backup


def remove_old_entries(root: Path, orders: list[Order], dry_run: bool) -> tuple[int, list[str]]:
    remove_pairs: set[tuple[str, str]] = set()
    for order in orders:
        remove_pairs.add((order.promoted, order.old_code))
        if order.new_code:
            remove_pairs.add((order.displaced, order.target_code))

    total = 0
    changed_files: list[str] = []
    for path in dict_files(root):
        lines = path.read_text("utf-8", errors="ignore").splitlines()
        new_lines: list[str] = []
        removed = 0
        for line in lines:
            remove = False
            if line and not line.startswith("#") and "\t" in line:
                text, rest = line.split("\t", 1)
                fields = rest.split()
                code = fields[0].split("〔", 1)[0] if fields else ""
                if (text, code) in remove_pairs:
                    remove = True
            if remove:
                removed += 1
            else:
                new_lines.append(line)
        if removed:
            total += removed
            changed_files.append(f"{path.name}: -{removed}")
            if not dry_run:
                path.write_text("\n".join(new_lines) + "\n", "utf-8")
    return total, changed_files


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply candidate_order.txt to xmjd6.candidate_order.dict.yaml")
    parser.add_argument("--order", type=Path, default=ORDER_FILE, help="candidate_order.txt path")
    parser.add_argument("--output", type=Path, default=OUTPUT_FILE, help="output dict path")
    parser.add_argument("--apply", action="store_true", help="write output and remove old source entries")
    parser.add_argument("--dry-run", action="store_true", help="preview only; this is the default")
    parser.add_argument("--no-remove", action="store_true", help="only generate output dict, do not remove old source entries")
    parser.add_argument("--clear-order", action="store_true", help="after --apply succeeds, back up and clear candidate_order.txt")
    args = parser.parse_args()

    dry_run = (not args.apply) or args.dry_run
    orders = parse_order_file(args.order)
    char_codes = load_char_codes(ROOT)
    existing_entries = load_candidate_entries(args.output)

    exclude_pairs: set[tuple[str, str]] = set()
    for order in orders:
        exclude_pairs.add((order.promoted, order.old_code))
        exclude_pairs.add((order.displaced, order.target_code))
    occupied = load_occupied_codes(ROOT, exclude_pairs)
    for text, code in existing_entries:
        if (text, code) not in exclude_pairs:
            occupied.setdefault(code, set()).add(text)
    warnings = assign_new_codes(orders, char_codes, occupied)
    entries = merge_candidate_entries(existing_entries, orders)

    print(f"orders: {len(orders)}")
    print(f"candidate dict entries: {len(entries)}")
    for text, code in entries:
        print(f"  {text}\t{code}")
    for warning in warnings:
        print("WARN:", warning)

    if dry_run:
        print(f"dry-run: would write {args.output}")
    else:
        write_candidate_dict(args.output, entries)
        print(f"wrote: {args.output}")

    if args.no_remove:
        print("remove: skipped by --no-remove")
    else:
        total, changed = remove_old_entries(ROOT, orders, dry_run=dry_run)
        action = "would remove" if dry_run else "removed"
        print(f"{action}: {total} old source entries")
        for item in changed:
            print("  " + item)

    if args.clear_order:
        if dry_run:
            print(f"dry-run: would back up and clear {args.order}")
        else:
            backup = clear_order_file(args.order)
            print(f"cleared: {args.order}")
            if backup:
                print(f"backup: {backup}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
