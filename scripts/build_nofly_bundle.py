#!/usr/bin/env python3
"""Build a standalone Windows-first XMJD6 dictionary bundle without fly keys."""

from __future__ import annotations

import dataclasses
import enum
import argparse
import functools
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from collections.abc import Sequence
from pathlib import Path

from pypinyin import Style, pinyin


@dataclasses.dataclass(frozen=True)
class Reading:
    initial: str
    final: str


class DictionaryKind(enum.Enum):
    STANDARD = "standard"
    SSB = "ssb"
    COPY = "copy"


@dataclasses.dataclass
class DictionaryStats:
    source: str
    entries: int = 0
    output_entries: int = 0
    converted: int = 0
    collapsed: int = 0
    unresolved: list[str] = dataclasses.field(default_factory=list)


class UnresolvedEntriesError(RuntimeError):
    def __init__(self, source: Path, entries: Sequence[str]):
        self.source = source
        self.entries = list(entries)
        sample = "\n".join(self.entries[:20])
        super().__init__(f"{source}: unresolved standard entries:\n{sample}")


FINAL_KEYS: dict[str, tuple[str, ...]] = {
    "iu": ("q",),
    "ua": ("q",),
    "ei": ("w",),
    "un": ("j", "w"),
    "e": ("e",),
    "eng": ("r",),
    "uan": ("t",),
    "iong": ("y",),
    "ong": ("y",),
    "ang": ("p",),
    "a": ("s",),
    "ia": ("s",),
    "ie": ("d",),
    "ou": ("d",),
    "an": ("f",),
    "ing": ("g",),
    "uai": ("g",),
    "ai": ("h",),
    "ue": ("h",),
    "ve": ("h",),
    "er": ("j",),
    "u": ("j",),
    "i": ("k",),
    "o": ("l",),
    "uo": ("l",),
    "v": ("j", "l"),
    "ao": ("z",),
    "iang": ("x",),
    "uang": ("m", "x"),
    "iao": ("c",),
    "in": ("b",),
    "ui": ("b",),
    "en": ("n",),
    "n": ("n",),
    "ian": ("m",),
}

INITIALS = ("zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w")
PINYIN_COMMENT_RE = re.compile(r"〔([^〕]+)〕")
SENTENCE_PUNCTUATION = frozenset("，。！？；：、,.!?;:\n\r")
OverrideValue = list[Reading] | str


def _rewrite_initial(initial: str) -> str | None:
    if initial == "ch":
        return "w"
    if initial == "zh":
        return "q"
    return None


def _normalize_final(initial: str, final: str) -> str:
    final = final.replace("ü", "v")
    if initial in {"j", "q", "x", "y"} and final == "u":
        return "v"
    return final


def split_pinyin(value: str) -> Reading:
    normalized = value.strip().lower().replace("ü", "v")
    normalized = "".join(
        char
        for char in unicodedata.normalize("NFD", normalized)
        if unicodedata.category(char) != "Mn"
    )
    normalized = re.sub(r"[^a-zv]", "", normalized)
    initial = next((item for item in INITIALS if normalized.startswith(item)), "")
    final = normalized[len(initial) :]
    return Reading(initial, _normalize_final(initial, final))


def parse_pinyin_comment(line: str) -> set[Reading]:
    match = PINYIN_COMMENT_RE.search(line)
    if not match:
        return set()
    return {split_pinyin(item) for item in match.group(1).split("_") if item.strip()}


def contextual_readings(text: str) -> list[Reading]:
    errors = lambda value: list(value)
    initials = pinyin(text, style=Style.INITIALS, strict=False, errors=errors)
    finals = pinyin(text, style=Style.FINALS, strict=False, errors=errors)
    result: list[Reading] = []
    for initial_item, final_item in zip(initials, finals, strict=True):
        initial = initial_item[0]
        final = _normalize_final(initial, final_item[0])
        result.append(Reading(initial, final))
    return result


