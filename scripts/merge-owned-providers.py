#!/usr/bin/env python3
"""Merge adjacent same-target, repo-owned rulesets into single providers.

[INPUT]: rule_provider_config.yaml（人类维护的 ruleset 顺序）与 providers/*.yaml
[OUTPUT]: providers/ 下新增的合并 provider，以及改写后的两份同构 INI
[POS]: 维护者脚本；只在同一策略组连续区块内合并，保持规则相对顺序不变

Why: every ruleset line becomes one HTTP rule-provider on the client. Entries that
share one target group and one behavior can be served as a single file without
changing evaluation order, because nothing of another target sits between them.

Only sources owned by this repository are merged. Upstream sets (blackmatrix7)
are left as separate providers so they keep receiving upstream updates.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

ROOT = Path.cwd()
INI = ROOT / "config" / "subconverter.ini"
LEGACY = ROOT / "rule_provider_config.yaml"
PROVIDERS = ROOT / "providers"
OWN_RE = re.compile(r"chinnsenn/ClashCustomRule/(?:refs/heads/)?master/providers/([A-Za-z0-9_]+\.yaml)")

# 目标组 -> 合并文件 ASCII 名（避免与现有 provider 重名）
SLUGS = {
    ("🎮 游戏平台", "clash-domain"): "GamePlatform_domain",
    ("📺 Bilibili", "clash-domain"): "BilibiliAll_domain",
    ("🎯 全球直连", "clash-domain"): "DirectAll_domain",
    ("🎯 全球直连", "clash-ipcidr"): "DirectAll_ipcidr",
    ("🆎 AdBlock", "clash-domain"): "AdBlock_domain",
    ("🆎 AdBlock", "clash-ipcidr"): "AdBlock_ipcidr",
}
SKIP_DUP = {"DirectAll_ipcidr"}  # 上一轮已生成、且本轮不再需要改写的名字


def parse_ruleset(line: str):
    body = line[len("ruleset="):]
    target, _, rest = body.partition(",")
    source, _, flags = rest.partition(",")
    kind, _, url = source.partition(":")
    return target, kind, url, flags


def main() -> int:
    text = INI.read_text(encoding="utf-8")
    lines = text.splitlines()

    # 切分为连续同目标组区块
    blocks: list[list[int]] = []
    prev_target = None
    for idx, line in enumerate(lines):
        if not line.startswith("ruleset="):
            continue
        target = line[len("ruleset="):].split(",", 1)[0]
        if blocks and target == prev_target:
            blocks[-1].append(idx)
        else:
            blocks.append([idx])
            prev_target = target

    replacements: dict[int, str] = {}
    drops: set[int] = set()
    created: list[str] = []

    for block in blocks:
        target, _, _, _ = parse_ruleset(lines[block[0]])
        buckets: dict[tuple[str, str], list[int]] = {}
        for idx in block:
            _, kind, _, flags = parse_ruleset(lines[idx])
            buckets.setdefault((kind, flags), []).append(idx)

        for (kind, flags), idxs in buckets.items():
            if len(idxs) < 2:
                continue
            sources = []
            for idx in idxs:
                _, _, url, _ = parse_ruleset(lines[idx])
                m = OWN_RE.search(url)
                if not m:
                    sources = []
                    break
                sources.append((idx, m.group(1), url))
            if not sources:
                continue

            slug = SLUGS.get((target, kind))
            if not slug:
                print(f"跳过（无 slug 定义）: {target} {kind} x{len(idxs)}", file=sys.stderr)
                continue

            payload: list[str] = []
            seen: set[str] = set()
            for _, name, _ in sources:
                data = yaml.safe_load((PROVIDERS / name).read_text(encoding="utf-8"))
                for item in data.get("payload") or []:
                    key = str(item)
                    if key not in seen:
                        seen.add(key)
                        payload.append(key)

            out = PROVIDERS / f"{slug}.yaml"
            out.write_text(
                yaml.safe_dump({"payload": payload}, allow_unicode=True, sort_keys=False, default_flow_style=False),
                encoding="utf-8",
            )
            created.append(f"{slug}.yaml ({len(payload)} 条, 合并 {len(sources)} 个源)")

            first, _, first_url = sources[0]
            base = first_url.rsplit("/providers/", 1)[0]
            new_url = f"{base}/providers/{slug}.yaml"
            replacements[first] = f"ruleset={target},{kind}:{new_url}" + (f",{flags}" if flags else "")
            for idx, _, _ in sources[1:]:
                drops.add(idx)

    if not replacements:
        print("没有可合并的区块")
        return 0

    for idx, new_line in replacements.items():
        lines[idx] = new_line
    kept = [ln for i, ln in enumerate(lines) if i not in drops]
    new_text = "\n".join(kept) + "\n"

    INI.write_text(new_text, encoding="utf-8")
    legacy = LEGACY.read_text(encoding="utf-8").splitlines()
    legacy_body = [ln for ln in legacy if not ln.startswith(("; [INPUT]:", "; [OUTPUT]:", "; [POS]:"))]
    new_body = [ln for ln in new_text.splitlines() if not ln.startswith(("; [INPUT]:", "; [OUTPUT]:", "; [POS]:"))]
    legacy_header = [ln for ln in legacy if ln.startswith(("; [INPUT]:", "; [OUTPUT]:", "; [POS]:"))]
    LEGACY.write_text("\n".join(legacy_header + new_body) + "\n", encoding="utf-8")

    print(f"合并 {len(created)} 个 provider：")
    for c in created:
        print("  -", c)
    print(f"ruleset 行: {len(lines)} -> {len(kept)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
