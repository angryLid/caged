#!/bin/bash
# chrome-devtools-mcp launcher with the DevTools TCP forwarder as a
# precondition. Referenced from mcp.json as the server's `command`, so the
# adapter runs this before chrome-devtools-mcp starts.
#
# Why: Chrome's DevTools server rejects non-localhost Host headers (500
# "Host header is specified and is not an IP address or localhost"), so
# host.docker.internal:9222 can never be used directly — even with
# --remote-allow-origins=* (that only relaxes the WebSocket Origin check).
# This wrapper ensures the zero-dep Node pipe (127.0.0.1:19222 ->
# host.docker.internal:9222) is up, then execs the real MCP server pointing
# at localhost, which Chrome accepts.
set -u

# 1) Start the forwarder if nothing is listening on 127.0.0.1:19222 yet.
#    Idempotent: repeated launches are cheap TCP probes, one spawn max.
if [ -f "$HOME/.pi/agent/scripts/devtools-forward.js" ] && ! (exec 3<>/dev/tcp/127.0.0.1/19222) 2>/dev/null; then
  # setsid: detach from this process group so the forwarder outlives the
  # MCP server process (and any pkill targeting chrome-devtools-mcp).
  setsid nohup node "$HOME/.pi/agent/scripts/devtools-forward.js" >/dev/null 2>&1 &
  # give it a moment to bind before the MCP server connects
  sleep 0.3
fi

# 2) exec the actual MCP server (stdio transport inherited from this process)
exec npx -y chrome-devtools-mcp@latest --browser-url=http://127.0.0.1:19222