def _han_text(text: str) -> str:
    digit_names = "零一二三四五六七八九"
    result: list[str] = []
    for char in text:
        if char.isascii() and char.isdigit():
            result.append(digit_names[int(char)])
        elif char == "〇" or unicodedata.name(char, "").startswith(
            ("CJK UNIFIED IDEOGRAPH", "CJK COMPATIBILITY IDEOGRAPH")
        ):
            result.append(char)
    return "".join(result)


@functools.lru_cache(maxsize=None)
def _possible_character_readings(char: str) -> frozenset[Reading]:
    values = pinyin(
        char,
        style=Style.NORMAL,
        heteronym=True,
        strict=False,
        errors=lambda value: list(value),
    )
    if not values:
        return frozenset()
    return frozenset(split_pinyin(value) for value in values[0])


def _initial_keys(reading: Reading) -> tuple[str, ...]:
    if reading.initial == "ch":
        return ("j", "w")
    if reading.initial == "zh":
        return ("f", "q")
    if reading.initial == "sh":
        return ("e",)
    if not reading.initial:
        return ("x",)
    return (reading.initial[:1],)


def choose_reading(sound_prefix: str, readings: Sequence[Reading]) -> Reading | None:
    if not sound_prefix:
        return None
    matches: set[Reading] = set()
    for reading in readings:
        if sound_prefix[0] not in _initial_keys(reading):
            continue
        if len(sound_prefix) >= 2 and sound_prefix[1] not in FINAL_KEYS.get(reading.final, ()):
            continue
        matches.add(reading)
    if len(matches) == 1:
        return next(iter(matches))
    return None


def load_overrides(path: Path) -> dict[tuple[str, str, str], OverrideValue]:
    result: dict[tuple[str, str, str], OverrideValue] = {}
    if not path.exists():
        return result
    for line_no, raw in enumerate(path.read_text("utf-8-sig").splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) != 4 or not all(parts):
            raise ValueError(f"{path}:{line_no}: expected four tab-separated fields")
        dictionary, text, code, reading_text = parts
        if reading_text == "COPY":
            result[(dictionary, text, code)] = []
            continue
        if reading_text.startswith("CODE:"):
            replacement = reading_text.removeprefix("CODE:")
            if not re.fullmatch(r"[a-z;]+", replacement):
                raise ValueError(f"{path}:{line_no}: invalid replacement code")
            result[(dictionary, text, code)] = replacement
            continue
        readings: list[Reading] = []
        for item in reading_text.split(","):
            pair = item.split(":", 1)
            if len(pair) != 2:
                raise ValueError(f"{path}:{line_no}: invalid reading {item!r}")
            readings.append(Reading(pair[0], pair[1]))
        result[(dictionary, text, code)] = readings
    return result


def load_pronunciation_index(path: Path) -> dict[str, set[Reading]]:
    """Index source pinyin comments so rare characters do not depend on pypinyin."""

    result: dict[str, set[Reading]] = {}
    if not path.is_file():
        return result
    for raw in path.read_text("utf-8-sig", errors="replace").splitlines():
        if "\t" not in raw:
            continue
        text = raw.split("\t", 1)[0]
        if len(text) != 1:
            continue
        readings = parse_pinyin_comment(raw)
        if readings:
            result.setdefault(text, set()).update(readings)
    return result


def _set(chars: list[str], index: int, value: str | None) -> None:
    if value is not None and index < len(chars):
        chars[index] = value


def _slot_matches(reading: Reading, code: str, initial_index: int, final_index: int | None) -> bool:
    if initial_index >= len(code):
        return True
    if code[initial_index] not in _initial_keys(reading):
        return False
    if final_index is not None and final_index < len(code):
        return code[final_index] in FINAL_KEYS.get(reading.final, ())
    return True


def _reading_slots(count: int, kind: DictionaryKind) -> list[tuple[int, int, int | None]]:
    if count <= 0 or kind is DictionaryKind.COPY:
        return []
    if kind is DictionaryKind.SSB:
        return [(0, 0, None)]
    if count == 1:
        return [(0, 0, 1)]
    if count == 2:
        return [(0, 0, 1), (1, 2, 3)]
    if count == 3:
        return [(index, index, None) for index in range(3)]
    return [(0, 0, None), (1, 1, None), (2, 2, None), (count - 1, 3, None)]


