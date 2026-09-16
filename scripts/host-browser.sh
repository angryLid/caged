#!/bin/sh
# Host-side control for caged browser host-attach mode (macOS + Apple container).
# `cg browser start|stop|status` forwards here. Manages two things:
#   * a debug Chrome (--remote-debugging-port=9222, throwaway user-data-dir —
#     Chrome 136+ refuses remote debugging on the default profile)
#   * a TCP bridge 0.0.0.0:9222 -> 127.0.0.1:9222 so the container can reach
#     loopback-bound Chrome via the vmnet gateway (the container connects
#     directly to the gateway IP; Chrome accepts IP-literal Host headers).
# Raw TCP pipe only. Needs only node + curl + lsof, no socat.
set -u

PORT="${CAGED_CDP_PORT:-9222}"
GATEWAY="${CAGED_GATEWAY:-192.168.64.1}"
BRIDGE_JS="/tmp/caged-host-cdp-bridge.js"
BRIDGE_LOG="/tmp/caged-host-cdp-bridge.log"

# Healthy = the endpoint answers real DevTools JSON, not merely a TCP
# listener: a stale forwarder or half-dead socket accepts connections and then
# hangs up (curl exit 52, empty body), which a plain curl success check would
# happily call "up".
cdp_version() { curl -s --max-time 3 "http://127.0.0.1:$PORT/json/version" 2>/dev/null; }
chrome_cdp_up() { cdp_version | grep -q '"Browser"'; }
gateway_version() { curl -s --max-time 3 "http://$GATEWAY:$PORT/json/version" 2>/dev/null; }
bridge_up() { gateway_version | grep -q '"Browser"'; }

port_listeners() { lsof -t -iTCP:"$PORT" -sTCP:LISTEN -n -P 2>/dev/null; }
port_owner_line() { lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2; }

# Free $PORT when a stale caged process squats on it; abort on foreign ones.
# Without this, a leftover forwarder holding the port made `start` a silent
# no-op ("already listening", no Chrome behind it, no window ever appears).
clean_port_or_die() {
  [ -z "$(port_listeners)" ] && return 0
  if pgrep -f "caged-host-cdp-bridge" >/dev/null 2>&1 || pgrep -f "caged-chrome-devtools" >/dev/null 2>&1; then
    echo "Cleaning stale caged processes holding port $PORT:"
    port_owner_line
    pkill -f "caged-host-cdp-bridge" 2>/dev/null || true
    pkill -f "caged-chrome-devtools" 2>/dev/null || true
    i=0
    while [ -n "$(port_listeners)" ] && [ "$i" -lt 10 ]; do sleep 0.5; i=$((i + 1)); done
  fi
  if [ -n "$(port_listeners)" ]; then
    echo "ERROR: port $PORT is held by a process caged did not start - not touching it:" >&2
    port_owner_line >&2
    echo "Close it yourself (or export CAGED_CDP_PORT=<other port>) and re-run: cg browser start" >&2
    exit 1
  fi
}

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
    echo "OK: bridge serves DevTools JSON at $GATEWAY:$PORT (log: $BRIDGE_LOG)"
  else
    echo "ERROR: bridge at $GATEWAY:$PORT did not return DevTools JSON - see $BRIDGE_LOG" >&2
    tail -n 5 "$BRIDGE_LOG" 2>/dev/null >&2
    if [ -n "$(port_listeners)" ]; then echo "Port $PORT listeners:" >&2; port_owner_line >&2; fi
    echo "Host-side check: curl -s http://127.0.0.1:$PORT/json/version | head -3" >&2
    echo "If the host works but the gateway does not, allow node in macOS Firewall (System Settings > Network > Firewall)." >&2
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
    echo "OK: Chrome CDP healthy on 127.0.0.1:$PORT (same proxy config)"
  else
    # A stale forwarder squatting on the port used to make this branch a
    # silent no-op - the port answered TCP but there was no Chrome behind it.
    clean_port_or_die
    echo "Starting Chrome with --remote-debugging-port=$PORT ..."
    # Only the throwaway-profile debug Chrome — never the user's own browser.
    pkill -f "caged-chrome-devtools" 2>/dev/null || true
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
  if [ -n "$(port_listeners)" ]; then
    echo "WARNING: port $PORT is still held by:" >&2
    port_owner_line >&2
    echo "Kill it before the next 'cg browser start', or start will refuse to run." >&2
  fi
}

cmd_status() {
  if chrome_cdp_up; then c="up"
  elif [ -n "$(port_listeners)" ]; then c="occupied (no healthy CDP endpoint)"
  else c="down"
  fi
  if bridge_up; then b="up"
  elif [ -n "$(port_listeners)" ]; then b="listener-only (nothing healthy behind it)"
  else b="down"
  fi
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
