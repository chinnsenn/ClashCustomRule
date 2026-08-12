#!/usr/bin/env bash
# [INPUT]: GitHub Actions Secrets、config/subconverter.ini、Docker 与 GitHub Gist API
# [OUTPUT]: 对外更新指定私有 Gist 的完整 Clash Meta 配置
# [POS]: scripts 的发布编排器，转换失败时保护最后可用的 Gist
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

printf '%s\n' "$SUBSCRIPTION_URLS" | while IFS= read -r url; do
  [ -z "$url" ] || case "$url" in \#*) ;; *) printf '::add-mask::%s\n' "$url" ;; esac
done
printf '::add-mask::%s\n' "$GIST_TOKEN"

mapfile -t subscriptions < <(printf '%s\n' "$SUBSCRIPTION_URLS" | grep -Ev '^\s*(#|$)' || true)
[ "${#subscriptions[@]}" -gt 0 ] || { printf '%s\n' '没有有效订阅地址' >&2; exit 1; }

config="$workspace/subconverter.ini"
sed "s#https://raw.githubusercontent.com/chinnsenn/ClashCustomRule/master/#https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${GITHUB_SHA}/#g; s#https://raw.githubusercontent.com/chinnsenn/ClashCustomRule/refs/heads/master/#https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${GITHUB_SHA}/#g" config/subconverter.ini > "$config"

joined_urls="$(printf '%s\n' "${subscriptions[@]}" | python3 -c 'import sys; print("|".join(line.strip() for line in sys.stdin if line.strip()))')"
docker run -d --rm --name "$container" -p 127.0.0.1:25500:25500 -v "$workspace:/base/config:ro" "$SUBCONVERTER_IMAGE" >/dev/null

for _ in $(seq 1 30); do
  curl --fail --silent --show-error http://127.0.0.1:25500/version >/dev/null && break
  sleep 1
done
curl --fail --silent --show-error http://127.0.0.1:25500/version >/dev/null

curl --fail --silent --show-error --get \
  --data-urlencode 'target=clash' \
  --data-urlencode "url=$joined_urls" \
  --data-urlencode 'config=config/subconverter.ini' \
  http://127.0.0.1:25500/sub > "$workspace/clash-meta.yaml"

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
current, config, name, request = map(Path, sys.argv[1:])
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
printf '%s\n' "已更新 Gist 文件：$GIST_FILENAME（${#subscriptions[@]} 个订阅来源）"