def _readings_match_code(code: str, kind: DictionaryKind, readings: Sequence[Reading]) -> bool:
    if kind is DictionaryKind.COPY or not readings:
        return kind is DictionaryKind.COPY
    return all(
        _slot_matches(readings[reading_index], code, initial_index, final_index)
        for reading_index, initial_index, final_index in _reading_slots(len(readings), kind)
    )


def _slot_effect(reading: Reading, final_index: int | None) -> tuple[str | None, str | None]:
    return (
        _rewrite_initial(reading.initial),
        "x" if final_index is not None and reading.final == "uang" else None,
    )


def _choose_same_effect(
    candidates: set[Reading], final_index: int | None
) -> Reading | None:
    if not candidates:
        return None
    if len({_slot_effect(candidate, final_index) for candidate in candidates}) != 1:
        return None
    return sorted(candidates, key=lambda item: (item.initial, item.final))[0]


def _code_may_need_conversion(code: str, initial_index: int, final_index: int | None) -> bool:
    initial_is_fly = initial_index < len(code) and code[initial_index] in {"f", "j", "q", "w"}
    final_is_fly = (
        final_index is not None
        and final_index < len(code)
        and code[final_index] in {"m", "x"}
    )
    return initial_is_fly or final_is_fly


def _resolve_slot_reading(
    current: Reading,
    available: set[Reading],
    code: str,
    initial_index: int,
    final_index: int | None,
) -> Reading | None:
    if _slot_matches(current, code, initial_index, final_index):
        return current

    full_matches = {
        candidate
        for candidate in available
        if _slot_matches(candidate, code, initial_index, final_index)
    }
    chosen = _choose_same_effect(full_matches, final_index)
    if chosen is not None:
        return chosen

    initial_matches = {
        candidate
        for candidate in available
        if initial_index >= len(code) or code[initial_index] in _initial_keys(candidate)
    }
    chosen = _choose_same_effect(initial_matches, final_index)
    if chosen is not None:
        return chosen

    fallback = _choose_same_effect(available, final_index)
    if fallback is not None and _code_may_need_conversion(
        code, initial_index, final_index
    ):
        return fallback
    if not _code_may_need_conversion(code, initial_index, final_index):
        return current
    return None


def _readings_from_code(
    text: str,
    code: str,
    kind: DictionaryKind,
    pronunciations: dict[str, set[Reading]],
) -> list[Reading] | None:
    readings = contextual_readings(text)
    if len(readings) != len(text):
        return None
    for reading_index, initial_index, final_index in _reading_slots(len(readings), kind):
        available = _possible_character_readings(text[reading_index]) | pronunciations.get(
            text[reading_index], set()
        )
        chosen = _resolve_slot_reading(
            readings[reading_index],
            available,
            code,
            initial_index,
            final_index,
        )
        if chosen is None:
            return None
        readings[reading_index] = chosen
    return readings


def _entry_readings(
    dictionary: str,
    text: str,
    code: str,
    line: str,
    kind: DictionaryKind,
    overrides: dict[tuple[str, str, str], OverrideValue],
    pronunciations: dict[str, set[Reading]],
    override_code: str | None = None,
) -> list[Reading] | None:
    override = overrides.get((dictionary, text, override_code or code))
    if override is not None:
        if isinstance(override, str):
            raise TypeError("direct code overrides are handled by convert_dictionary")
        if not override:
            return []
        return override if _readings_match_code(code, kind, override) else None

    if any(char in SENTENCE_PUNCTUATION for char in text):
        return []

    phonetic_text = _han_text(text)
    if not phonetic_text:
        return []
    if len(phonetic_text) == 1:
        candidates = (
            parse_pinyin_comment(line)
            or pronunciations.get(phonetic_text, set())
            or _possible_character_readings(phonetic_text)
        )
        if candidates:
            contextual = contextual_readings(phonetic_text)
            current = contextual[0] if contextual else sorted(
                candidates, key=lambda item: (item.initial, item.final)
            )[0]
            reading = _resolve_slot_reading(current, candidates, code, 0, 1)
            return [reading] if reading is not None else None

    return _readings_from_code(phonetic_text, code, kind, pronunciations)


