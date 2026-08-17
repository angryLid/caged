# dsh — DeepSeek Harness for caged

A hardened, disposable container for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`@deepseek-ai/dsh`) — the sibling of the repo's `pi` image. Same hardening
posture (non-root uid 1000, read-only rootfs, no capabilities, no-new-privileges)
and the same "live seed, no rebuild for config" philosophy, but for dsh's
**browser Web UI** (and one-shot headless mode) instead of pi's TUI.

> dsh is a **developer preview** that is iterating rapidly, with
> compatibility-breaking changes expected. The version is pinned in
> `Containerfile` (build-arg `DSH_VERSION`, default `0.1.0-rc.6`) so a release
> bump is explicit.

## What it is / isn't

- **Is**: a containerized dsh — a plugin-based coding-agent harness where the
  agent can read/edit workspace files, run bash, delegate, and plan. The Web UI
  lets you configure models and pick a workspace in the browser.
- **Is NOT**: a network sandbox. dsh needs open networking to reach model
  providers, exactly like caged — see the root [SECURITY.md](../docs/SECURITY.md)
  for that accepted trade-off.

## Layout

```
dsh/
├── Containerfile          # image definition (node24, non-root, pinned dsh)
├── .dockerignore
├── scripts/
│   ├── entrypoint.sh      # fail-fast seed check + tini + default-workspace seed
│   ├── ensure-workspace.mjs # best-effort: register /workspace as Web default
│   ├── build-container.sh # Apple `container` build
│   └── start-container.sh # Apple `container` run: web UI on host loopback
└── seed/.dsh/             # LIVE $DSH_HOME bind source — ships our home-level
                           # cordis.patch.yml; dsh generates profiles/settings/creds
                           # here on first run
```

## Run it

Like caged, dsh is a single disposable container whose only job is isolation,
so there's no orchestration — and Apple's `container` tool (the runtime) has
no compose support anyway. Build and run with the scripts:

```sh
# build (context dsh/, build-arg DSH_VERSION)
dsh/scripts/build-container.sh
# run the web UI; opens on the host loopback
DSH_HOST_PORT=8080 dsh/scripts/start-container.sh
open http://127.0.0.1:3080
```

- **Configure a model**: Settings → Models → paste a DeepSeek API key and save.
  The key is stored in `seed/.dsh/.credentials.yaml` (or, better, pass
  `DEEPSEEK_API_KEY` at launch — dsh gives the environment top, read-only
  precedence, so the key never needs to touch disk in the repo).
- **Pick a workspace**: the entrypoint seeds `/workspace` (the mounted project
  dir) as the default Web workspace on first boot, so the Web UI opens on your
  code without a manual "Choose workspace". If you ever see a stale workspace
  left from an earlier manual run (e.g. an `agent-home` leftover), remove it in
  Settings or delete the runtime state (`seed/.dsh/storages/`+
  `seed/.dsh/sessions/` — gitignored test artifacts).
- **Run a task**: start a session and send a prompt.

### Permission model (danger-full-access by default)

dsh ships its own process sandbox (bwrap / Landlock / seatbelt) and interactive
approval prompts. caged **does not want those**: the container is already the
sandbox (non-root uid 1000, read-only rootfs, no caps), and dsh's own
confinement would likely fail inside a hardened read-only container anyway
(`SANDBOX_UNAVAILABLE`). So this image runs dsh in its official "allow all"
mode via the purpose-built env knob:

```
DSH_PERMISSION_MODE=danger-full-access   # default here
```

Set by `dsh/scripts/start-container.sh`; it makes the base bundle set
`sandbox/mode: danger-full-access` (bash/fs operations run as uid 1000 with no
dsh-level file confinement) and `approval/policy: never` (no interactive
approval prompts). The agent effectively has the full rights of the `pi` user
inside the container. Override (`DSH_PERMISSION_MODE=workspace-write`, etc.) if
you want dsh's own sandbox + approval back.

### One-shot headless (no server, prints the answer and exits)

Run with the `container` tool directly, mirroring `start-container.sh` but
adding `dsh --profile headless "…"` as the command:

```sh
container run --rm \
  --read-only --cap-drop ALL --tmpfs /tmp --memory 2g \
  -v "$PWD:/workspace:rw" \
  -v "$PWD/seed/.dsh:/agent-home/.dsh:rw" \
  -e DSH_HOME=/agent-home/.dsh \
  -e DEEPSEEK_API_KEY="$DEEPSEEK_API_KEY" \
  -e DSH_PERMISSION_MODE=danger-full-access \
  dsh:latest dsh --profile headless "explain this repo and exit"
```

