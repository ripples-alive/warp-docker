#!/usr/bin/env bash

set -e

readonly LOG_TAG="entrypoint"

log() {
  local level="$1"
  shift

  printf '==> [%s] [%s] %s\n' "$LOG_TAG" "$level" "$*"
}

log_info() {
  log "INFO" "$@"
}

log_warn() {
  log "WARN" "$@"
}

log_error() {
  log "ERROR" "$@" >&2
}

trim() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"

  printf '%s' "$value"
}

filter_csv_by_family() {
  local family="$1"
  local csv="$2"
  local result=""
  local item
  local -a items
  local IFS=','

  read -r -a items <<< "$csv"

  for item in "${items[@]}"; do
    item="$(trim "$item")"

    if [ -z "$item" ]; then
      continue
    fi

    if [ "$family" = "ipv4" ] && [ "$item" != "${item#*:}" ]; then
      continue
    fi

    if [ "$family" = "ipv6" ] && [ "$item" = "${item#*:}" ]; then
      continue
    fi

    if [ -n "$result" ]; then
      result="${result}, "
    fi
    result="${result}${item}"
  done

  printf '%s' "$result"
}

set_wg_conf_value() {
  local wg_conf="$1"
  local key="$2"
  local value="$3"

  sed -i "s#^${key} = .*#${key} = ${value}#" "$wg_conf"
}

patch_wg_quick_src_valid_mark() {
  local wg_quick_bin=""
  local sysctl_path="/proc/sys/net/ipv4/conf/all/src_valid_mark"
  local current_value=""

  wg_quick_bin="$(which wg-quick 2>/dev/null || true)"
  if [ -z "$wg_quick_bin" ] || [ ! -f "$wg_quick_bin" ]; then
    log_warn "wg-quick was not found via which; skipping the src_valid_mark compatibility patch."
    return 0
  fi

  if ! grep -q 'net\.ipv4\.conf\.all\.src_valid_mark=1' "$wg_quick_bin"; then
    log_info "wg-quick does not contain the src_valid_mark sysctl step."
    return 0
  fi

  if [ ! -e "$sysctl_path" ]; then
    log_warn "${sysctl_path} is not available; patching wg-quick to skip the src_valid_mark sysctl step."
    sed -i '/net\.ipv4\.conf\.all\.src_valid_mark=1/d' "$wg_quick_bin"
    return 0
  fi

  current_value="$(cat "$sysctl_path")"

  if [ -w "$sysctl_path" ]; then
    log_info "src_valid_mark is writable; keeping the default wg-quick behavior."
    return 0
  fi

  if [ "$current_value" != "1" ]; then
    log_error "src_valid_mark is ${current_value}, but ${sysctl_path} is read-only. Set the container sysctl to 1 before starting."
    return 1
  fi

  log_info "src_valid_mark is already set to 1 and ${sysctl_path} is read-only; patching wg-quick to skip the duplicate sysctl step."
  sed -i '/net\.ipv4\.conf\.all\.src_valid_mark=1/d' "$wg_quick_bin"
}

apply_ip_mode() {
  local wg_conf="$1"
  local mode="$2"
  local family=""
  local mode_label=""
  local allowed_ips=""
  local address_line=""
  local filtered_addresses=""

  case "$mode" in
    -4)
      family="ipv4"
      mode_label="IPv4-only"
      allowed_ips="0.0.0.0/0"
      ;;
    -6)
      family="ipv6"
      mode_label="IPv6-only"
      allowed_ips="::/0"
      ;;
    *)
      return 0
      ;;
  esac

  log_info "Applying ${mode_label} mode."

  address_line="$(grep '^Address = ' "$wg_conf" || true)"
  if [ -z "$address_line" ]; then
    log_error "Unable to find the Address field in ${wg_conf}."
    return 1
  fi

  filtered_addresses="$(filter_csv_by_family "$family" "${address_line#Address = }")"
  if [ -z "$filtered_addresses" ]; then
    log_error "No ${family} address was found in the generated profile."
    return 1
  fi
  set_wg_conf_value "$wg_conf" "Address" "$filtered_addresses"

  set_wg_conf_value "$wg_conf" "AllowedIPs" "$allowed_ips"
  log_info "Updated Address and AllowedIPs for ${mode_label} mode."
}

