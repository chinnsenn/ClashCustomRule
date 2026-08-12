#!/usr/bin/env bash
# [INPUT]: config/subconverter.ini、config/clash-meta.yaml 与 providers payload
# [OUTPUT]: 对外提供规则引用、策略组与 YAML 结构校验
# [POS]: scripts 的离线完整性门卫，被维护者和发布工作流共同调用
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
set -euo pipefail
set +x

python3 - <<'PY'
from pathlib import Path
import re
import sys

try:
    import yaml
except ImportError as error:
    raise SystemExit(f"缺少 PyYAML: {error}")

root = Path.cwd()
ini = (root / "config/subconverter.ini").read_text(encoding="utf-8")
providers = root / "providers"
errors = []

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
    if match and not (providers / match.group(1)).is_file():
        errors.append(f"引用的 provider 不存在: {match.group(1)}")

for path in sorted(providers.glob("*.yaml")):
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as error:
        errors.append(f"provider YAML 无效: {path.name}: {error}")
        continue
    if not isinstance(data, dict) or not isinstance(data.get("payload"), list):
        errors.append(f"provider 缺少 payload 列表: {path.name}")

native = root / "config/clash-meta.yaml"
try:
    data = yaml.safe_load(native.read_text(encoding="utf-8"))
except yaml.YAMLError as error:
    errors.append(f"Clash Meta 模板 YAML 无效: {error}")
else:
    for key in ("proxy-providers", "rule-providers", "proxy-groups", "rules"):
        if not data.get(key):
            errors.append(f"Clash Meta 模板缺少 {key}")
    native_groups = {group.get("name") for group in data.get("proxy-groups", []) if isinstance(group, dict)}
    for rule in data.get("rules", []):
        parts = rule.split(",")
        if len(parts) >= 3 and parts[0] in {"RULE-SET", "GEOIP", "MATCH"} and parts[2] not in native_groups:
            errors.append(f"Clash Meta 规则引用的策略组缺失: {rule}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print(f"校验通过：{len(list(providers.glob('*.yaml')))} 个 provider，{len(groups)} 个 subconverter 策略组")
PY