`dsh/scripts/start-container.sh` starts the Web UI. It publishes
`127.0.0.1:${DSH_HOST_PORT} -> 3080` via `container run -p` (host
**loopback**, not the LAN), reaching the webserver (which binds `0.0.0.0:3080`
inside the container via `cordis.patch.yml`). The container port is a stable
3080; only `DSH_HOST_PORT` varies. Hardening is the tool's implementable
subset (same as the pi image): `--read-only`, `--cap-drop ALL`, `--tmpfs
/tmp`, pinned memory — no userns / no `--security-opt`. Env knobs: `DSH_IMAGE`,
`DSH_VERSION`, `DSH_HOME_HOST`, `CAGED_WORKSPACE`, `DSH_MEMORY`.

## Port mapping

dsh web defaults to binding `127.0.0.1:3080` and its CLI **rejects**
`--host 0.0.0.0`. Apple's `container -p` publishes ports to the *container
IP*, not loopback, so a loopback-only bind is unreachable. We keep that CLI
guard but set the webserver **config** to bind `0.0.0.0:3080` inside the
container through the shipped home-level patch
(`seed/.dsh/cordis.patch.yml`) — the *runtime schema* accepts `'0.0.0.0'`, only
the *flag parser* rejects it. Every launch then publishes the HOST side to
loopback only:

```
host browser :${DSH_HOST_PORT}  (host loopback)  --publish-->  container 0.0.0.0:3080 (dsh)
```

| Variable | Default | Meaning |
|---|---|---|
| `DSH_HOST_PORT` | `3080` | the host-loopback port you open in the browser (only this varies) |
| container port | `3080` | fixed; pinned in `seed/.dsh/cordis.patch.yml` and dsh's default |

Override only the host side, e.g. `DSH_HOST_PORT=8080 dsh/scripts/start-container.sh`.
No `--host 0.0.0.0` flag is passed anywhere — the CLI's RCE guard is preserved;
we only set the runtime config to bind inside the container, and the host publish
stays loopback-only.

## Volume mapping

| Volume | Mount | Why |
|---|---|---|
| `${CAGED_WORKSPACE:-$PWD}` | `/workspace:rw` | the code dsh agents work on — **the default Web workspace** |
| `${DSH_HOME_HOST:-./seed/.dsh}` | `/agent-home/.dsh:rw` | LIVE `$DSH_HOME` — persistence + live config |

`$DSH_HOME` (default `~/.dsh`) is dsh's single data root, the analogue of
pi's `~/.pi`: `profiles/<name>/`, `settings.yaml`, `.credentials.yaml`,
`.env`, and session data all live under it. In this repo it's a live bind of
`seed/.dsh`, so:

- dsh auto-initializes its `web`/`headless` profiles on first use. We ship one
  home-level patch (`seed/.dsh/cordis.patch.yml`) that binds the webserver to
  the container network; everything else is generated at first run.
- Config edits land on the **next start**, no image rebuild.
- **Runtime state stays out of git** — `seed/.dsh/.gitignore` ignores the
  generated files; track only config you author.

## Security notes

- Same hardening as caged: `--cap-drop ALL`, non-root, read-only rootfs,
  `/tmp` tmpfs. On Apple's `container` tool the implementable subset applies
  (no userns / no `--security-opt`), matching the pi image — see the root
  docs/APPLE-CONTAINER.md.
- dsh ships its own Landlock sandbox (`native/landlock-run`). It is **not**
  enabled here — the container already is the sandbox; nesting it adds no
  isolation and may fight the read-only rootfs. See docs/SECURITY.md. Combined
  with `DSH_PERMISSION_MODE=danger-full-access`, the agent's bash/fs tools run
  with the full rights of the container's uid-1000 user.
- Pointing a browser at the dsh Web UI gives dsh's agent a bash tool that runs
  as uid 1000 in the container — the workspace bind is its only writable
  surface beyond `$DSH_HOME` and, because permission mode is
  `danger-full-access`/`never`, there are **no approval prompts** to gate it.
  Do not publish the port to a trusted network without thinking about who can
  reach it.

## Known gotchas / untested on this host

- **node-pty must compile on Linux.** dsh's terminal dep `node-pty@1.1.0`
  ships no Linux prebuilds (only darwin/win32), so on Linux its install always
  runs `node-gyp rebuild`. The image therefore installs a C++ toolchain
  (`python3 build-essential`) in the cached base layer. First build is slow;
  subsequent ones are cached.

- First build needs enough memory for npm's dependency resolution (the whole
  `@deepseek-ai/dsh` tree is large). On a memory-constrained builder, raise it
  (e.g. `container build --memory=6g`, or add `--memory` to the build step).
- `--publish` forwards to the container IP on its **first** network; with the
  default network that is where the webserver binds, so the default path works
  as-is. If you attach dsh to a custom network, keep the publish target in mind.