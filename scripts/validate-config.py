#!/usr/bin/env python3
"""Validate the public Clash Meta template and subconverter configuration."""

from __future__ import annotations

import ipaddress
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError as error:
    raise SystemExit(
        f"缺少 PyYAML: {error}。请先运行：python3 -m pip install -r requirements-dev.txt"
    )


ROOT = Path.cwd()
INI_PATH = ROOT / "config" / "subconverter.ini"
LEGACY_INI_PATH = ROOT / "rule_provider_config.yaml"
NATIVE_PATH = ROOT / "config" / "clash-meta.yaml"
PROVIDERS = ROOT / "providers"
AUTO_REGION_GROUPS = {
    "🇭🇰 香港节点-自动": ("港", "Hong", "HK"),
    "🇯🇵 日本节点-自动": ("日本", "东京", "JP", "Japan"),
    "🇺🇲 美国节点-自动": ("美", "United", "USA", "US"),
    "🇨🇳 台湾节点-自动": ("台", "Taiwan", "TW"),
    "🇸🇬 新加坡节点-自动": ("新加坡", "Singapore", "SG"),
    "🇰🇷 韩国节点-自动": ("Korea", "首尔", "韩", "KR"),
}


def load_yaml(path: Path, errors: list[str]):
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as error:
        errors.append(f"YAML 无效: {path.relative_to(ROOT)}: {error}")
        return None


def normalized_ini(path: Path) -> str:
    metadata = ("; [INPUT]:", "; [OUTPUT]:", "; [POS]:")
    return "\n".join(line for line in path.read_text(encoding="utf-8").splitlines() if not line.startswith(metadata))


def inferred_behavior(payload: list[object]) -> str:
    values = [str(value) for value in payload]
    if any("," in value for value in values):
        return "classical"
    try:
        for value in values:
            ipaddress.ip_network(value, strict=False)
    except ValueError:
        return "domain"
    return "ipcidr"


def rule_target(rule: object) -> str | None:
    if not isinstance(rule, str):
        return None
    parts = rule.split(",")
    if parts[0] in {"RULE-SET", "GEOIP"} and len(parts) >= 3:
        return parts[2]
    if parts[0] == "MATCH" and len(parts) >= 2:
        return parts[1]
    return None


def main() -> int:
    errors: list[str] = []
    for path in (INI_PATH, LEGACY_INI_PATH, NATIVE_PATH, PROVIDERS):
        if not path.exists():
            errors.append(f"缺少必需路径: {path.relative_to(ROOT)}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    if normalized_ini(INI_PATH) != normalized_ini(LEGACY_INI_PATH):
        errors.append("rule_provider_config.yaml 与 config/subconverter.ini 不再同构")

    ini = INI_PATH.read_text(encoding="utf-8")
    groups = {
        line.split("=", 1)[1].split("`", 1)[0]
        for line in ini.splitlines()
        if line.startswith("custom_proxy_group=")
    }
    for line in ini.splitlines():
        if not line.startswith("ruleset="):
            continue
        target, source = line.removeprefix("ruleset=").split(",", 1)
        if target not in groups:
            errors.append(f"规则目标组缺失: {target}")
        match = re.search(r"providers/([A-Za-z0-9_]+\.yaml)", source)
        if match and not (PROVIDERS / match.group(1)).is_file():
            errors.append(f"引用的 provider 不存在: {match.group(1)}")

    for path in sorted(PROVIDERS.glob("*.yaml")):
        data = load_yaml(path, errors)
        if not isinstance(data, dict) or not isinstance(data.get("payload"), list):
            errors.append(f"provider 缺少 payload 列表: {path.name}")

    native = load_yaml(NATIVE_PATH, errors)
    if isinstance(native, dict):
        for key in ("proxy-providers", "rule-providers", "proxy-groups", "rules"):
            if not native.get(key):
                errors.append(f"Clash Meta 模板缺少 {key}")

        rule_providers = native.get("rule-providers", {})
        groups_by_name = {
            group.get("name"): group
            for group in native.get("proxy-groups", [])
            if isinstance(group, dict) and group.get("name")
        }
        if len(groups_by_name) != len(native.get("proxy-groups", [])):
            errors.append("Clash Meta 模板存在重复或无名策略组")

        for name, provider in rule_providers.items():
            if not isinstance(provider, dict):
                errors.append(f"rule-provider 配置无效: {name}")
                continue
            behavior = provider.get("behavior")
            if behavior not in {"domain", "ipcidr", "classical"}:
                errors.append(f"rule-provider behavior 无效: {name}")
            local = re.search(r"providers/([A-Za-z0-9_]+\.yaml)", str(provider.get("url", "")))
            if local:
                path = PROVIDERS / local.group(1)
                if path.is_file():
                    data = load_yaml(path, errors)
                    if isinstance(data, dict) and isinstance(data.get("payload"), list):
                        expected = inferred_behavior(data["payload"])
                        if behavior != expected:
                            errors.append(
                                f"rule-provider behavior 不匹配: {name} 应为 {expected}，当前为 {behavior}"
                            )

        native_targets: set[str] = set()
        for rule in native.get("rules", []):
            if isinstance(rule, str) and rule.startswith("RULE-SET,"):
                provider_name = rule.split(",", 3)[1]
                if provider_name not in rule_providers:
                    errors.append(f"Clash Meta 规则引用的 provider 不存在: {provider_name}")
            target = rule_target(rule)
            if target:
                native_targets.add(target)
                if target not in groups_by_name:
                    errors.append(f"Clash Meta 规则引用的策略组缺失: {rule}")

        automatic_targets = {
            line.removeprefix("ruleset=").split(",", 1)[0]
            for line in ini.splitlines()
            if line.startswith("ruleset=")
        }
        missing_targets = automatic_targets - native_targets
        if missing_targets:
            errors.append(f"原生模板缺少自动发布的规则目标组: {', '.join(sorted(missing_targets))}")

        for name, keywords in AUTO_REGION_GROUPS.items():
            group = groups_by_name.get(name)
            if not group:
                errors.append(f"原生模板缺少自动地区组: {name}")
                continue
            if group.get("type") != "url-test":
                errors.append(f"自动地区组必须使用 url-test: {name}")
            if not group.get("url") or not group.get("interval"):
                errors.append(f"自动地区组缺少测速设置: {name}")
            if not any(keyword.lower() in str(group.get("filter", "")).lower() for keyword in keywords):
                errors.append(f"自动地区组缺少地区筛选: {name}")
            if "DIRECT" in group.get("proxies", []):
                errors.append(f"自动地区组不能将 DIRECT 作为测速候选: {name}")

        for name in ("♻️ 自动选择", "🔯 故障转移"):
            group = groups_by_name.get(name)
            if group and "DIRECT" in group.get("proxies", []):
                errors.append(f"自动策略组不能将 DIRECT 作为候选: {name}")

    if errors:
        print("\n".join(dict.fromkeys(errors)), file=sys.stderr)
        return 1
    print(
        f"校验通过：{len(list(PROVIDERS.glob('*.yaml')))} 个 provider，"
        f"{len(groups)} 个 subconverter 策略组，原生模板与自动发布目标组一致"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