# Tear down the WireGuard interface before the script exits.
down_wgcf() {
  local exit_code=$?

  printf '\n'
  log_info "Cleaning up the wgcf interface."
  if ! wg-quick down wgcf; then
    log_warn "wgcf did not shut down cleanly."
  fi
  log_info "Cleanup finished."

  exit "$exit_code"
}

# Start the SOCKS proxy and replace the subshell with the proxy process.
run_microsocks() {
  local listen_addr="${BIND_ADDR:-0.0.0.0}"
  local listen_port="${BIND_PORT:-1080}"

  if [ -n "${SOCKS_USER:-}" ] && [ -n "${SOCKS_PASS:-}" ]; then
    log_info "SOCKS authentication is enabled for user: $SOCKS_USER."
    log_info "Starting the SOCKS proxy on ${listen_addr}:${listen_port}."
    exec microsocks -i "$listen_addr" -p "$listen_port" -u "$SOCKS_USER" -P "$SOCKS_PASS"
  else
    if [ -n "${SOCKS_USER:-}" ] || [ -n "${SOCKS_PASS:-}" ]; then
      log_warn "SOCKS credentials are incomplete; starting without authentication."
    else
      log_warn "SOCKS credentials are not set; starting without authentication."
    fi
    log_info "Starting the SOCKS proxy on ${listen_addr}:${listen_port}."
    exec microsocks -i "$listen_addr" -p "$listen_port"
  fi
}

# Run the Disney+ and Netflix probes from check.unlock.media via check.sh
# without modifying the upstream script body more than necessary.
run_unlock_probe() {
  local mode="${1:-}"
  local probe_output=""

  probe_output="$(
    CHECK_SH_SOURCE_ONLY=1
    export CHECK_SH_SOURCE_ONLY

    # shellcheck disable=SC1091
    . /check.sh

    process -E en
    download_extra_data

    case "$mode" in
      -4)
        CURL_DEFAULT_OPTS="-4 ${CURL_OPTS}"
        USE_IPV4=1
        USE_IPV6=0
        ;;
      -6)
        CURL_DEFAULT_OPTS="-6 ${CURL_OPTS}"
        USE_IPV4=0
        USE_IPV6=1
        ;;
      *)
        CURL_DEFAULT_OPTS="${CURL_OPTS}"
        USE_IPV4=1
        USE_IPV6=0
        ;;
    esac

    MediaUnlockTest_DisneyPlus
    MediaUnlockTest_Netflix
  )"

  printf '%s\n' "$probe_output"
}

# Poll the check.unlock.media Disney+ and Netflix probes and recycle wgcf
# when either service becomes unavailable.
monitor_unlock_status() {
  local mode="${1:-}"
  local interval="${UNLOCK_INTERVAL:-300}"
  local probe_output=""

  while true; do
    log_info "Running Disney+ and Netflix unlock checks."
    probe_output="$(run_unlock_probe "$mode")"
    printf '%s\n' "$probe_output"

    if printf '%s\n' "$probe_output" | grep 'Disney+:' | grep -q 'No' || \
      printf '%s\n' "$probe_output" | grep 'Netflix:' | grep -q 'No'; then
      log_warn "Disney+ or Netflix is locked. Restarting wgcf."
      if ! wg-quick down wgcf; then
        log_warn "wgcf did not shut down cleanly before restart."
      fi
      wg-quick up wgcf
      check_connection
      continue
    fi

    log_info "Disney+ and Netflix are available. Sleeping for ${interval} seconds."
    sleep "$interval"
  done
}

# Retry the WireGuard tunnel until outbound connectivity becomes available.
check_connection() {
  local trace_output=""
  local current_ip=""
  local warp_status=""

  log_info "Checking outbound connectivity through wgcf."
  while true; do
    if trace_output="$(curl --silent --show-error --fail --max-time 2 https://cloudflare.com/cdn-cgi/trace)"; then
      current_ip="$(printf '%s\n' "$trace_output" | sed -n 's/^ip=//p' | head -n 1)"
      warp_status="$(printf '%s\n' "$trace_output" | sed -n 's/^warp=//p' | head -n 1)"

      if [ -n "$current_ip" ] && [ -n "$warp_status" ]; then
        log_info "Connectivity check passed. Exit IP: ${current_ip}. WARP status: ${warp_status}."
      elif [ -n "$current_ip" ]; then
        log_info "Connectivity check passed. Exit IP: ${current_ip}."
      else
        log_info "Connectivity check passed."
      fi
      return 0
    fi

    if ! wg-quick down wgcf; then
      log_warn "wgcf did not shut down cleanly during the retry cycle."
    fi
    log_warn "Connectivity check failed; retrying in 2 seconds."
    sleep 2
    log_info "Bringing wgcf back up for another connectivity check."
    wg-quick up wgcf
  done
}

