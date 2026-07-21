#!/usr/bin/env python3
"""Move valid dynamic phrases into an XMJD static custom dictionary.

Dynamic phrase records are UTF-8 ``text<TAB>code`` lines.  Valid records absent
from the static dictionary are appended to it; every valid dynamic record that
exists in the resulting static dictionary is then removed from the dynamic file.
Comments, blank lines, and malformed dynamic lines are retained verbatim.
"""

from __future__ import annotations

import argparse
import os
import tempfile
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DYNAMIC = PROJECT_ROOT / "dynamic_phrases.txt"
DEFAULT_DICTIONARY = PROJECT_ROOT / "xmjd6.zidingyi.dict.yaml"


@dataclass(frozen=True)
class Phrase:
    text: str
    code: str


def parse_phrase_line(line: str) -> Phrase | None:
    """Parse one strict ``text<TAB>code`` record without accepting comments."""
    if not line.strip() or line.lstrip().startswith("#"):
        return None
    if line.count("\t") != 1:
        return None
    text, code = (part.strip() for part in line.split("\t", 1))
    if not text or not code:
        return None
    return Phrase(text=text, code=code)


def read_lines(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines(keepends=True)
    except FileNotFoundError as exc:
        raise SystemExit(f"找不到文件：{path}") from exc


def atomic_write(path: Path, content: str) -> None:
    """Replace a UTF-8 text file without leaving a partly-written target."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent, text=True
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
    except BaseException:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def append_static_records(static_lines: list[str], phrases: list[Phrase]) -> str:
    content = "".join(static_lines)
    if not phrases:
        return content
    if content and not content.endswith(("\n", "\r")):
        content += "\n"
    return content + "".join(f"{phrase.text}\t{phrase.code}\n" for phrase in phrases)


def retained_dynamic_content(dynamic_lines: list[str], static_pairs: set[Phrase]) -> tuple[str, int]:
    retained: list[str] = []
    removed = 0
    for line in dynamic_lines:
        phrase = parse_phrase_line(line.rstrip("\r\n"))
        if phrase is not None and phrase in static_pairs:
            removed += 1
            continue
        retained.append(line)
    return "".join(retained), removed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="将 dynamic_phrases.txt 中的有效词条归档到自定义静态词库。"
    )
    parser.add_argument(
        "--dynamic",
        type=Path,
        default=DEFAULT_DYNAMIC,
        help=f"动态词文件（默认：{DEFAULT_DYNAMIC}）",
    )
    parser.add_argument(
        "--dictionary",
        type=Path,
        default=DEFAULT_DICTIONARY,
        help=f"静态词库（默认：{DEFAULT_DICTIONARY}）",
    )
    parser.add_argument("--dry-run", action="store_true", help="只报告，不写入文件")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    dynamic_path = args.dynamic.expanduser().resolve()
    dictionary_path = args.dictionary.expanduser().resolve()

    dynamic_lines = read_lines(dynamic_path)
    dictionary_lines = read_lines(dictionary_path)

    static_pairs = {
        phrase
        for line in dictionary_lines
        if (phrase := parse_phrase_line(line.rstrip("\r\n"))) is not None
    }

    dynamic_records: list[Phrase] = []
    malformed = 0
    for line in dynamic_lines:
        raw_line = line.rstrip("\r\n")
        phrase = parse_phrase_line(raw_line)
        if phrase is not None:
            dynamic_records.append(phrase)
        elif raw_line.strip() and not raw_line.lstrip().startswith("#"):
            malformed += 1

    additions: list[Phrase] = []
    seen_dynamic: set[Phrase] = set()
    for phrase in dynamic_records:
        if phrase in seen_dynamic:
            continue
        seen_dynamic.add(phrase)
        if phrase not in static_pairs:
            static_pairs.add(phrase)
            additions.append(phrase)

    dictionary_content = append_static_records(dictionary_lines, additions)
    dynamic_content, removed = retained_dynamic_content(dynamic_lines, static_pairs)

    changed_dictionary = dictionary_content != "".join(dictionary_lines)
    changed_dynamic = dynamic_content != "".join(dynamic_lines)

    print(f"动态有效词条：{len(dynamic_records)}")
    print(f"动态格式异常行：{malformed}")
    print(f"新增静态词条：{len(additions)}")
    print(f"从动态词库移除：{removed}")
    if args.dry_run:
        print("演练模式：未写入文件")
        return 0

    # Write the durable destination first. If interruption occurs before dynamic
    # cleanup, a rerun is safe: it will recognize the static entries and remove
    # them from the dynamic file.
    if changed_dictionary:
        atomic_write(dictionary_path, dictionary_content)
    if changed_dynamic:
        atomic_write(dynamic_path, dynamic_content)
    print("已完成归档" if changed_dictionary or changed_dynamic else "无需归档")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
