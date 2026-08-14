#!/bin/bash
# chrome-devtools-mcp launcher with the DevTools TCP forwarder as a
# precondition. Referenced from mcp.json as the server's `command`, so the
# adapter runs this before chrome-devtools-mcp starts.
#
# Why: Chrome's DevTools server rejects Host headers that aren't localhost
# or an IP literal (500 "Host header is specified and is not an IP address
# or localhost"), and --remote-allow-origins=* only relaxes the WebSocket
# Origin check. This wrapper pins the CDP endpoint to a localhost URL
# (127.0.0.1:19222 -> 192.168.64.1:9222, the host CDP via the vmnet
# gateway), which Chrome always accepts, and keeps the MCP server stable
# regardless of how the host is addressed.
set -u

# 0) Diagnostic hint: if host Chrome's CDP is not up, print a ready-to-run
#    command so the user can start it themselves. Never fatal — the MCP
#    server still starts and will simply be unavailable, same as before.
CDP_HOST="${CDP_HOST:-192.168.64.1}"
CDP_REMOTE_PORT="${CDP_REMOTE_PORT:-9222}"
if ! curl -fsS -m 2 "http://${CDP_HOST}:${CDP_REMOTE_PORT}/json/version" >/dev/null 2>&1; then
  cat >&2 <<EOF
caged: host Chrome CDP not reachable at ${CDP_HOST}:${CDP_REMOTE_PORT} — chrome-devtools MCP will be unavailable.
Start a debug Chrome on your laptop (host), then reconnect:
  macOS:  open -na "Google Chrome" --args --remote-debugging-port=${CDP_REMOTE_PORT} '--remote-allow-origins=*' --user-data-dir="\$HOME/.caged-chrome-devtools" --no-first-run
          # Chrome binds loopback only — bridge to the vmnet gateway:
          # socat TCP-LISTEN:192.168.64.1:${CDP_REMOTE_PORT},fork TCP:127.0.0.1:${CDP_REMOTE_PORT} &
  Linux:  google-chrome --remote-debugging-port=${CDP_REMOTE_PORT} '--remote-allow-origins=*' --user-data-dir="\$HOME/.caged-chrome-devtools" --no-first-run &
EOF
fi

# 1) Start the forwarder if nothing is listening on 127.0.0.1:19222 yet.
#    Idempotent: repeated launches are cheap TCP probes, one spawn max.
if [ -f "$HOME/.pi/agent/scripts/devtools-forward.js" ] && ! (exec 3<>/dev/tcp/127.0.0.1/19222) 2>/dev/null; then
  # setsid: detach from this process group so the forwarder outlives the
  # MCP server process (and any pkill targeting chrome-devtools-mcp).
  setsid nohup node "$HOME/.pi/agent/scripts/devtools-forward.js" >/dev/null 2>&1 &
  # give it a moment to bind before the MCP server connects
  sleep 0.3
fi

# 2) exec the actual MCP server (stdio transport inherited from this process).
#    Runs from the global install baked into the image at build time — npx
#    would download to /tmp/.npm, which is a noexec tmpfs (Permission denied).
exec chrome-devtools-mcp --browser-url=http://127.0.0.1:19222
