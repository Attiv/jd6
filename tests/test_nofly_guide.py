#!/usr/bin/env python3
"""Regression contract for the no-fly user guide and keyboard diagram."""

from __future__ import annotations

import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUIDE = ROOT / "guide" / "无飞键版说明.md"
IMAGE = ROOT / "guide" / "xmjd6-nofly-keyboard.png"


class NoFlyGuideTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guide_text = GUIDE.read_text(encoding="utf-8")

    def test_guide_links_keyboard_image(self) -> None:
        self.assertIn(
            "![键道6无飞键版键盘图](xmjd6-nofly-keyboard.png)",
            self.guide_text,
        )

    def test_keyboard_image_is_wide_png(self) -> None:
        data = IMAGE.read_bytes()
        self.assertGreater(len(data), 50_000)
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(data[12:16], b"IHDR")
        width, height = struct.unpack(">II", data[16:24])
        self.assertGreaterEqual(width, 1_500)
        self.assertGreaterEqual(height, 450)
        self.assertGreater(width / height, 3.0)
        self.assertLess(width / height, 3.4)

    def test_canonical_mappings_and_focus_keys_are_documented(self) -> None:
        required = (
            "ch → J",
            "zh → Q",
            "uang → X",
            "Q：zh",
            "W：ei、un",
            "F：an",
            "J：ch；er、u",
            "X：iang、uang",
            "M：ian",
        )
        for marker in required:
            with self.subTest(marker=marker):
                self.assertIn(marker, self.guide_text)

    def test_converted_and_native_examples_are_documented(self) -> None:
        required = (
            "超 `jz`",
            "春 `jwv`",
            "找 `qz`",
            "中 `qy`",
            "装 `qx`",
            "光 `gx`",
            "均 `jw`",
            "无 `wj`",
            "求 `qq`",
            "服 `fj`",
        )
        for marker in required:
            with self.subTest(marker=marker):
                self.assertIn(marker, self.guide_text)

    def test_conversion_totals_are_documented(self) -> None:
        required = ("1,259,654", "1,251,653", "195,446", "8,001", "未解决条目：0")
        for marker in required:
            with self.subTest(marker=marker):
                self.assertIn(marker, self.guide_text)

    def test_windows_first_branch_and_redeployment_workflow_is_documented(self) -> None:
        windows_index = self.guide_text.index("Windows")
        macos_index = self.guide_text.index("macOS")
        self.assertLess(windows_index, macos_index)
        self.assertIn("git checkout feature/xmjd6-nofly", self.guide_text)
        self.assertIn("重新部署", self.guide_text)
        self.assertIn("键道6·无飞键版", self.guide_text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
