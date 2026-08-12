#!/usr/bin/env bash
# Verifies downloaded subscription files are tolerated and converted locally.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
call_log="$workspace/calls.log"
export call_log

docker() {
  case "$1" in
    run) printf '%s\n' 'docker-run' >>"$call_log" ;;
    rm) return 0 ;;
    logs) printf "subscription source: https://invalid.example/private-token\n" >&2 ;;
  esac
}

curl() {
  local output='' write_out='' url='' direct_url='' previous='' argument status=200
  for argument in "$@"; do
    if [ "$previous" = '--output' ]; then output="$argument"; fi
    if [ "$previous" = '--write-out' ]; then write_out="$argument"; fi
    if [ "$previous" = '--data-urlencode' ] && [[ "$argument" == url=* ]]; then url="${argument#url=}"; fi
    if [[ "$argument" == https://*.example/* ]]; then direct_url="$argument"; fi
    previous="$argument"
  done

  if [ -n "$direct_url" ]; then
    if [[ "$direct_url" == *'invalid.example'* ]]; then
      status=502
      printf '%s\n' 'download-invalid' >>"$call_log"
      printf 'curl: (22) The requested URL returned error: 502: %s\n' "$direct_url" >&2
    else
      printf '%s\n' 'download-valid' >>"$call_log"
      printf 'ss://example@valid.example:443#test\n' >"$output"
    fi
  elif [[ "$*" == *'/version'* ]]; then
    printf 'subconverter test backend\n' >"$output"
  elif [[ "$*" == *'api.github.com/gists/'* ]]; then
    if [[ "$*" == *'-X PATCH'* ]]; then
      :
    else
      printf '{"files":{"clash-meta.yaml":{"content":""}}}' >"$output"
    fi
  elif [[ "$url" != '/base/config/subscriptions/0' ]]; then
    status=400
    printf 'converter must receive a downloaded local file, got: %s\n' "$url" >"$output"
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

grep -F '订阅下载：1/2 个来源下载成功' "$log" >/dev/null
grep -F '订阅 2 下载失败（HTTP 502）' "$log" >/dev/null
grep -F '将跳过 1 个下载失败订阅并转换其余来源' "$log" >/dev/null
grep -F '订阅预检：1/1 个已下载来源可转换' "$log" >/dev/null
grep -F '已更新 Gist 文件：clash-meta.yaml（1/2 个订阅来源已下载并转换，已跳过 1 个）' "$log" >/dev/null
diagnostics="$(sed -n '/订阅 2 下载失败/,$p' "$log")"
if grep -E 'https://(valid|invalid)\.example|private-token' <<<"$diagnostics" >/dev/null; then
  printf '%s\n' 'publish diagnostics exposed a subscription URL or token' >&2
  sed -n '1,160p' "$log" >&2
  exit 1
fi

first_docker_line="$(grep -n 'docker-run' "$call_log" | cut -d: -f1)"
first_download_line="$(grep -n 'download-valid' "$call_log" | cut -d: -f1)"
[ "$first_download_line" -lt "$first_docker_line" ] || {
  printf '%s\n' 'subconverter started before a subscription download succeeded' >&2
  exit 1
}

: >"$call_log"
failed_log="$workspace/all-downloads-failed.log"
if (
  cd "$root"
  SUBSCRIPTION_URLS='https://invalid.example/private-token' \
  GIST_ID=test GIST_TOKEN=test GITHUB_REPOSITORY=owner/repo GITHUB_SHA=test \
  bash ./scripts/publish-config.sh
) >"$failed_log" 2>&1; then
  printf '%s\n' 'publish unexpectedly continued without a downloaded subscription' >&2
  exit 1
fi

grep -F '没有成功下载的订阅，保留现有 Gist，不启动转换器' "$failed_log" >/dev/null
if grep -F 'docker-run' "$call_log" >/dev/null; then
  printf '%s\n' 'subconverter started although every subscription download failed' >&2
  exit 1
fi
