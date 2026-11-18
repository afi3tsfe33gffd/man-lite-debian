#!/bin/sh
set -eu

export NGINX_PORT="${NGINX_PORT:-3000}"

# Environment switches: 1 = enabled, 0/empty/unset = disabled
ENABLE_USR2_SNI="${ENABLE_USR2_SNI:-0}"
ENABLE_HUP_AETHER_PSIPHON="${ENABLE_HUP_AETHER_PSIPHON:-0}"
ENABLE_PWR_AETHER_WG="${ENABLE_PWR_AETHER_WG:-0}"

AETHER_BIN="/usr/local/bin/aether"
AETHER_BIND="127.0.0.1:1820"
AETHER_WG_SCRIPT="/etc/xray/th.sh"

XRAY_PID=""
SNI_PID=""
AETHER_PID=""
AETHER_WG_PID=""
NGINX_PID=""
ARMAN_PID=""

echo "Generating nginx configuration..."
envsubst '${NGINX_PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

XRAY_CONFIG="/usr/bin/config.json"

echo "Checking mounted Xray configuration..."
[ -s /etc/xray/config.json ] || { echo "ERROR: /etc/xray/config.json is missing or empty."; exit 1; }
/usr/bin/xray -test -config /etc/xray/config.json
cp /etc/xray/config.json "$XRAY_CONFIG"
chmod 600 "$XRAY_CONFIG"
echo "Xray config copied to $XRAY_CONFIG"

echo "Testing Nginx configuration..."
nginx -t

start_arman() {
    ARMAN_BIN="/root/x/arman"
    [ -f "$ARMAN_BIN" ] || { echo "ERROR: arman binary not found under /root/x"; return 1; }
    chmod 755 "$ARMAN_BIN"
    ARMAN_DIR="$(dirname "$ARMAN_BIN")"
    echo "Starting arman from $ARMAN_BIN..."
    (cd "$ARMAN_DIR" && exec "$ARMAN_BIN") &
    ARMAN_PID=$!
    echo "arman started with PID $ARMAN_PID"
}
stop_arman() {
    [ -n "${ARMAN_PID:-}" ] || return 0
    kill -TERM "$ARMAN_PID" 2>/dev/null || true
    wait "$ARMAN_PID" 2>/dev/null || true
    ARMAN_PID=""
}
start_xray() {
    /usr/bin/xray -config "$XRAY_CONFIG" &
    XRAY_PID=$!
    echo "Xray started with PID $XRAY_PID"
}
restart_xray() {
    echo "Validating Xray configuration..."
    if ! /usr/bin/xray -test -config /etc/xray/config.json; then
        echo "Invalid Xray config; keeping current process."
        return 1
    fi
    cp /etc/xray/config.json "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"
    echo "Updated Xray config copy at $XRAY_CONFIG"
    echo "Restarting Xray..."
    kill -TERM "$XRAY_PID" 2>/dev/null || true
    wait "$XRAY_PID" 2>/dev/null || true
    start_xray
}
start_sni() {
    /usr/local/bin/sni-spoof-rs /etc/xray/pconfig.json &
    SNI_PID=$!
    echo "SNI started with PID $SNI_PID"
}
restart_sni() {
    [ "$ENABLE_USR2_SNI" = "1" ] || { echo "SNI is disabled."; return 0; }
    echo "Validating SNI configuration..."
    if ! jq -e 'type == "object" and (.listeners | type == "array")' /etc/xray/pconfig.json >/dev/null; then
        echo "Invalid SNI JSON structure; keeping current process."
        return 1
    fi
    echo "Restarting SNI..."
    kill -TERM "$SNI_PID" 2>/dev/null || true
    wait "$SNI_PID" 2>/dev/null || true
    start_sni
}
start_aether() {
    echo "Starting Aether Psiphon..."
    "$AETHER_BIN" --psiphon-only --bind "$AETHER_BIND" &
    AETHER_PID=$!
    echo "Aether Psiphon started with PID $AETHER_PID"
}
find_psiphon_child() {
    ps -o pid,ppid,args 2>/dev/null | awk -v parent="$AETHER_PID" '$2 == parent && /psiphon-tunnel-core/ {print $1; exit}'
}
stop_aether() {
    [ -n "${AETHER_PID:-}" ] || return 0
    echo "Stopping Aether Psiphon..."
    PSIPHON_PID="$(find_psiphon_child || true)"
    [ -z "$PSIPHON_PID" ] || kill -TERM "$PSIPHON_PID" 2>/dev/null || true
    kill -TERM "$AETHER_PID" 2>/dev/null || true
    wait "$AETHER_PID" 2>/dev/null || true
    if [ -n "$PSIPHON_PID" ]; then
        COUNT=0
        while kill -0 "$PSIPHON_PID" 2>/dev/null && [ "$COUNT" -lt 5 ]; do sleep 1; COUNT=$((COUNT + 1)); done
        kill -0 "$PSIPHON_PID" 2>/dev/null && kill -KILL "$PSIPHON_PID" 2>/dev/null || true
    fi
    AETHER_PID=""
    echo "Aether Psiphon stopped."
}
restart_aether() {
    [ "$ENABLE_HUP_AETHER_PSIPHON" = "1" ] || { echo "Aether Psiphon is disabled."; return 0; }
    echo "Restarting Aether Psiphon..."
    stop_aether
    sleep 1
    start_aether
}
start_aether_wg() {
    [ -f "$AETHER_WG_SCRIPT" ] || { echo "ERROR: $AETHER_WG_SCRIPT not found."; return 1; }
    echo "Starting Aether WireGuard from $AETHER_WG_SCRIPT..."
    sh "$AETHER_WG_SCRIPT" &
    AETHER_WG_PID=$!
    echo "Aether WireGuard started with PID $AETHER_WG_PID"
}
stop_aether_wg() {
    [ -n "${AETHER_WG_PID:-}" ] || return 0
    echo "Stopping Aether WireGuard..."
    kill -TERM "$AETHER_WG_PID" 2>/dev/null || true
    wait "$AETHER_WG_PID" 2>/dev/null || true
    AETHER_WG_PID=""
    echo "Aether WireGuard stopped."
}
restart_aether_wg() {
    [ "$ENABLE_PWR_AETHER_WG" = "1" ] || { echo "Aether WireGuard is disabled."; return 0; }
    echo "Restarting Aether WireGuard..."
    stop_aether_wg
    sleep 1
    start_aether_wg
}

