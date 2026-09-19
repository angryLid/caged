# Browser automation in caged — design note

Status: **implemented and sole path**. The script-driven Playwright layer
replaced the former chrome-devtools MCP integration, which has been removed
entirely (mcp.json entry, image install, launcher script). This document
records the design reasoning. Read this before touching `Containerfile*` or
the browser skill.

## Design goals

1. **Self-contained by default.** The default path works with zero host
   setup, survives container restarts trivially, and never depends on a
   process caged doesn't own — matching caged's disposable, fail-fast philosophy.
2. **Script-driven, not tool-call-driven.** pi has bash; the browser is a
   *library* — the model writes a Playwright script and runs it, instead of
   paying per-action MCP round-trips that injected unopt-out-able
   accessibility snapshots and ~26 tool schemas into every session.
3. **Two attach modes, one API.** Headless Chromium inside the container is
   the default; attaching to the host's Chrome over CDP is the escape hatch.
   Both share one programming model, so the skill doc is one document.
4. **No MCP.** The deciding fact: since Chrome 136 remote debugging is
   refused on the default profile, so host attach can never reuse the user's
   real logins — the classic reason for the MCP chain was already gone. What
   remains valuable (host `localhost` dev servers, VPN/intranet) is kept as
   a narrow escape hatch. Dead paths in a hardened image are maintenance
   debt, so nothing dual-support is kept.

## Image layer: `Containerfile.browser`

Part of the pi image chain — both the pi TUI and pi-web-ui build and run on
it; dsh does not inherit the weight. The Command Code image builds its own
copy of the same file on top of `commandcode:latest`:

```
caged-base:latest ──► caged:latest ──► caged-browser:latest ──► caged-webui:latest
   Containerfile.base   Containerfile     Containerfile.browser     Containerfile.webui

caged-base:latest ──► commandcode:latest ──► commandcode-browser:latest
   Containerfile.base   Containerfile.commandcode   Containerfile.browser
```

- The pinned Playwright npm package + full Chromium are baked into the image
  (`--no-shell` skips the redundant headless-shell download): the runtime
  `/tmp` is a noexec tmpfs, so a runtime `playwright install` or npx would fail.
- The Apple `container` runtime runs Chromium unprivileged without user
  namespaces, needing `--no-sandbox` — accepted: the container is disposable
  and the browser only sees what the agent could reach anyway.
- The build is the fail-fast gate: `playwright install` failing fails the build.

## Runtime: `browserd` — one persistent headless Chromium

A seed-side supervisor, started lazily on first browser use (never by the
entrypoint). It starts one headless Chromium on a fixed local CDP port and
keeps it alive across turns, so cookies, localStorage and logins survive
between script runs. It is idempotent and restartable: kill it and the next
run spawns a fresh browser. Scripts connect via Playwright's
`connectOverCDP('http://127.0.0.1:<port>')`.

Browser state is **disposable**: the profile lives under
`/tmp/caged-browser` and dies with the container. Revisit persistence only if
a real need shows up.

## Host attach

Attaches to the host's Chrome over CDP for targets only the host can reach
(localhost dev servers, VPN/intranet):

| | Local (default) | Host attach (`BROWSER_MODE=host`) |
|---|---|---|
| Browser | disposable headless Chromium via `browserd` | the host's Chrome, over CDP |
| State | `/tmp/caged-browser`, dies with the container | host Chrome's throwaway profile |
| Reaches | the internet, `/workspace` | host `localhost` dev servers, VPN/intranet |

The host side is managed by `cg browser` (run on the host; see
`scripts/host-browser.sh`):

- `cg browser start` — launch Chrome with `--remote-debugging-port=9222` and
  a throwaway `--user-data-dir` (mandatory since Chrome 136), then run a
  Node TCP bridge `0.0.0.0:9222 → 127.0.0.1:9222` (no socat needed).
- `cg browser status` — report Chrome CDP and bridge reachability.
- `cg browser stop` — stop bridge and debug Chrome (the user's normal Chrome
  is untouched; only the throwaway-profile instance is killed).

Inside the container, the browser helper and custom scripts connect
**directly** to the host's vmnet gateway IP (`192.168.64.1:9222`):
Chrome's DevTools server rejects non-localhost *hostnames* in the Host
header but accepts IP literals, and it echoes that Host back as the
`webSocketDebuggerUrl`, so HTTP discovery and the WebSocket both go
straight to the gateway — no in-container forwarder needed. When host
CDP is unreachable, the skill says so and falls back to local mode — no
silent confusion.

## Interface: a skill, not an MCP server

`seed/skills-src/browser/SKILL.md` teaches:

- one-shot helpers (`browser open|shot|pdf|eval|cdp`);
- the convention for everything else: **write a Playwright script, run it,
  read its output**. One script = N browser actions = one model turn. The
  model's context holds code and its output, never the browser's whole state.

Attach via `connectOverCDP` to the persistent browser — never
`chromium.launch()` a second one.

## Rejected alternative: raw CDP + a skill document

CDP is a stateful WebSocket session protocol (target discovery, session
attach, event streams, OOPIF auto-attach, binary payloads); a skill document
teaches the syntax but not the state management, so the model would re-learn
the footguns every session. CDP belongs underneath a wrapper — and
Playwright's is the better-maintained one for "make the page do the thing".

## Known losses (accepted)

- Host `localhost` dev servers are unreachable from the container unless they
  bind `0.0.0.0` (the vmnet gateway IP only works then); host attach covers
  the genuinely host-bound cases.
- The pi and commandcode image chains grow by the browser layer's size (part
  of the chains by decision); dsh does not inherit it.
- No chrome-devtools-mcp debugging surface (performance traces, Lighthouse).
  If the need arises, the answer is a Playwright tracing script, not the old
  MCP server.