def convert_code(
    text: str,
    code: str,
    kind: DictionaryKind,
    readings: Sequence[Reading],
) -> str:
    """Normalize fly-key phonetic slots while leaving shape slots untouched."""

    if kind is DictionaryKind.COPY or not code or not readings:
        return code

    result = list(code)
    if kind is DictionaryKind.SSB:
        _set(result, 0, _rewrite_initial(readings[0].initial))
        return "".join(result)

    count = len(readings)
    if count == 1:
        _set(result, 0, _rewrite_initial(readings[0].initial))
        if readings[0].final == "uang":
            _set(result, 1, "x")
    elif count == 2:
        for reading, initial_index, final_index in (
            (readings[0], 0, 1),
            (readings[1], 2, 3),
        ):
            _set(result, initial_index, _rewrite_initial(reading.initial))
            if reading.final == "uang":
                _set(result, final_index, "x")
    elif count == 3:
        for index, reading in enumerate(readings):
            _set(result, index, _rewrite_initial(reading.initial))
    else:
        selected = (readings[0], readings[1], readings[2], readings[-1])
        for index, reading in enumerate(selected):
            _set(result, index, _rewrite_initial(reading.initial))

    return "".join(result)


ENTRY_CODE_RE = re.compile(r"^([a-z;]+)(.*)$")


STANDARD_DICTIONARIES = {
    "xmjd6.danzi",
    "xmjd6.cizu",
    "xmjd6.cx",
    "xmjd6.fjcy",
    "xmjd6.chaojizici",
    "xmjd6.same_code_short_first",
    "xmjd6.candidate_order",
}
SSB_DICTIONARIES = {"xmjd6.wxw", "xkjd6.ssb1"}
COPY_DICTIONARIES = {
    "xmjd6.zidingyi",
    "xmjd6.fuhao",
    "xmjd6.buchong",
    "xmjd6.lianjie",
    "xmjd6.user",
    "xmjd6.yingwen",
    "xkjd6.yingwen",
    "xkjd6.yinyang",
    "xkjd6.wanne",
}
SCHEMA_FILES = (
    "xmjd6.schema.yaml",
    "xmjd6.cx.schema.yaml",
    "xmjd6.gbk.schema.yaml",
    "pinyin_simp.schema.yaml",
    "liangfen.schema.yaml",
    "english.schema.yaml",
)
SUPPORT_DICTIONARIES = (
    "xmjd6.dict.yaml",
    "xmjd6.extended.dict.yaml",
    "xmjd6.cx.dict.yaml",
    "xmjd6.gbk.dict.yaml",
    "xmjd6.en.dict.yaml",
    "pinyin_simp.dict.yaml",
    "liangfen.dict.yaml",
    "english.dict.yaml",
)
RUNTIME_TEXT_FILES = (
    "anniversaries.txt",
    "candidate_order.txt",
    "dynamic_phrases.txt",
)


def active_imports(path: Path) -> list[str]:
    """Return uncommented import table names in source order."""

    imports: list[str] = []
    in_imports = False
    for raw in path.read_text("utf-8-sig").splitlines():
        if re.match(r"^import_tables\s*:", raw):
            in_imports = True
            continue
        if not in_imports or raw.lstrip().startswith("#"):
            continue
        if raw and not raw[0].isspace():
            break
        match = re.match(r"^\s+-\s+([A-Za-z0-9_.-]+)(?:\s*(?:#.*)?)?$", raw)
        if match:
            imports.append(match.group(1))
    return imports