# Accept "-4" or "-6" to disable one address family in the generated config.
run_wgcf() {
  local wg_conf="/etc/wireguard/wgcf.conf"
  local default_gateway_interface
  local default_route_ip
  local mode="${1:-}"

  trap 'down_wgcf' ERR TERM INT

  # Reuse the existing account and profile if they are already present.
  if [ ! -e "wgcf-account.toml" ]; then
    log_info "wgcf account not found; registering a new account."
    wgcf register --accept-tos
  else
    log_info "Reusing the existing wgcf account."
  fi

  if [ ! -e "wgcf-profile.conf" ]; then
    log_info "wgcf profile not found; generating a new profile."
    wgcf generate
  else
    log_info "Reusing the existing wgcf profile."
  fi

  log_info "Writing the WireGuard config to ${wg_conf}."
  cp wgcf-profile.conf "$wg_conf"

  default_gateway_interface="$(route | awk '/^default/ {print $8; exit}')"
  if [ -z "$default_gateway_interface" ]; then
    log_error "Unable to determine the default gateway interface."
    return 1
  fi

  default_route_ip="$(ifconfig "$default_gateway_interface" | awk '/inet / {print $2; exit}' | sed 's/addr://')"
  if [ -z "$default_route_ip" ]; then
    log_error "Unable to determine the IPv4 address for interface: $default_gateway_interface."
    return 1
  fi

  log_info "Detected default gateway interface: $default_gateway_interface."
  log_info "Detected default IPv4 address: $default_route_ip."

  # Keep the original main routing table for traffic sourced from the host IP.
  sed -i "/\[Interface\]/a PostDown = ip rule delete from $default_route_ip lookup main" "$wg_conf"
  sed -i "/\[Interface\]/a PostUp = ip rule add from $default_route_ip lookup main" "$wg_conf"

  apply_ip_mode "$wg_conf" "$mode"

  if grep -q '^DNS = ' "$wg_conf"; then
    log_info "Removing DNS from the WireGuard config to avoid resolvconf inside the container."
    sed -i '/^DNS = /d' "$wg_conf"
  fi

  # Keep the tunnel alive behind NAT even when traffic is idle.
  log_info "Ensuring PersistentKeepalive is set to 15 seconds."
  if ! grep -q "PersistentKeepalive" "$wg_conf"; then
    sed -i '/\[Peer\]/a PersistentKeepalive = 15' "$wg_conf"
  else
    sed -i 's/PersistentKeepalive.*/PersistentKeepalive = 15/g' "$wg_conf"
  fi

  # Allow callers to override the default WireGuard endpoint.
  if [ -n "${ENDPOINT_IP:-}" ]; then
    log_info "Overriding the WireGuard endpoint with: $ENDPOINT_IP."
    sed -i "s/^Endpoint.*/Endpoint = $ENDPOINT_IP/g" "$wg_conf"
  fi

  if [ "$mode" = "-4" ]; then
    log_info "Skipping ip6table_raw because IPv4-only mode is enabled."
  else
    log_info "Loading the ip6table_raw kernel module."
    modprobe ip6table_raw
  fi

  if [ "$mode" != "-6" ]; then
    patch_wg_quick_src_valid_mark
  fi

  log_info "Bringing up the wgcf interface."
  wg-quick up wgcf

  check_connection

  printf '\n'
  log_info "wgcf is up and outbound connectivity is available."

  # Run the unlock check in the background when explicitly enabled.
  if [ -n "${UNLOCK_STREAM:-}" ]; then
    log_info "UNLOCK_STREAM is enabled; starting the check.unlock.media-based unlock monitor in the background."
    monitor_unlock_status "$mode" &
  fi

  # Keep the SOCKS server in the background and wait for managed jobs.
  log_info "Launching the SOCKS proxy."
  run_microsocks &
  wait
}

run_wgcf "$@"
