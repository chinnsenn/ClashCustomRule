#!/usr/bin/env bash
# Verifies a public subconverter is used without Docker and failed sources are tolerated.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
call_log="$workspace/calls.log"
export call_log

curl() {
  local output='' write_out='' url='' config='' endpoint='' previous='' argument status=200
  for argument in "$@"; do
    if [ "$previous" = '--output' ]; then output="$argument"; fi
    if [ "$previous" = '--write-out' ]; then write_out="$argument"; fi
    if [ "$previous" = '--data-urlencode' ] && [[ "$argument" == url=* ]]; then url="${argument#url=}"; fi
    if [ "$previous" = '--data-urlencode' ] && [[ "$argument" == config=* ]]; then config="${argument#config=}"; fi
    if [[ "$argument" == https://converter.example/* ]]; then endpoint="$argument"; fi
    previous="$argument"
  done

  if [[ "$endpoint" == *'/version' ]]; then
    printf '%s\n' 'converter-version' >>"$call_log"
    printf 'subconverter test backend\n' >"$output"
  elif [[ "$endpoint" == *'/sub' ]]; then
    printf '%s\n' "converter-sub:$url" >>"$call_log"
    if [[ "$url" == *'invalid.example'* ]]; then
      status=400
      printf 'The following link does not contain valid nodes: %s\n' "$url" >"$output"
    else
      if [ -n "$config" ] && [[ "$config" != 'https://raw.githubusercontent.com/owner/repo/test/config/subconverter.ini' ]]; then
        status=400
        printf 'unexpected external config: %s\n' "$config" >"$output"
      else
        printf '#%.0s' {1..600} >"$output"
        printf '\nproxies:\n  - name: test\n    type: ss\nproxy-groups:\n  - name: test\nrules:\n  - MATCH,test\n' >>"$output"
      fi
    fi
  elif [[ "$*" == *'api.github.com/gists/'* ]]; then
    if [[ "$*" == *'-X PATCH'* ]]; then
      :
    else
      printf '{"files":{"clash-meta.yaml":{"content":""}}}' >"$output"
    fi
  else
    status=404
    printf 'unexpected URL\n' >"$output"
  fi
  [ -n "$write_out" ] && printf '%s' "$status"
}

export -f curl
log="$workspace/publish.log"
if ! (
  cd "$root"
  SUBSCRIPTION_URLS=$'https://valid.example/sub\nhttps://invalid.example/private-token' \
  SUBCONVERTER_URL=https://converter.example \
  GIST_ID=test GIST_TOKEN=test GITHUB_REPOSITORY=owner/repo GITHUB_SHA=test \
  bash ./scripts/publish-config.sh
) >"$log" 2>&1; then
  printf '%s\n' 'publish unexpectedly rejected a usable subscription set' >&2
  sed -n '1,160p' "$log" >&2
  exit 1
fi

grep -F '订阅 2 转换失败（HTTP 400）' "$log" >/dev/null
grep -F '订阅预检：1/2 个来源可转换' "$log" >/dev/null
grep -F '将跳过 1 个转换失败订阅并发布其余来源' "$log" >/dev/null
grep -F '已更新 Gist 文件：clash-meta.yaml（1/2 个订阅来源可用，已跳过 1 个）' "$log" >/dev/null
diagnostics="$(sed -n '/订阅 2 转换失败/,$p' "$log")"
if grep -E 'https://(valid|invalid)\.example|private-token' <<<"$diagnostics" >/dev/null; then
  printf '%s\n' 'publish diagnostics exposed a subscription URL or token' >&2
  sed -n '1,160p' "$log" >&2
  exit 1
fi
grep -F 'converter-version' "$call_log" >/dev/null
if grep -E 'docker|/base/config/subscriptions' "$call_log" "$log" >/dev/null; then
  printf '%s\n' 'publish unexpectedly depended on a local Docker converter' >&2
  exit 1
fi

: >"$call_log"
failed_log="$workspace/all-conversions-failed.log"
if (
  cd "$root"
  SUBSCRIPTION_URLS='https://invalid.example/private-token' \
  SUBCONVERTER_URL=https://converter.example \
  GIST_ID=test GIST_TOKEN=test GITHUB_REPOSITORY=owner/repo GITHUB_SHA=test \
  bash ./scripts/publish-config.sh
) >"$failed_log" 2>&1; then
  printf '%s\n' 'publish unexpectedly continued without a convertible subscription' >&2
  exit 1
fi

grep -F '没有可转换的订阅，保留现有 Gist，不执行发布' "$failed_log" >/dev/null
if grep -F 'api.github.com/gists' "$call_log" >/dev/null; then
  printf '%s\n' 'publish attempted a Gist update without a convertible subscription' >&2
  exit 1
fi
