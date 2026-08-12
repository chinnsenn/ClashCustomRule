#!/usr/bin/env bash
# [INPUT]: GitHub Actions Secrets、config/subconverter.ini、Docker 与 GitHub Gist API
# [OUTPUT]: 对外更新指定私有 Gist 的完整 Clash Meta 配置
# [POS]: scripts 的容错发布编排器，跳过失效订阅并保护最后可用的 Gist
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
set -euo pipefail
set +x

: "${SUBSCRIPTION_URLS:?缺少 SUBSCRIPTION_URLS}"
: "${GIST_ID:?缺少 GIST_ID}"
: "${GIST_TOKEN:?缺少 GIST_TOKEN}"
: "${GIST_FILENAME:=clash-meta.yaml}"
: "${SUBCONVERTER_IMAGE:=ghcr.io/metacubex/subconverter:latest}"
: "${GITHUB_REPOSITORY:=chinnsenn/ClashCustomRule}"
: "${GITHUB_SHA:=master}"

workspace="$(mktemp -d)"
container="clash-subconverter-${RANDOM}-${RANDOM}"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true; rm -rf "$workspace"' EXIT

redact() {
  sed -E \
    -e 's#https?://[^[:space:]"'"'"'<>]+#<已隐藏的订阅地址>#g' \
    -e 's#(token|key|secret|password|authorization)=?[^[:space:]&]+#\1=<已隐藏>#Ig'
}

show_converter_diagnostics() {
  local response="$1"
  if [ -s "$response" ]; then
    printf '%s' '转换器响应（已脱敏）：' >&2
    head -c 2048 "$response" | tr '\n' ' ' | redact >&2
    printf '\n' >&2
  fi
  printf '%s\n' '转换器最近日志（已脱敏）：' >&2
  docker logs "$container" 2>&1 | tail -n 30 | redact >&2 || true
}

request_converter() {
  local output="$1"
  shift
  curl --silent --show-error --get \
    --connect-timeout 10 \
    --max-time 180 \
    --output "$output" \
    --write-out '%{http_code}' \
    "$@" \
    http://127.0.0.1:25500/sub || true
}

printf '%s\n' "$SUBSCRIPTION_URLS" | while IFS= read -r url; do
  [ -z "$url" ] || case "$url" in \#*) ;; *) printf '::add-mask::%s\n' "$url" ;; esac
done
printf '::add-mask::%s\n' "$GIST_TOKEN"

mapfile -t subscriptions < <(printf '%s\n' "$SUBSCRIPTION_URLS" | grep -Ev '^\s*(#|$)' || true)
[ "${#subscriptions[@]}" -gt 0 ] || { printf '%s\n' '没有有效订阅地址' >&2; exit 1; }

config="$workspace/subconverter.ini"
sed "s#https://raw.githubusercontent.com/chinnsenn/ClashCustomRule/master/#https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${GITHUB_SHA}/#g; s#https://raw.githubusercontent.com/chinnsenn/ClashCustomRule/refs/heads/master/#https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${GITHUB_SHA}/#g" config/subconverter.ini > "$config"

docker run -d --rm --name "$container" -p 127.0.0.1:25500:25500 -v "$workspace:/base/config:ro" "$SUBCONVERTER_IMAGE" >/dev/null

ready=0
for _ in $(seq 1 30); do
  status="$(curl --silent --show-error --connect-timeout 2 --max-time 5 --output "$workspace/version.txt" --write-out '%{http_code}' http://127.0.0.1:25500/version 2>/dev/null || true)"
  if [ "$status" = 200 ]; then
    ready=1
    break
  fi
  sleep 1
done
[ "$ready" = 1 ] || {
  printf '%s\n' "转换器未能就绪（HTTP ${status:-000}）" >&2
  show_converter_diagnostics "$workspace/version.txt"
  exit 1
}

successful_subscriptions=0
failed_subscriptions=0
valid_subscriptions=()
for index in "${!subscriptions[@]}"; do
  output="$workspace/subscription-$index.yaml"
  status="$(request_converter "$output" \
    --data-urlencode 'target=clash' \
    --data-urlencode "url=${subscriptions[$index]}")"
  if [ "$status" != 200 ] || ! python3 - "$output" <<'PY'
import sys
from pathlib import Path
import yaml
try:
    data = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
