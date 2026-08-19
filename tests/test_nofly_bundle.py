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
    active_imports,
    build_bundle,
    compile_bundle,
    DictionaryKind,
    Reading,
    choose_reading,
    contextual_readings,
    convert_code,
    convert_dictionary,
    load_overrides,
    parse_pinyin_comment,
    UnresolvedEntriesError,
    validate_bundle,
)


def make_bundle_fixture(root: Path) -> None:
    (root / "default_win.yaml").write_text("schema_list:\n  - schema: xmjd6\n", "utf-8")
    (root / "default.custom_win.yaml").write_text("patch:\n  menu/page_size: 6\n", "utf-8")
    (root / "weasel.custom.yaml").write_text("patch:\n  style/font_point: 14\n", "utf-8")
    (root / "symbols.yaml").write_text("punctuator:\n", "utf-8")
    (root / "xmjd6.schema.yaml").write_text(
        "schema:\n"
        "  schema_id: xmjd6\n"
        "  name: 键道6·仰望星空\n"
        "  dependencies:\n"
        "    - xmjd6.cx\n"
        "    - pinyin_simp\n"
        "    - liangfen\n"
        "    - xmjd6.gbk\n",
        "utf-8",
    )
    for name in (
        "xmjd6.cx.schema.yaml",
        "xmjd6.gbk.schema.yaml",
        "pinyin_simp.schema.yaml",
        "liangfen.schema.yaml",
        "english.schema.yaml",
    ):
        (root / name).write_text(f"schema:\n  schema_id: {name.removesuffix('.schema.yaml')}\n", "utf-8")

    (root / "xmjd6.extended.dict.yaml").write_text(
        "---\n"
        "name: xmjd6.extended\n"
        "import_tables:\n"
        "  - xmjd6.danzi\n"
        "  - xmjd6.wxw  # active SSB\n"
        "  # - disabled.table\n"
        "  - xmjd6.zidingyi\n",
        "utf-8",
    )
    dictionaries = {
        "xmjd6.dict.yaml": "---\nname: xmjd6\n...\n",
        "xmjd6.danzi.dict.yaml": "超\twz\n找\tfz\n",
        "xmjd6.wxw.dict.yaml": "超找\twfm\n",
        "xmjd6.zidingyi.dict.yaml": "自定义\tjzvo\n",
        "xmjd6.cx.dict.yaml": "超\tjz\t0 # 〔chāo〕\n",
        "xmjd6.gbk.dict.yaml": "龘\tOabcd\n",
        "pinyin_simp.dict.yaml": "超\tchao\n",
        "liangfen.dict.yaml": "超\tzhao ri\n",
        "english.dict.yaml": "Windows\twindows\n",
    }
    for name, content in dictionaries.items():
        (root / name).write_text(content, "utf-8")

    (root / "lua" / "xmjd6").mkdir(parents=True)
    (root / "lua" / "xmjd6" / "sample.lua").write_text("return {}\n", "utf-8")
    (root / "opencc").mkdir()
    (root / "opencc" / "sample.json").write_text("{}\n", "utf-8")
    (root / "anniversaries.txt").write_text("测试\t2020-01-01\n", "utf-8")
    (root / "candidate_order.txt").write_text("# empty\n", "utf-8")
    (root / "dynamic_phrases.txt").write_text("# empty\n", "utf-8")