def dictionary_kind(name: str) -> DictionaryKind:
    if name in SSB_DICTIONARIES:
        return DictionaryKind.SSB
    if name in COPY_DICTIONARIES:
        return DictionaryKind.COPY
    if name in STANDARD_DICTIONARIES:
        return DictionaryKind.STANDARD
    if name.startswith("xkjd6."):
        return DictionaryKind.STANDARD
    raise ValueError(f"unclassified dictionary: {name}")


def convert_dictionary(
    source: Path,
    output: Path,
    kind: DictionaryKind,
    overrides: dict[tuple[str, str, str], OverrideValue] | None = None,
    pronunciations: dict[str, set[Reading]] | None = None,
) -> DictionaryStats:
    """Convert one Rime dictionary without altering non-code fields."""

    stats = DictionaryStats(source=source.name)
    if kind is DictionaryKind.COPY:
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, output)
        for raw in source.read_text("utf-8-sig", errors="replace").splitlines():
            if raw and not raw.lstrip().startswith("#") and "\t" in raw:
                stats.entries += 1
        stats.output_entries = stats.entries
        return stats

    override_map = overrides or {}
    pronunciation_map = pronunciations or {}
    payload = source.read_bytes()
    has_bom = payload.startswith(b"\xef\xbb\xbf")
    text_data = payload.decode("utf-8-sig")
    result_lines: list[str] = []
    seen: set[tuple[str, str]] = set()

    for line_no, raw in enumerate(text_data.splitlines(keepends=True), 1):
        newline = ""
        body = raw
        if raw.endswith("\r\n"):
            body, newline = raw[:-2], "\r\n"
        elif raw.endswith(("\n", "\r")):
            body, newline = raw[:-1], raw[-1]

        if not body or body.lstrip().startswith("#") or "\t" not in body:
            result_lines.append(raw)
            continue

        fields = body.split("\t")
        text = fields[0]
        match = ENTRY_CODE_RE.match(fields[1]) if len(fields) >= 2 else None
        if not text or match is None:
            result_lines.append(raw)
            continue

        code, code_suffix = match.groups()
        stats.entries += 1
        override = override_map.get((source.name, text, code))
        if isinstance(override, str):
            converted = override
        else:
            code_prefix = (
                "o"
                if source.name == "xmjd6.cx.dict.yaml" and code.startswith("o")
                else ""
            )
            sound_code = code[len(code_prefix) :]
            readings = _entry_readings(
                source.name,
                text,
                sound_code,
                body,
                kind,
                override_map,
                pronunciation_map,
                code,
            )
            if readings is None:
                stats.unresolved.append(f"line {line_no}: {text}\t{code}")
                result_lines.append(raw)
                continue
            converted = code_prefix + convert_code(text, sound_code, kind, readings)
        if converted != code:
            stats.converted += 1
        key = (text, converted)
        if key in seen:
            stats.collapsed += 1
            continue
        seen.add(key)
        fields[1] = converted + code_suffix
        result_lines.append("\t".join(fields) + newline)
        stats.output_entries += 1

    if stats.unresolved:
        raise UnresolvedEntriesError(source, stats.unresolved)

    output.parent.mkdir(parents=True, exist_ok=True)
    encoded = "".join(result_lines).encode("utf-8")
    output.write_bytes((b"\xef\xbb\xbf" if has_bom else b"") + encoded)
    return stats


def _copy_tree(source: Path, output: Path) -> None:
    def ignore(_directory: str, names: list[str]) -> set[str]:
        return {
            name
            for name in names
            if name in {".DS_Store", "__pycache__"}
            or name.endswith((".pyc", ".pyo"))
        }

    shutil.copytree(source, output, ignore=ignore)


def _copy_required(source: Path, output: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"required bundle resource is missing: {source.name}")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, output)


def _copy_optional(source: Path, output: Path) -> bool:
    if not source.is_file():
        return False
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, output)
    return True


