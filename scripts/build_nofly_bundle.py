#!/usr/bin/env python3
"""Build a standalone Windows-first XMJD6 dictionary bundle without fly keys."""

from __future__ import annotations

import dataclasses
import enum
from collections.abc import Sequence


@dataclasses.dataclass(frozen=True)
class Reading:
    initial: str
    final: str


class DictionaryKind(enum.Enum):
    STANDARD = "standard"
    SSB = "ssb"
    COPY = "copy"


def _rewrite_initial(initial: str) -> str | None:
    if initial == "ch":
        return "w"
    if initial == "zh":
        return "q"
    return None


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