class ConversionUnitTests(unittest.TestCase):
    def test_single_character_fly_keys_are_normalized(self) -> None:
        self.assertEqual(
            convert_code("超", "wzvo", DictionaryKind.STANDARD, [Reading("ch", "ao")]),
            "jzvo",
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
            convert_code("超装", "wzfmvo", DictionaryKind.STANDARD, readings),
            "jzqxvo",
        )

    def test_three_character_initial_positions_are_normalized(self) -> None:
        readings = [Reading("ch", "ao"), Reading("zh", "ao"), Reading("g", "uang")]
        self.assertEqual(
            convert_code("超找光", "wfgvio", DictionaryKind.STANDARD, readings),
            "jqgvio",
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
            convert_code("超找光明中", "wfgfvo", DictionaryKind.STANDARD, readings),
            "jqgqvo",
        )

    def test_ssb_only_treats_first_position_as_an_initial(self) -> None:
        readings = [Reading("ch", "ao"), Reading("zh", "ao")]
        self.assertEqual(
            convert_code("超找", "wfm", DictionaryKind.SSB, readings),
            "jfm",
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

    def test_both_legacy_fly_variants_resolve_for_ch_and_zh(self) -> None:
        self.assertEqual(
            choose_reading("qx", [Reading("zh", "uang")]),
            Reading("zh", "uang"),
        )
        self.assertEqual(
            choose_reading("wz", [Reading("ch", "ao")]),
            Reading("ch", "ao"),
        )

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

    def test_override_file_supports_explicit_copy_exceptions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            path = Path(tmp_name) / "overrides.tsv"
            path.write_text(
                "sample.dict.yaml\t免服兵役\twfbyu\tCOPY\n",
                "utf-8",
            )
            self.assertEqual(
                load_overrides(path),
                {("sample.dict.yaml", "免服兵役", "wfbyu"): []},
            )

    def test_override_file_supports_direct_code_exceptions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            path = Path(tmp_name) / "overrides.tsv"
            path.write_text(
                "sample.dict.yaml\tB超\tbjz\tCODE:bwz\n",
                "utf-8",
            )
            self.assertEqual(
                load_overrides(path),
                {("sample.dict.yaml", "B超", "bwz"): "bjz"},
            )


class DictionaryTransformTests(unittest.TestCase):
    def test_dictionary_conversion_preserves_header_bom_and_trailing_fields(self) -> None:
        source_text = (
            "# Rime dictionary\n"
            "---\n"
            "name: sample\n"
            "...\n"
            "超\twzvo\t900 # 高频\n"
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
                source_text.replace("超\twzvo", "超\tjzvo").replace("找\tfz", "找\tqz"),
            )
            self.assertEqual(stats.entries, 2)
            self.assertEqual(stats.converted, 2)
            self.assertEqual(stats.collapsed, 0)

    def test_duplicate_fly_variants_collapse_stably(self) -> None:
        source_text = "超\twz\n抄\tjz\n超\tjz\n找\tfz\n找\tqz\n"
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "sample.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_text(source_text, "utf-8")

            stats = convert_dictionary(source, output, DictionaryKind.STANDARD)

            self.assertEqual(output.read_text("utf-8"), "超\tjz\n抄\tjz\n找\tqz\n")
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
            source.write_text("车\tjx\n", "utf-8")

            with self.assertRaises(UnresolvedEntriesError) as raised:
                convert_dictionary(source, output, DictionaryKind.STANDARD)

            self.assertIn("车", str(raised.exception))
            self.assertFalse(output.exists())

    def test_phrase_heteronyms_are_selected_by_the_original_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "sample.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_text("标识\tbcfk\n", "utf-8")

            convert_dictionary(source, output, DictionaryKind.STANDARD)

            self.assertEqual(output.read_text("utf-8"), "标识\tbcqk\n")

    def test_non_han_separators_do_not_shift_phrase_sound_slots(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "sample.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_text("十有**\tekyduv\n", "utf-8")

            convert_dictionary(source, output, DictionaryKind.STANDARD)

            self.assertEqual(output.read_text("utf-8"), "十有**\tekyduv\n")

    def test_direct_code_override_handles_nonstandard_mixed_text_layout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "sample.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_text("B超\tbwz\nB超\tbjz\n", "utf-8")

            stats = convert_dictionary(
                source,
                output,
                DictionaryKind.STANDARD,
                {
                    ("sample.dict.yaml", "B超", "bwz"): "bjz",
                    ("sample.dict.yaml", "B超", "bjz"): "bjz",
                },
            )

            self.assertEqual(output.read_text("utf-8"), "B超\tbjz\n")
            self.assertEqual(stats.collapsed, 1)

    def test_cx_o_prefix_preserves_the_prefix_and_converts_the_sound_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            source = tmp / "xmjd6.cx.dict.yaml"
            output = tmp / "output.dict.yaml"
            source.write_text("超\tojzviv\t0 # 〔chāo〕\n", "utf-8")

            convert_dictionary(source, output, DictionaryKind.STANDARD)

            self.assertEqual(
                output.read_text("utf-8"),
                "超\tojzviv\t0 # 〔chāo〕\n",
            )


class BundleManifestTests(unittest.TestCase):
    def test_active_imports_ignore_commented_tables_and_inline_comments(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            root = Path(tmp_name)
            make_bundle_fixture(root)
            self.assertEqual(
                active_imports(root / "xmjd6.extended.dict.yaml"),
                ["xmjd6.danzi", "xmjd6.wxw", "xmjd6.zidingyi"],
            )

    def test_bundle_contains_windows_runtime_and_transformed_dictionaries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            root = Path(tmp_name) / "source"
            output = Path(tmp_name) / "xmjd6-nofly"
            root.mkdir()
            make_bundle_fixture(root)

            stats = build_bundle(root, output)

            self.assertEqual(
                (output / "default.yaml").read_bytes(),
                (root / "default_win.yaml").read_bytes(),
            )
            self.assertEqual(
                (output / "default.custom.yaml").read_bytes(),
                (root / "default.custom_win.yaml").read_bytes(),
            )
            for relative in (
                "weasel.custom.yaml",
                "xmjd6.schema.yaml",
                "xmjd6.cx.schema.yaml",
                "xmjd6.gbk.schema.yaml",
                "pinyin_simp.schema.yaml",
                "liangfen.schema.yaml",
                "english.schema.yaml",
                "xmjd6.dict.yaml",
                "xmjd6.extended.dict.yaml",
                "xmjd6.danzi.dict.yaml",
                "xmjd6.wxw.dict.yaml",
                "xmjd6.zidingyi.dict.yaml",
                "lua/xmjd6/sample.lua",
                "opencc/sample.json",
                "symbols.yaml",
                "anniversaries.txt",
                "candidate_order.txt",
                "dynamic_phrases.txt",
                "conversion-report.txt",
            ):
                with self.subTest(relative=relative):
                    self.assertTrue((output / relative).is_file())

            schema = (output / "xmjd6.schema.yaml").read_text("utf-8-sig")
            self.assertIn("schema_id: xmjd6", schema)
            self.assertIn("name: 键道6·无飞键版", schema)
            self.assertNotIn("name: 键道6·仰望星空", schema)
            self.assertEqual(
                (output / "xmjd6.danzi.dict.yaml").read_text("utf-8"),
                "超\tjz\n找\tqz\n",
            )
            self.assertEqual(
                (output / "xmjd6.wxw.dict.yaml").read_text("utf-8"),
                "超找\tjfm\n",
            )
            self.assertEqual(
                (output / "xmjd6.zidingyi.dict.yaml").read_bytes(),
                (root / "xmjd6.zidingyi.dict.yaml").read_bytes(),
            )
            self.assertGreaterEqual(sum(item.converted for item in stats), 3)
            self.assertEqual(validate_bundle(output), [])

    def test_bundle_excludes_build_products_and_source_specific_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            root = Path(tmp_name) / "source"
            output = Path(tmp_name) / "xmjd6-nofly"
            root.mkdir()
            make_bundle_fixture(root)
            (root / "build").mkdir()
            (root / "build" / "xmjd6.table.bin").write_bytes(b"compiled")
            (root / "mac.hskin").write_text("mac only", "utf-8")
            (root / "archive.zip").write_bytes(b"zip")
            (root / "installation.yaml").write_text("installation_id: local\n", "utf-8")
            (root / "user.yaml").write_text("var: local\n", "utf-8")

            build_bundle(root, output)

            paths = [item.relative_to(output).as_posix() for item in output.rglob("*")]
            self.assertFalse(any(path == "build" or path.startswith("build/") for path in paths))
            self.assertFalse(any(path.endswith((".bin", ".hskin", ".zip")) for path in paths))
            self.assertNotIn("installation.yaml", paths)
            self.assertNotIn("user.yaml", paths)
            for path in output.rglob("*"):
                if path.is_file():
                    self.assertNotIn(str(root), path.read_text("utf-8", errors="ignore"))


class WindowsArtifactTests(unittest.TestCase):
    def test_generated_readme_documents_the_standalone_windows_package(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            root = Path(tmp_name) / "source"
            output = Path(tmp_name) / "xmjd6-nofly"
            root.mkdir()
            make_bundle_fixture(root)
            build_bundle(root, output)

            readme = (output / "README.md").read_text("utf-8")
            for phrase in (
                "不会自动安装",
                "schema_id: `xmjd6`",
                "不能与原版同时共存",
                "重新部署",
                "不包含 macOS 编译产物",
                "ch → J",
                "zh → Q",
                "uang → X",
                "超：`jz`",
                "找：`qz`",
                "光：`gx`",
            ):
                with self.subTest(phrase=phrase):
                    self.assertIn(phrase, readme)

    def test_windows_verifier_is_read_only_and_portable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            root = Path(tmp_name) / "source"
            output = Path(tmp_name) / "xmjd6-nofly"
            root.mkdir()
            make_bundle_fixture(root)
            build_bundle(root, output)

            verifier = (output / "verify_windows.cmd").read_text("utf-8")
            self.assertIn("%~dp0", verifier)
            self.assertIn("chcp 65001", verifier.lower())
            self.assertIn("xmjd6.schema.yaml", verifier)
            self.assertIn("xmjd6.extended.dict.yaml", verifier)
            self.assertIn("if exist \"%ROOT%build\\\"", verifier)
            self.assertNotRegex(verifier.lower(), r"\b(copy|xcopy|robocopy|move|del|rm|cp)\b")
            self.assertNotIn("/Users/", verifier)
            self.assertNotIn("/tmp/", verifier)


class CompileCheckTests(unittest.TestCase):
    def test_compile_check_uses_an_isolated_copy_and_requires_main_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_name:
            tmp = Path(tmp_name)
            root = tmp / "source"
            output = tmp / "xmjd6-nofly"
            shared = tmp / "shared"
            root.mkdir()
            shared.mkdir()
            make_bundle_fixture(root)
            build_bundle(root, output)
            before = {path.relative_to(output): path.read_bytes() for path in output.rglob("*") if path.is_file()}

            deployer = tmp / "fake_rime_deployer.py"
            deployer.write_text(
                f"#!{sys.executable}\n"
                "import pathlib, sys\n"
                "staging = pathlib.Path(sys.argv[-1])\n"
                "staging.mkdir(parents=True, exist_ok=True)\n"
                "for name in ('xmjd6.schema.yaml', 'xmjd6.table.bin', "
                "'xmjd6.prism.bin', 'xmjd6.reverse.bin'):\n"
                "    (staging / name).write_bytes(b'compiled')\n",
                "utf-8",
            )
            deployer.chmod(0o755)

            artifacts = compile_bundle(output, deployer=deployer, shared_data=shared)

            self.assertEqual(
                set(artifacts),
                {
                    "xmjd6.schema.yaml",
                    "xmjd6.table.bin",
                    "xmjd6.prism.bin",
                    "xmjd6.reverse.bin",
                },
            )
            after = {path.relative_to(output): path.read_bytes() for path in output.rglob("*") if path.is_file()}
            self.assertEqual(after, before)


if __name__ == "__main__":
    unittest.main()
