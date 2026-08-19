#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.build_nofly_bundle import (
    DictionaryKind,
    Reading,
    choose_reading,
    contextual_readings,
    convert_code,
    convert_dictionary,
    load_overrides,
    parse_pinyin_comment,
    UnresolvedEntriesError,
)


class ConversionUnitTests(unittest.TestCase):
    def test_single_character_fly_keys_are_normalized(self) -> None:
        self.assertEqual(
            convert_code("超", "jzvo", DictionaryKind.STANDARD, [Reading("ch", "ao")]),
            "wzvo",
        )
        self.assertEqual(
            convert_code("找", "fziuv", DictionaryKind.STANDARD, [Reading("zh", "ao")]),
            "qziuv",
        )
        self.assertEqual(
            convert_code("光", "gmiou", DictionaryKind.STANDARD, [Reading("g", "uang")]),
            "gxiou",
        )

    def test_native_initials_are_not_rewritten(self) -> None:
        cases = [
            ("均", "jw", Reading("j", "un")),
            ("无", "wj", Reading("w", "u")),
            ("求", "qq", Reading("q", "iu")),
            ("服", "fj", Reading("f", "u")),
        ]
        for text, code, reading in cases:
            with self.subTest(text=text, code=code):
                self.assertEqual(
                    convert_code(text, code, DictionaryKind.STANDARD, [reading]),
                    code,
                )

    def test_two_character_sound_positions_are_normalized(self) -> None:
        readings = [Reading("ch", "ao"), Reading("zh", "uang")]
        self.assertEqual(
            convert_code("超装", "jzfmvo", DictionaryKind.STANDARD, readings),
            "wzqxvo",
        )

    def test_three_character_initial_positions_are_normalized(self) -> None:
        readings = [Reading("ch", "ao"), Reading("zh", "ao"), Reading("g", "uang")]
        self.assertEqual(
            convert_code("超找光", "jfgvio", DictionaryKind.STANDARD, readings),
            "wqgvio",
        )

    def test_long_phrase_uses_first_three_and_last_initials(self) -> None:
        readings = [
            Reading("ch", "ao"),
            Reading("zh", "ao"),
            Reading("g", "uang"),
            Reading("m", "ing"),
            Reading("zh", "ong"),
        ]
        self.assertEqual(
            convert_code("超找光明中", "jfgfvo", DictionaryKind.STANDARD, readings),
            "wqgqvo",
        )

    def test_ssb_only_treats_first_position_as_an_initial(self) -> None:
        readings = [Reading("ch", "ao"), Reading("zh", "ao")]
        self.assertEqual(
            convert_code("超找", "jfm", DictionaryKind.SSB, readings),
            "wfm",
        )

    def test_copy_dictionary_is_never_rewritten(self) -> None:
        readings = [Reading("ch", "ao")]
        self.assertEqual(
            convert_code("超", "jzvo", DictionaryKind.COPY, readings),
            "jzvo",
        )


class ReadingResolutionTests(unittest.TestCase):
    def test_cx_comment_readings_are_parsed(self) -> None:
        self.assertEqual(
            parse_pinyin_comment("车\tjeva\t0 # 〔chē_jū〕"),
            {Reading("ch", "e"), Reading("j", "v")},
        )

    def test_polyphonic_che_uses_original_sound_prefix(self) -> None:
        readings = [Reading("ch", "e"), Reading("j", "v")]
        self.assertEqual(choose_reading("je", readings), Reading("ch", "e"))
        self.assertEqual(choose_reading("we", readings), Reading("ch", "e"))
        self.assertEqual(choose_reading("jl", readings), Reading("j", "v"))

    def test_ambiguous_or_unmatched_prefix_is_not_guessed(self) -> None:
        readings = [Reading("ch", "ao"), Reading("ch", "ao")]
        self.assertEqual(choose_reading("jz", readings), Reading("ch", "ao"))
        self.assertIsNone(choose_reading("bk", readings))

    def test_contextual_phrase_reading_handles_polyphony(self) -> None:
        self.assertEqual(
            contextual_readings("火车"),
            [Reading("h", "uo"), Reading("ch", "e")],
        )
        self.assertEqual(
            contextual_readings("银行行长"),
            [
                Reading("y", "in"),
                Reading("h", "ang"),
                Reading("h", "ang"),
                Reading("zh", "ang"),
            ],
        )

    def test_override_file_is_strictly_parsed(self) -> None:
        from tempfile import TemporaryDirectory

        with TemporaryDirectory() as tmp_name:
            path = Path(tmp_name) / "overrides.tsv"
            path.write_text(
                "# dictionary<TAB>text<TAB>code<TAB>readings\n"
                "xmjd6.cizu.dict.yaml\t火车\thlje\th:uo,ch:e\n",
                "utf-8",
            )
            self.assertEqual(
                load_overrides(path),
                {
                    ("xmjd6.cizu.dict.yaml", "火车", "hlje"): [
                        Reading("h", "uo"),
                        Reading("ch", "e"),
                    ]
                },
            )


class DictionaryTransformTests(unittest.TestCase):
    def test_dictionary_conversion_preserves_header_bom_and_trailing_fields(self) -> None:
        source_text = (
            "# Rime dictionary\n"
            "---\n"
            "name: sample\n"
            "...\n"
            "超\tjzvo\t900 # 高频\n"
            "找\tfz\t800\n"
        )
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "sample.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_bytes(b"\xef\xbb\xbf" + source_text.encode("utf-8"))

            stats = convert_dictionary(source, output, DictionaryKind.STANDARD)

            self.assertTrue(output.read_bytes().startswith(b"\xef\xbb\xbf"))
            self.assertEqual(
                output.read_text("utf-8-sig"),
                source_text.replace("超\tjzvo", "超\twzvo").replace("找\tfz", "找\tqz"),
            )
            self.assertEqual(stats.entries, 2)
            self.assertEqual(stats.converted, 2)
            self.assertEqual(stats.collapsed, 0)

    def test_duplicate_fly_variants_collapse_stably(self) -> None:
        source_text = "超\tjz\n抄\twz\n超\twz\n找\tfz\n找\tqz\n"
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "sample.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_text(source_text, "utf-8")

            stats = convert_dictionary(source, output, DictionaryKind.STANDARD)

            self.assertEqual(output.read_text("utf-8"), "超\twz\n抄\twz\n找\tqz\n")
            self.assertEqual(stats.entries, 5)
            self.assertEqual(stats.output_entries, 3)
            self.assertEqual(stats.collapsed, 2)

    def test_copy_dictionary_is_byte_for_byte_identical(self) -> None:
        payload = b"\xef\xbb\xbf# custom\r\n\xe8\xb6\x85\tjzvo\r\n"
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "custom.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_bytes(payload)

            stats = convert_dictionary(source, output, DictionaryKind.COPY)

            self.assertEqual(output.read_bytes(), payload)
            self.assertEqual(stats.converted, 0)

    def test_unmatched_standard_entry_fails_without_guessing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "sample.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_text("超\tbk\n", "utf-8")

            with self.assertRaises(UnresolvedEntriesError) as raised:
                convert_dictionary(source, output, DictionaryKind.STANDARD)

            self.assertIn("超", str(raised.exception))
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
