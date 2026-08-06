#!/usr/bin/env node
/**
 * DevTools TCP forwarder — makes host Chrome's CDP port reachable from the
 * sandbox on a localhost port.
 *
 * WHY this exists:
 *   Chrome's DevTools HTTP server (--remote-debugging-port) rejects any
 *   request whose Host header is not `localhost` / `127.0.0.1` / an IP
 *   literal: "Host header is specified and is not an IP address or localhost."
 *   Connecting via host.docker.internal:9222 therefore fails with a 500 even
 *   though --remote-allow-origins=* is set (that flag only relaxes the
 *   WebSocket Origin/CORS check, NOT the Host header check).
 *
 * HOW it works:
 *   Clients in the sandbox connect to 127.0.0.1:19222 with Host:
 *   localhost:19222 (which Chrome accepts); this server pipes the raw TCP
 *   bytes to host.docker.internal:9222, so Chrome only ever sees a
 *   localhost Host header.
 *
 * Requires only Node's built-in `net` — no socat, no dependencies.
 */
const net = require("net");

const HOST = process.env.CDP_HOST || "host.docker.internal";
const REMOTE_PORT = parseInt(process.env.CDP_REMOTE_PORT || "9222", 10);
const LOCAL_PORT = parseInt(process.env.CDP_LOCAL_PORT || "19222", 10);

const server = net.createServer((client) => {
  const upstream = net.connect(REMOTE_PORT, HOST, () => {
    client.pipe(upstream).pipe(client);
  });
  client.on("error", () => upstream.destroy());
  upstream.on("error", () => client.destroy());
});

server.on("error", (err) => {
  console.error(`[devtools-forward] ${err.message}`);
  process.exit(1);
});

server.listen(LOCAL_PORT, "127.0.0.1", () => {
  console.error(
    `[devtools-forward] listening 127.0.0.1:${LOCAL_PORT} -> ${HOST}:${REMOTE_PORT}`,
  );
});
