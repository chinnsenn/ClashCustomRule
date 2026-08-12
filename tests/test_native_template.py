#!/usr/bin/env python3
"""Regression tests for the directly importable Mihomo template."""

from __future__ import annotations

import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
INI = ROOT / "config" / "subconverter.ini"
TEMPLATE = ROOT / "config" / "clash-meta.yaml"
AUTO_REGION_GROUPS = {
    "🇭🇰 香港节点-自动": ("港", "Hong", "HK"),
    "🇯🇵 日本节点-自动": ("日本", "东京", "JP", "Japan"),
    "🇺🇲 美国节点-自动": ("美国", "united states", "usa"),
    "🇨🇳 台湾节点-自动": ("台", "台湾", "Taiwan"),
    "🇸🇬 新加坡节点-自动": ("新加坡", "Singapore"),
    "🇰🇷 韩国节点-自动": ("Korea", "首尔", "韩"),
}


class NativeTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.template = yaml.safe_load(TEMPLATE.read_text(encoding="utf-8"))
        cls.groups = {group["name"]: group for group in cls.template["proxy-groups"]}

    def test_ibkr_uses_classical_rules(self) -> None:
        self.assertEqual("classical", self.template["rule-providers"]["ibkr"]["behavior"])

    def test_automatic_groups_only_select_subscription_nodes(self) -> None:
        for name, keywords in AUTO_REGION_GROUPS.items():
            with self.subTest(name=name):
                group = self.groups[name]
                self.assertEqual("url-test", group["type"])
                self.assertTrue(group.get("url"))
                self.assertTrue(group.get("interval"))
                self.assertNotIn("DIRECT", group.get("proxies", []))
                self.assertTrue(any(keyword.lower() in group.get("filter", "").lower() for keyword in keywords))

        for name in ("♻️ 自动选择", "🔯 故障转移"):
            with self.subTest(name=name):
                self.assertNotIn("DIRECT", self.groups[name].get("proxies", []))

    def test_covers_every_automatic_publish_target(self) -> None:
        automatic_targets = {
            line.removeprefix("ruleset=").split(",", 1)[0]
            for line in INI.read_text(encoding="utf-8").splitlines()
            if line.startswith("ruleset=")
        }
        native_targets = {
            rule.split(",", 3)[2]
            for rule in self.template["rules"]
            if rule.startswith("RULE-SET,")
        }
        native_targets.update(
            rule.split(",", 2)[1] for rule in self.template["rules"] if rule.startswith("MATCH,")
        )
        self.assertSetEqual(set(), automatic_targets - native_targets)


if __name__ == "__main__":
    unittest.main()
