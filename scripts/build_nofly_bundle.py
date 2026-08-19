#!/usr/bin/env python3
"""Build a standalone Windows-first XMJD6 dictionary bundle without fly keys."""

from __future__ import annotations

import dataclasses
import enum
import re
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