def _patch_schema_name(path: Path) -> None:
    payload = path.read_bytes()
    has_bom = payload.startswith(b"\xef\xbb\xbf")
    content = payload.decode("utf-8-sig")
    patched, count = re.subn(
        r"^(\s*name:\s*).*$",
        r"\g<1>键道6·无飞键版",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise ValueError(f"cannot locate schema name in {path}")
    path.write_bytes((b"\xef\xbb\xbf" if has_bom else b"") + patched.encode("utf-8"))


def _readme_text() -> str:
    return """# 键道6·无飞键版（Windows）

这是一个**独立生成的 Windows 优先分发目录**，构建程序不会自动安装，也不会把任何文件复制到当前 Rime 用户目录。

## 规则

- `ch → W`，例如超：`wz`。
- `zh → Q`，例如找：`qz`。
- `uang → X`，例如光：`gx`。
- 普通的 `j`、`q`、`w`、`f` 声母和其他韵母保持原规则。

## Windows 手动使用

1. 先运行 `verify_windows.cmd`，只读检查包是否完整。
2. 退出小狼毫或备份现有用户目录后，按自己的安装方式把本目录内容放入 Rime 用户目录。
3. 在小狼毫菜单中执行“重新部署”。

内部方案标识仍是 schema_id: `xmjd6`，因此本版用于**替换原版**，不能与原版同时共存。此目录没有执行安装，也不包含 macOS 编译产物、用户数据库或已编译的 `build` 目录。

`conversion-report.txt` 记录每个码表的转换与去重数量。若要重新生成，请在源码项目中运行 `python scripts/build_nofly_bundle.py`。
"""


def _windows_verifier_text() -> str:
    return r"""@echo off
setlocal EnableExtensions
chcp 65001 >nul
set "ROOT=%~dp0"
set "FAILED=0"

call :require "xmjd6.schema.yaml"
call :require "xmjd6.extended.dict.yaml"
call :require "default.yaml"
call :require "default.custom.yaml"
call :require "weasel.custom.yaml"
call :require "symbols.yaml"
call :require "conversion-report.txt"
call :require "lua\xmjd6"
call :require "opencc"

if exist "%ROOT%build\" (
  echo [FAIL] Package must not contain a build directory.
  set "FAILED=1"
)

if "%FAILED%"=="0" (
  echo [OK] Package structure is complete. No files were installed or changed.
) else (
  echo [FAIL] Package verification failed.
)
exit /b %FAILED%

:require
if not exist "%ROOT%%~1" (
  echo [MISS] %~1
  set "FAILED=1"
) else (
  echo [ OK ] %~1
)
exit /b 0
"""


def _write_report(output: Path, stats: Sequence[DictionaryStats]) -> None:
    total_entries = sum(item.entries for item in stats)
    total_output = sum(item.output_entries for item in stats)
    total_converted = sum(item.converted for item in stats)
    total_collapsed = sum(item.collapsed for item in stats)
    unresolved = sum(len(item.unresolved) for item in stats)
    lines = [
        "XMJD6 no-fly conversion report",
        "mapping: ch=W, zh=Q, uang=X",
        "",
        f"input entries: {total_entries}",
        f"output entries: {total_output}",
        f"converted entries: {total_converted}",
        f"collapsed duplicates: {total_collapsed}",
        f"unresolved entries: {unresolved}",
        "",
        "per dictionary:",
    ]
    for item in stats:
        lines.append(
            f"- {item.source}: input={item.entries}, output={item.output_entries}, "
            f"converted={item.converted}, collapsed={item.collapsed}, "
            f"unresolved={len(item.unresolved)}"
        )
    (output / "conversion-report.txt").write_text("\n".join(lines) + "\n", "utf-8")


def validate_bundle(output: Path) -> list[str]:
    """Return deterministic validation errors without modifying the bundle."""

    errors: list[str] = []
    required = {
        "default.yaml",
        "default.custom.yaml",
        "weasel.custom.yaml",
        "symbols.yaml",
        "xmjd6.schema.yaml",
        "xmjd6.dict.yaml",
        "xmjd6.extended.dict.yaml",
        "README.md",
        "verify_windows.cmd",
        "conversion-report.txt",
    }
    required.update(SCHEMA_FILES)
    required.update(RUNTIME_TEXT_FILES)
    for name in sorted(required):
        if not (output / name).is_file():
            errors.append(f"missing file: {name}")

    for directory in ("lua/xmjd6", "opencc"):
        if not (output / directory).is_dir():
            errors.append(f"missing directory: {directory}")

    extended = output / "xmjd6.extended.dict.yaml"
    if extended.is_file():
        for name in active_imports(extended):
            relative = f"{name}.dict.yaml"
            if not (output / relative).is_file():
                errors.append(f"missing active import: {relative}")

    schema = output / "xmjd6.schema.yaml"
    if schema.is_file():
        content = schema.read_text("utf-8-sig")
        if not re.search(r"^\s*schema_id:\s*xmjd6\s*$", content, re.MULTILINE):
            errors.append("main schema_id is not xmjd6")
        if not re.search(r"^\s*name:\s*键道6·无飞键版\s*$", content, re.MULTILINE):
            errors.append("main schema display name is not the no-fly name")

    for path in output.rglob("*") if output.exists() else ():
        relative = path.relative_to(output).as_posix()
        if path.is_dir() and relative == "build":
            errors.append("forbidden directory: build")
        if path.is_file() and path.suffix.lower() in {
            ".bin",
            ".hskin",
            ".zip",
            ".rar",
            ".7z",
        }:
            errors.append(f"forbidden artifact: {relative}")
        if path.is_file() and path.name in {"installation.yaml", "user.yaml"}:
            errors.append(f"forbidden local state: {relative}")
    return errors


def build_bundle(root: Path, output: Path, clean: bool = True) -> list[DictionaryStats]:
    """Build and atomically publish a standalone Windows-first bundle."""

    root = root.resolve()
    output = output.resolve()
    extended = root / "xmjd6.extended.dict.yaml"
    imports = active_imports(extended)
    stage = output.with_name(f".{output.name}.tmp")
    if stage.exists():
        shutil.rmtree(stage)
    if output.exists() and not clean:
        raise FileExistsError(output)
    stage.mkdir(parents=True)

    try:
        _copy_required(root / "default_win.yaml", stage / "default.yaml")
        _copy_required(root / "default.custom_win.yaml", stage / "default.custom.yaml")
        for name in ("weasel.custom.yaml", "symbols.yaml", *SCHEMA_FILES, *RUNTIME_TEXT_FILES):
            _copy_required(root / name, stage / name)
        _patch_schema_name(stage / "xmjd6.schema.yaml")

        for name in SUPPORT_DICTIONARIES:
            _copy_optional(root / name, stage / name)
        _copy_optional(root / "xmjd6.custom.yaml", stage / "xmjd6.custom.yaml")

        for directory in ("lua/xmjd6", "opencc"):
            source_directory = root / directory
            if not source_directory.is_dir():
                raise FileNotFoundError(f"required bundle resource is missing: {directory}")
            _copy_tree(source_directory, stage / directory)
        if (root / "Fonts").is_dir():
            _copy_tree(root / "Fonts", stage / "Fonts")

        overrides = load_overrides(root / "scripts/nofly_overrides.tsv")
        pronunciations = load_pronunciation_index(root / "xmjd6.cx.dict.yaml")
        stats: list[DictionaryStats] = []
        transformed_names = set(imports)
        if (root / "xmjd6.cx.dict.yaml").is_file():
            transformed_names.add("xmjd6.cx")
        for name in sorted(transformed_names):
            source = root / f"{name}.dict.yaml"
            if not source.is_file():
                raise FileNotFoundError(f"active dictionary is missing: {source.name}")
            stats.append(
                convert_dictionary(
                    source,
                    stage / source.name,
                    dictionary_kind(name),
                    overrides,
                    pronunciations,
                )
            )

        (stage / "README.md").write_text(_readme_text(), "utf-8")
        (stage / "verify_windows.cmd").write_text(_windows_verifier_text(), "utf-8", newline="\r\n")
        _write_report(stage, stats)

        errors = validate_bundle(stage)
        if errors:
            raise RuntimeError("bundle validation failed:\n" + "\n".join(errors))

        if output.exists():
            shutil.rmtree(output)
        stage.rename(output)
        return stats
    except BaseException:
        if stage.exists():
            shutil.rmtree(stage)
        raise


def _find_rime_deployer() -> Path:
    discovered = shutil.which("rime_deployer")
    candidates = [
        Path(discovered) if discovered else None,
        Path("/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer"),
    ]
    for candidate in candidates:
        if candidate is not None and candidate.is_file():
            return candidate
    raise FileNotFoundError(
        "rime_deployer was not found; set --rime-deployer to its executable path"
    )


def _default_shared_data(deployer: Path) -> Path:
    squirrel_shared = deployer.parent.parent / "SharedSupport"
    return squirrel_shared if squirrel_shared.is_dir() else deployer.parent


def compile_bundle(
    bundle: Path,
    deployer: Path | None = None,
    shared_data: Path | None = None,
) -> list[str]:
    """Compile the main schema in temporary directories without touching the bundle."""

    bundle = bundle.resolve()
    errors = validate_bundle(bundle)
    if errors:
        raise RuntimeError("bundle validation failed:\n" + "\n".join(errors))
    deployer_path = (deployer or _find_rime_deployer()).resolve()
    shared_path = (shared_data or _default_shared_data(deployer_path)).resolve()

    with tempfile.TemporaryDirectory(prefix="xmjd6-nofly-compile-") as tmp_name:
        tmp = Path(tmp_name)
        user_data = tmp / "user"
        staging = tmp / "staging"
        shutil.copytree(bundle, user_data)
        staging.mkdir()
        command = [
            str(deployer_path),
            "--compile",
            str(user_data / "xmjd6.schema.yaml"),
            str(user_data),
            str(shared_path),
            str(staging),
        ]
        completed = subprocess.run(
            command,
            cwd=user_data,
            text=True,
            capture_output=True,
            check=False,
        )
        if completed.returncode != 0:
            details = "\n".join(
                part.strip() for part in (completed.stdout, completed.stderr) if part.strip()
            )
            raise RuntimeError(
                f"rime_deployer failed with exit code {completed.returncode}"
                + (f":\n{details}" if details else "")
            )

        artifacts: list[str] = []
        for base, prefix in ((staging, ""), (user_data / "build", "build/")):
            if not base.is_dir():
                continue
            artifacts.extend(
                prefix + path.relative_to(base).as_posix()
                for path in base.rglob("*")
                if path.is_file() and path.stat().st_size > 0
            )
        artifacts.sort()
        required_suffixes = (
            "xmjd6.schema.yaml",
            ".table.bin",
            ".prism.bin",
            ".reverse.bin",
        )
        missing = [
            suffix
            for suffix in required_suffixes
            if not any(name.endswith(suffix) for name in artifacts)
        ]
        if missing:
            raise RuntimeError(
                "compile completed without required artifacts: "
                + ", ".join(missing)
                + "\nobserved artifacts:\n"
                + "\n".join(artifacts)
            )
        return artifacts


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    project_root = Path(__file__).resolve().parents[1]
    parser.add_argument("--root", type=Path, default=project_root)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--compile-check", action="store_true")
    parser.add_argument("--rime-deployer", type=Path)
    parser.add_argument("--shared-data", type=Path)
    args = parser.parse_args(argv)
    output = args.output or args.root / "xmjd6-nofly"

    if args.check:
        errors = validate_bundle(output)
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
        print(f"Bundle OK: {output}")
        return 0

    if args.compile_check:
        artifacts = compile_bundle(
            output,
            deployer=args.rime_deployer,
            shared_data=args.shared_data,
        )
        print(f"Compile OK: {len(artifacts)} generated artifacts")
        return 0

    stats = build_bundle(args.root, output)
    print(
        f"Built {output}: {sum(item.converted for item in stats)} converted, "
        f"{sum(item.collapsed for item in stats)} duplicates collapsed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