except (OSError, yaml.YAMLError):
    raise SystemExit(1)
raise SystemExit(0 if isinstance(data, dict) and data.get("proxies") else 1)
PY
  then
    failed_subscriptions=$((failed_subscriptions + 1))
    printf '%s\n' "订阅 $((index + 1)) 转换失败（HTTP ${status:-000}）" >&2
    show_converter_diagnostics "$output"
  else
    successful_subscriptions=$((successful_subscriptions + 1))
    valid_subscriptions+=("${subscriptions[$index]}")
  fi
done
printf '%s\n' "订阅预检：${successful_subscriptions}/${#subscriptions[@]} 个来源可转换"
[ "$successful_subscriptions" -gt 0 ] || {
  printf '%s\n' '没有可转换的订阅，保留现有 Gist，不执行发布' >&2
  exit 1
}
if [ "$failed_subscriptions" -gt 0 ]; then
  printf '%s\n' "将跳过 ${failed_subscriptions} 个失败订阅并发布其余来源"
fi

output="$workspace/clash-meta.yaml"
joined_urls="$(printf '%s\n' "${valid_subscriptions[@]}" | python3 -c 'import sys; print("|".join(line.strip() for line in sys.stdin if line.strip()))')"
status="$(request_converter "$output" \
  --data-urlencode 'target=clash' \
  --data-urlencode "url=$joined_urls" \
  --data-urlencode 'config=config/subconverter.ini')"
[ "$status" = 200 ] || {
  printf '%s\n' "聚合转换失败（HTTP ${status:-000}）" >&2
  show_converter_diagnostics "$output"
  exit 1
}

python3 - "$workspace/clash-meta.yaml" <<'PY'
import sys
from pathlib import Path
try:
    import yaml
except ImportError as error:
    raise SystemExit(f"缺少 PyYAML: {error}")
content = Path(sys.argv[1]).read_text(encoding="utf-8")
if len(content) < 512 or content.lstrip().lower().startswith(("<html", "<!doctype")):
    raise SystemExit("转换器返回的配置无效")
data = yaml.safe_load(content)
if not isinstance(data, dict):
    raise SystemExit("转换器输出不是 YAML 映射")
for key in ("proxies", "proxy-groups", "rules"):
    if not data.get(key):
        raise SystemExit(f"转换器输出缺少 {key}")
print(f"已验证配置：{len(data['proxies'])} 个节点，{len(data['proxy-groups'])} 个策略组，{len(data['rules'])} 条规则")
PY

current="$workspace/current.json"
status="$(curl --silent --show-error --output "$current" --write-out '%{http_code}' \
  -H "Authorization: Bearer $GIST_TOKEN" \
  -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/gists/$GIST_ID")"
[ "$status" = 200 ] || { printf '%s\n' "读取 Gist 失败（HTTP $status）" >&2; exit 1; }

result=0
python3 - "$current" "$workspace/clash-meta.yaml" "$GIST_FILENAME" "$workspace/request.json" <<'PY' || result=$?
import json, sys
from pathlib import Path
current, config, request = map(Path, (sys.argv[1], sys.argv[2], sys.argv[4]))
name = sys.argv[3]
old = json.loads(current.read_text()).get("files", {}).get(name, {}).get("content", "")
new = config.read_text(encoding="utf-8")
if old == new:
    raise SystemExit(10)
request.write_text(json.dumps({"files": {name: {"content": new}}}, ensure_ascii=False), encoding="utf-8")
PY
if [ "$result" = 10 ]; then
  printf '%s\n' '节点与配置保持一致，跳过 Gist 更新'
  exit 0
fi
[ "$result" = 0 ] || exit "$result"

status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  -X PATCH -H "Authorization: Bearer $GIST_TOKEN" -H 'Accept: application/vnd.github+json' \
  -H 'Content-Type: application/json' --data-binary "@$workspace/request.json" \
  "https://api.github.com/gists/$GIST_ID")"
[ "$status" = 200 ] || { printf '%s\n' "更新 Gist 失败（HTTP $status）" >&2; exit 1; }
printf '%s\n' "已更新 Gist 文件：${GIST_FILENAME}（${successful_subscriptions}/${#subscriptions[@]} 个订阅来源可用，已跳过 ${failed_subscriptions} 个）"
