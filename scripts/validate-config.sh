#!/usr/bin/env bash
# [INPUT]: config/subconverter.ini、config/clash-meta.yaml 与 providers payload
# [OUTPUT]: 对外提供规则引用、策略组与 YAML 结构校验
# [POS]: scripts 的离线完整性门卫，被维护者和发布工作流共同调用
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
set -euo pipefail
set +x

exec python3 "$(dirname "$0")/validate-config.py"
