# warp-docker

A WARP SOCKS5 container built with `wgcf`, WireGuard, and `microsocks`.

On startup, the container will:

- reuse or register a `wgcf` account
- generate `wgcf-profile.conf` when needed
- build the runtime WireGuard config
- bring up the `wgcf` tunnel
- start a SOCKS5 proxy

Persistent state is stored in `/etc/wgcf`.

## Quick Start

Default dual-stack mode:

```bash
docker run -d \
  --name warp \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  -p 1080:1080 \
  -v /lib/modules:/lib/modules:ro \
  -v "$(pwd)/wgcf:/etc/wgcf" \
  ripples/warp:latest
```

IPv4-only mode:

```bash
docker run -d \
  --name warp \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  -p 1080:1080 \
  -v "$(pwd)/wgcf:/etc/wgcf" \
  ripples/warp:latest -4
```

IPv6-only mode:

```bash
docker run -d \
  --name warp \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  -p 1080:1080 \
  -v /lib/modules:/lib/modules:ro \
  -v "$(pwd)/wgcf:/etc/wgcf" \
  ripples/warp:latest -6
```

## Build

Build and push the multi-arch image:

```bash
./build.sh
```

If your build environment needs an HTTP proxy, `build.sh` will automatically forward `http_proxy`, `https_proxy`, and `no_proxy` to `docker buildx build`.

Example:

```bash
https_proxy=http://127.0.0.1:7890 ./build.sh
```

## Runtime Requirements

- Required: `NET_ADMIN`
- Required: `net.ipv4.conf.all.src_valid_mark=1`
- Required: mount `/etc/wgcf`
- Recommended for dual-stack or `-6`: `SYS_MODULE`
- Recommended for dual-stack or `-6`: `/lib/modules:/lib/modules:ro`

Notes:

- In `-4` mode, the entrypoint skips `modprobe ip6table_raw`
- In dual-stack or `-6` mode, the container may call `modprobe`
- `/lib/modules` only needs a read-only mount

## Startup Modes

- default: dual-stack
- `-4`: IPv4-only
- `-6`: IPv6-only

## Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `BIND_ADDR` | `0.0.0.0` | SOCKS5 listen address |
| `BIND_PORT` | `1080` | SOCKS5 listen port |
| `SOCKS_USER` | empty | SOCKS5 username |
| `SOCKS_PASS` | empty | SOCKS5 password |
| `ENDPOINT_IP` | empty | Override the default WireGuard endpoint |
| `UNLOCK_STREAM` | empty | Run `/check.sh` in the background when non-empty |
| `ENABLE_HEALTHCHECK` | `1` | Run the internal health monitor in the background |
| `HEALTHCHECK_INTERVAL` | `30` | Seconds between internal health checks |
| `HEALTHCHECK_RETRIES` | `3` | Consecutive health check failures before the container exits |
| `HEALTHCHECK_TIMEOUT` | `10` | Per-check curl timeout in seconds |
| `HEALTHCHECK_URL` | `https://cloudflare.com/cdn-cgi/trace` | Probe URL used by `/healthcheck.sh` |
| `HEALTHCHECK_PROXY_HOST` | derived from `BIND_ADDR` | Override the proxy host used by `/healthcheck.sh` |
| `REGION_ID` | `0` | Passed to `/check.sh` |

Authentication is enabled only when both `SOCKS_USER` and `SOCKS_PASS` are set.

## Persistent Files

Files stored in `/etc/wgcf`:

- `wgcf-account.toml`
- `wgcf-profile.conf`

Runtime config:

- `/etc/wireguard/wgcf.conf`

## Entrypoint Behavior

The current entrypoint also handles container-specific compatibility issues:

- removes `DNS = ...` from the generated config
  This avoids `resolvconf` failures inside the container.

- rewrites `Address` and `AllowedIPs` in `-4` and `-6` modes
  This matches the real `wgcf-profile.conf` format, where IPv4 and IPv6 values are usually combined on one line.

- patches `wg-quick` when `src_valid_mark` is already `1` but the sysctl path is read-only
  This avoids duplicate sysctl writes inside the container.

## Health Check And Auto Restart

The image now includes a Docker `HEALTHCHECK` that runs `/healthcheck.sh`.

The probe sends a real request through the local SOCKS5 proxy and verifies that:

- the proxy is reachable
- outbound traffic still works
- Cloudflare reports `warp` is enabled

The entrypoint also runs the same probe in the background. When the probe fails `HEALTHCHECK_RETRIES` times in a row, PID 1 exits non-zero so Docker can restart the container.

To actually restart the container automatically, run it with a restart policy such as:

```bash
--restart unless-stopped
```

If you need to disable the in-container monitor, set:

```bash
-e ENABLE_HEALTHCHECK=0
```

If you disable it and still want Docker to stop probing, also add:

```bash
--no-healthcheck
```

## Troubleshooting

### `resolvconf: could not detect a useable init system`

The entrypoint removes `DNS = ...` from the generated WireGuard config to avoid this.

### `sysctl: error setting key 'net.ipv4.conf.all.src_valid_mark': Read-only file system`

Make sure the container starts with:

```bash
--sysctl net.ipv4.conf.all.src_valid_mark=1
```

If the value is already `1`, the entrypoint patches `wg-quick` to skip the duplicate write.

### `modprobe` fails

Check both:

- `SYS_MODULE`
- `/lib/modules:/lib/modules:ro`

If you always run `-4`, you usually do not need either of them.

### `wgcf-account.toml` or `wgcf-profile.conf` disappears after restart

Persist:

```bash
-v /path/to/wgcf:/etc/wgcf
```

Do not use the old `/wgcf` path.
