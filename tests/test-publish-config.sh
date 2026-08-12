#!/usr/bin/env bash
# Verifies tolerant, redacted publishing when one subscription source is invalid.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

docker() {
  case "$1" in
    run|rm) return 0 ;;
    logs) printf "subscription source: https://invalid.example/private-token\n" >&2 ;;
  esac
}

curl() {
  local output='' write_out='' url='' previous='' argument status=200
  for argument in "$@"; do
    if [ "$previous" = '--output' ]; then output="$argument"; fi
    if [ "$previous" = '--write-out' ]; then write_out="$argument"; fi
    if [ "$previous" = '--data-urlencode' ] && [[ "$argument" == url=* ]]; then url="${argument#url=}"; fi
    previous="$argument"
  done

  if [[ "$*" == *'/version'* ]]; then
    printf 'subconverter test backend\n' >"$output"
  elif [[ "$*" == *'api.github.com/gists/'* ]]; then
    if [[ "$*" == *'-X PATCH'* ]]; then
      :
    else
      printf '{"files":{"clash-meta.yaml":{"content":""}}}' >"$output"
    fi
  elif [[ "$url" == *'invalid.example'* ]]; then
    status=400
    printf 'The following link does not contain valid nodes: %s\n' "$url" >"$output"
  else
    printf '#%.0s' {1..600} >"$output"
    printf '\nproxies:\n  - name: test\n    type: ss\nproxy-groups:\n  - name: test\nrules:\n  - MATCH,test\n' >>"$output"
  fi
  [ -n "$write_out" ] && printf '%s' "$status"
}

export -f docker curl
log="$workspace/publish.log"
if ! (
  cd "$root"
  SUBSCRIPTION_URLS=$'https://valid.example/sub\nhttps://invalid.example/private-token' \
  GIST_ID=test GIST_TOKEN=test GITHUB_REPOSITORY=owner/repo GITHUB_SHA=test \
  bash ./scripts/publish-config.sh
) >"$log" 2>&1; then
  printf '%s\n' 'publish unexpectedly rejected a usable subscription set' >&2
  sed -n '1,160p' "$log" >&2
  exit 1
fi

grep -F '订阅预检：1/2 个来源可转换' "$log" >/dev/null
grep -F '订阅 2 转换失败（HTTP 400）' "$log" >/dev/null
grep -F '将跳过 1 个失败订阅并发布其余来源' "$log" >/dev/null
grep -F '已更新 Gist 文件：clash-meta.yaml（1/2 个订阅来源可用，已跳过 1 个）' "$log" >/dev/null
diagnostics="$(sed -n '/订阅 2 转换失败/,$p' "$log")"
if grep -E 'https://(valid|invalid)\.example|private-token' <<<"$diagnostics" >/dev/null; then
  printf '%s\n' 'publish diagnostics exposed a subscription URL or token' >&2
  sed -n '1,160p' "$log" >&2
  exit 1
fi
