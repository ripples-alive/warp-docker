#!/usr/bin/env bash

set -euo pipefail

resolve_proxy_host() {
  local bind_addr="${HEALTHCHECK_PROXY_HOST:-${BIND_ADDR:-0.0.0.0}}"

  case "$bind_addr" in
    ""|0.0.0.0)
      printf '127.0.0.1'
      ;;
    "::"|"[::]")
      printf '::1'
      ;;
    *)
      printf '%s' "$bind_addr"
      ;;
  esac
}

format_proxy_host() {
  local host="$1"

  case "$host" in
    \[*\])
      printf '%s' "$host"
      ;;
    *:*)
      printf '[%s]' "$host"
      ;;
    *)
      printf '%s' "$host"
      ;;
  esac
}

proxy_host="$(resolve_proxy_host)"
proxy_port="${BIND_PORT:-1080}"
probe_url="${HEALTHCHECK_URL:-https://cloudflare.com/cdn-cgi/trace}"
timeout="${HEALTHCHECK_TIMEOUT:-10}"
formatted_proxy_host="$(format_proxy_host "$proxy_host")"
proxy_url="socks5h://${formatted_proxy_host}:${proxy_port}"

curl_args=(
  --silent
  --show-error
  --fail
  --location
  --connect-timeout "$timeout"
  --max-time "$timeout"
  --proxy "$proxy_url"
)

if [ -n "${SOCKS_USER:-}" ] && [ -n "${SOCKS_PASS:-}" ]; then
  curl_args+=(--proxy-user "${SOCKS_USER}:${SOCKS_PASS}")
fi

trace_output="$(curl "${curl_args[@]}" "$probe_url")"
current_ip="$(printf '%s\n' "$trace_output" | sed -n 's/^ip=//p' | head -n 1)"
warp_status="$(printf '%s\n' "$trace_output" | sed -n 's/^warp=//p' | head -n 1)"

if [ -z "$current_ip" ]; then
  printf 'healthcheck failed: missing exit IP in probe response\n' >&2
  exit 1
fi

if [ -z "$warp_status" ] || [ "$warp_status" = "off" ]; then
  printf 'healthcheck failed: warp is unavailable (status=%s)\n' "${warp_status:-unknown}" >&2
  exit 1
fi
