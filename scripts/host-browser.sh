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
  if bridge_up; then
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
  if chrome_cdp_up; then
    echo "OK: Chrome CDP already listening on 127.0.0.1:$PORT"
  else
    echo "Restarting Chrome with --remote-debugging-port=$PORT ..."
    pkill -x "Google Chrome" 2>/dev/null || true
    sleep 1
    open -na "Google Chrome" --args --remote-debugging-port="$PORT" --remote-allow-origins='*' --user-data-dir="$HOME/.caged-chrome-devtools" --no-first-run
    i=0
    until chrome_cdp_up; do
      i=$((i + 1))
      if [ "$i" -gt 30 ]; then echo "ERROR: Chrome CDP did not come up on 127.0.0.1:$PORT" >&2; exit 1; fi
      sleep 0.5
    done
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
