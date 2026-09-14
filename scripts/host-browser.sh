#!/bin/sh
# Host-side control for caged browser host-attach mode (macOS + Apple container).
# `cg browser start|stop|status` forwards here. Manages two things:
#   * a debug Chrome (--remote-debugging-port=9222, throwaway user-data-dir —
#     Chrome 136+ refuses remote debugging on the default profile)
#   * a TCP bridge 0.0.0.0:9222 -> 127.0.0.1:9222 so the container can reach
#     loopback-bound Chrome via the vmnet gateway (the container connects
#     directly to the gateway IP; Chrome accepts IP-literal Host headers).
# Raw TCP pipe only. Needs only node + curl, no socat.
set -u

PORT="${CAGED_CDP_PORT:-9222}"
GATEWAY="${CAGED_GATEWAY:-192.168.64.1}"
BRIDGE_JS="/tmp/caged-host-cdp-bridge.js"
BRIDGE_LOG="/tmp/caged-host-cdp-bridge.log"

chrome_cdp_up() { curl -s "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; }
bridge_up() { curl -s "http://$GATEWAY:$PORT/json/version" >/dev/null 2>&1; }

start_bridge() {
  # Health = the bridge PROCESS is alive AND its port answers. Port-reachable
  # alone is not enough: anything else listening on $PORT (or a stale half-open
  # state) would produce a false "already reachable" and silently leave no
  # bridge in place.
  if pgrep -f "node .*caged-host-cdp-bridge\.js" >/dev/null 2>&1 && bridge_up; then
    echo "OK: bridge already reachable at $GATEWAY:$PORT"
    return 0
  fi
  pkill -f "caged-host-cdp-bridge" 2>/dev/null || true
  cat > "$BRIDGE_JS" <<'EOF'
// caged-host-cdp-bridge: pipes 0.0.0.0:9222 -> 127.0.0.1:9222 (Chrome CDP)
const net = require("net");
const PORT = process.env.BRIDGE_PORT || "9222";
const server = net.createServer((client) => {
  const upstream = net.connect(PORT, "127.0.0.1", () => client.pipe(upstream).pipe(client));
  client.on("error", () => upstream.destroy());
  upstream.on("error", () => client.destroy());
});
server.on("error", (err) => { console.error("[caged-host-cdp-bridge] " + err.message); process.exit(1); });
server.listen(PORT, "0.0.0.0", () => console.log("[caged-host-cdp-bridge] listening 0.0.0.0:" + PORT + " -> 127.0.0.1:" + PORT));
EOF
  nohup node "$BRIDGE_JS" >"$BRIDGE_LOG" 2>&1 &
  sleep 1
  if bridge_up; then
    echo "OK: bridge reachable at $GATEWAY:$PORT (log: $BRIDGE_LOG)"
  else
    echo "ERROR: bridge NOT reachable at $GATEWAY:$PORT - see $BRIDGE_LOG" >&2
    echo "If macOS firewall blocked node, allow it in System Settings > Network > Firewall." >&2
    exit 1
  fi
}

cmd_start() {
  # Optional page-traffic proxy (CDP control channel is unaffected):
  #   CAGED_PROXY="socks5://127.0.0.1:1080" cg browser start   # or http://
  #   CAGED_PROXY_BYPASS="<local>;*.internal.example.com"  (optional)
  # Chrome accepts http/https/socks4/socks5/quic schemes — NOT curl's
  # socks5h notation. Chrome sends hostnames to socks5 proxies itself,
  # so proxy-side DNS works with plain socks5://.
  # A change vs. the running instance restarts the debug Chrome.
  proxy_args=""
  [ -n "${CAGED_PROXY:-}" ] && proxy_args="--proxy-server=$CAGED_PROXY"
  [ -n "${CAGED_PROXY_BYPASS:-}" ] && proxy_args="$proxy_args --proxy-bypass-list=$CAGED_PROXY_BYPASS"
  PROXY_STATE="/tmp/caged-host-cdp-proxy"
  prev_proxy="$(cat "$PROXY_STATE" 2>/dev/null || true)"
  if chrome_cdp_up && [ "$prev_proxy" = "$proxy_args" ]; then
    echo "OK: Chrome CDP already listening on 127.0.0.1:$PORT (same proxy config)"
  else
    echo "Restarting Chrome with --remote-debugging-port=$PORT ..."
    pkill -x "Google Chrome" 2>/dev/null || true
    sleep 1
    # shellcheck disable=SC2086 -- proxy_args must split into separate args
    open -na "Google Chrome" --args --remote-debugging-port="$PORT" --remote-allow-origins='*' --user-data-dir="$HOME/.caged-chrome-devtools" --no-first-run $proxy_args
    i=0
    until chrome_cdp_up; do
      i=$((i + 1))
      if [ "$i" -gt 30 ]; then echo "ERROR: Chrome CDP did not come up on 127.0.0.1:$PORT" >&2; exit 1; fi
      sleep 0.5
    done
    printf '%s' "$proxy_args" > "$PROXY_STATE"
    echo "OK: Chrome CDP listening on 127.0.0.1:$PORT"
  fi
  start_bridge
}

cmd_stop() {
  pkill -f "caged-host-cdp-bridge" 2>/dev/null && echo "Stopped bridge." || echo "Bridge was not running."
  # Only the throwaway-profile debug Chrome — your normal Chrome is untouched.
  pkill -f "caged-chrome-devtools" 2>/dev/null && echo "Stopped debug Chrome." || echo "Debug Chrome was not running."
}

cmd_status() {
  chrome_cdp_up && c="up" || c="down"
  bridge_up && b="up" || b="down"
  echo "Chrome CDP (127.0.0.1:$PORT): $c"
  echo "Bridge ($GATEWAY:$PORT): $b"
  if [ "$b" = "up" ]; then
    echo "Host-attach ready. In the container: BROWSER_MODE=host browser open <url>"
    exit 0
  fi
  echo "Host-attach not ready — run: cg browser start"
  exit 1
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  *) echo "Usage: cg browser <start|stop|status>" >&2; exit 2 ;;
esac