echo "Starting Xray..."
start_xray
echo "Starting arman..."
start_arman

if [ "$ENABLE_USR2_SNI" = "1" ]; then
    echo "SNI enabled."
    jq -e 'type == "object" and (.listeners | type == "array")' /etc/xray/pconfig.json >/dev/null
    start_sni
else
    echo "SNI disabled."
fi
if [ "$ENABLE_HUP_AETHER_PSIPHON" = "1" ]; then echo "Aether Psiphon enabled."; start_aether; else echo "Aether Psiphon disabled."; fi
if [ "$ENABLE_PWR_AETHER_WG" = "1" ]; then echo "Aether WireGuard enabled."; start_aether_wg; else echo "Aether WireGuard disabled."; fi

echo "Starting Nginx..."
nginx -g "daemon off;" &
NGINX_PID=$!

cleanup() {
    trap - EXIT TERM INT USR1 USR2 HUP PWR
    echo "Stopping managed services..."
    stop_arman
    stop_aether_wg
    stop_aether
    if [ -n "${XRAY_PID:-}" ]; then kill -TERM "$XRAY_PID" 2>/dev/null || true; wait "$XRAY_PID" 2>/dev/null || true; fi
    if [ -n "${SNI_PID:-}" ]; then kill -TERM "$SNI_PID" 2>/dev/null || true; wait "$SNI_PID" 2>/dev/null || true; fi
    if [ -n "${NGINX_PID:-}" ]; then kill -TERM "$NGINX_PID" 2>/dev/null || true; wait "$NGINX_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'restart_xray || true' USR1
[ "$ENABLE_USR2_SNI" = "1" ] && trap 'restart_sni || true' USR2
[ "$ENABLE_HUP_AETHER_PSIPHON" = "1" ] && trap 'restart_aether || true' HUP
[ "$ENABLE_PWR_AETHER_WG" = "1" ] && trap 'restart_aether_wg || true' PWR

while :; do
    kill -0 "$XRAY_PID" 2>/dev/null || break
    kill -0 "$ARMAN_PID" 2>/dev/null || break
    kill -0 "$NGINX_PID" 2>/dev/null || break
    [ "$ENABLE_USR2_SNI" != "1" ] || kill -0 "$SNI_PID" 2>/dev/null || break
    [ "$ENABLE_HUP_AETHER_PSIPHON" != "1" ] || kill -0 "$AETHER_PID" 2>/dev/null || break
    [ "$ENABLE_PWR_AETHER_WG" != "1" ] || kill -0 "$AETHER_WG_PID" 2>/dev/null || break
    sleep 2 || true
done
echo "A service exited; stopping the container."
exit 1
