#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def codes_for(text: str) -> set[str]:
    result: set[str] = set()
    path = ROOT / "xmjd6.danzi.dict.yaml"
    for raw in path.read_text("utf-8-sig").splitlines():
        fields = raw.split("\t")
        if len(fields) >= 2 and fields[0] == text:
            result.add(fields[1].split()[0])
    return result


class NoFlyRootLayoutTests(unittest.TestCase):
    def test_root_is_the_no_fly_runtime(self) -> None:
        schema = (ROOT / "xmjd6.schema.yaml").read_text("utf-8-sig")
        self.assertIn("schema_id: xmjd6", schema)
        self.assertIn("name: 键道6·无飞键版", schema)
        self.assertFalse(ROOT.joinpath("xmjd6-nofly").exists())

    def test_representative_fly_variants_are_normalized(self) -> None:
        normalized = {
            "超": "jz",
            "春": "jwv",
            "找": "qz",
            "中": "qy",
            "装": "qx",
            "光": "gx",
            "穿": "jt",
        }
        legacy = {
            "超": {"wz"},
            "春": {"wwv"},
            "找": {"fz"},
            "中": {"fy"},
            "装": {"fm", "fx"},
            "光": {"gm"},
            "穿": {"wt"},
        }
        for text, expected in normalized.items():
            with self.subTest(text=text):
                self.assertIn(expected, codes_for(text))
                self.assertTrue(codes_for(text).isdisjoint(legacy.get(text, set())))

    def test_native_initial_codes_remain_available(self) -> None:
        for text, code in {"均": "jw", "无": "wj", "求": "qq", "服": "fj"}.items():
            with self.subTest(text=text):
                self.assertIn(code, codes_for(text))

    def test_readme_explains_branch_switching_and_redeployment(self) -> None:
        readme = (ROOT / "README.md").read_text("utf-8")
        self.assertIn("git checkout main", readme)
        self.assertIn("git checkout feature/xmjd6-nofly", readme)
        self.assertIn("重新部署", readme)
        self.assertIn("installation.yaml", readme)
        self.assertIn("user.yaml", readme)


if __name__ == "__main__":
    unittest.main()
