#!/usr/bin/env python3
"""Build a standalone Windows-first XMJD6 dictionary bundle without fly keys."""

from __future__ import annotations

import dataclasses
import enum
import re
import shutil
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
    "un": ("w",),
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
    "v": ("l",),
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


def _initial_keys(reading: Reading) -> tuple[str, ...]:
    if reading.initial == "ch":
        if reading.final in {"ao", "e"}:
            return ("j", "w")
        if reading.final in {"ai", "an", "ang", "en", "eng", "u", "un"}:
            return ("j",)
        return ("w",)
    if reading.initial == "zh":
        if reading.final in {"ai", "ao", "e"}:
            return ("f", "q")
        if reading.final in {"an", "ang", "ei", "en", "eng", "u", "un"}:
            return ("q",)
        return ("f",)
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


def load_overrides(path: Path) -> dict[tuple[str, str, str], list[Reading]]:
    result: dict[tuple[str, str, str], list[Reading]] = {}
    if not path.exists():
        return result
    for line_no, raw in enumerate(path.read_text("utf-8-sig").splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) != 4 or not all(parts):
            raise ValueError(f"{path}:{line_no}: expected four tab-separated fields")
        dictionary, text, code, reading_text = parts
        readings: list[Reading] = []
        for item in reading_text.split(","):
            pair = item.split(":", 1)
            if len(pair) != 2:
                raise ValueError(f"{path}:{line_no}: invalid reading {item!r}")
            readings.append(Reading(pair[0], pair[1]))
        result[(dictionary, text, code)] = readings
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


def _readings_match_code(code: str, kind: DictionaryKind, readings: Sequence[Reading]) -> bool:
    if kind is DictionaryKind.COPY or not readings:
        return kind is DictionaryKind.COPY
    if kind is DictionaryKind.SSB:
        return _slot_matches(readings[0], code, 0, None)
    if len(readings) == 1:
        return _slot_matches(readings[0], code, 0, 1)
    if len(readings) == 2:
        return _slot_matches(readings[0], code, 0, 1) and _slot_matches(readings[1], code, 2, 3)
    if len(readings) == 3:
        return all(_slot_matches(reading, code, index, None) for index, reading in enumerate(readings))
    selected = (readings[0], readings[1], readings[2], readings[-1])
    return all(_slot_matches(reading, code, index, None) for index, reading in enumerate(selected))


def _entry_readings(
    dictionary: str,
    text: str,
    code: str,
    line: str,
    kind: DictionaryKind,
    overrides: dict[tuple[str, str, str], list[Reading]],
) -> list[Reading] | None:
    override = overrides.get((dictionary, text, code))
    if override is not None:
        return override if _readings_match_code(code, kind, override) else None

    if len(text) == 1:
        candidates = parse_pinyin_comment(line)
        if candidates:
            reading = choose_reading(code[:2], tuple(candidates))
            return [reading] if reading is not None else None

    readings = contextual_readings(text)
    if len(readings) != len(text) or not _readings_match_code(code, kind, readings):
        return None
    return readings


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


def convert_dictionary(
    source: Path,
    output: Path,
    kind: DictionaryKind,
    overrides: dict[tuple[str, str, str], list[Reading]] | None = None,
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
        readings = _entry_readings(source.name, text, code, body, kind, override_map)
        if readings is None:
            stats.unresolved.append(f"line {line_no}: {text}\t{code}")
            result_lines.append(raw)
            continue

        converted = convert_code(text, code, kind, readings)
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
