# man-lite-debian

Debian 12 slim port of [man-lite](https://github.com/afi3tsfe33gffd/man-lite).

## What's changed

- Base image is `debian:12-slim`; Alpine is not used.
- Xray-core `26.9.30` is installed from the official XTLS release.
- Alpine's `apk` packages were replaced with Debian `apt` packages.
- The existing Nginx template, startup/signal handling, SNI Spoof, Aether, Arman, CottenDNS and Slipnet components are retained.
- Large binary assets are downloaded from the original repository during the Docker build, so they are not duplicated in this repository.

## Required runtime configuration

The image includes a minimal valid `/etc/xray/config.json` so it can start, but it has no inbound listeners. Supply your real Xray configuration at `/etc/xray/config.json` (usually by mounting the directory or configuring the platform's persistent file/volume mechanism).

Optional features expect these files when enabled:

- SNI Spoof: `/etc/xray/pconfig.json`
- Aether WireGuard: `/etc/xray/th.sh`

The image provides an empty default `pconfig.json`. The WireGuard script is intentionally not fabricated; provide your own `th.sh` before enabling that feature.

## Environment variables

| Variable | Default | Purpose |
|---|---:|---|
| `NGINX_PORT` | `3000` | Nginx listen port |
| `ENABLE_USR2_SNI` | `0` | Enable SNI Spoof; send `SIGUSR2` to PID 1 to restart it |
| `ENABLE_HUP_AETHER_PSIPHON` | `0` | Enable Aether Psiphon; send `SIGHUP` to PID 1 to restart it |
| `ENABLE_PWR_AETHER_WG` | `0` | Enable Aether WireGuard; send `SIGPWR` to PID 1 to restart it |

Send `SIGUSR1` to PID 1 to validate and restart Xray after changing `/etc/xray/config.json`.

## Build

```sh
docker build -t man-lite-debian .
docker run --rm -p 3000:3000 -v "$PWD/xray-config:/etc/xray" man-lite-debian
```

The image currently targets Linux AMD64 because the bundled Arman, CottenDNS and Slipnet assets are AMD64 binaries.

## Important

This is a Debian port, not a claim that every optional binary has been runtime-tested on every host. In particular, test CottenDNS/Slipnet and the optional WireGuard script in your target environment before production deployment.
