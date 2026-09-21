# caged repo — agent guide

You are working on the **caged** source repo: a hardened, disposable container that runs AI coding agents as a non-root user (uid 1000) on a read-only rootfs with no capabilities — so an agent that executes arbitrary bash can only ever touch the workspace handed to it. `pi` is the default agent; `dsh` (DeepSeek Harness) and `cmdc` (Command Code) are siblings built on the same base image and the same hardening. Your job here is to improve the repo: the images, the run scripts, the seed config, the docs.

caged is **not** a network sandbox: open egress is deliberate, because agents must reach model providers. Threat model and the accepted risks live in `docs/SECURITY.md`.

## Layout

```
caged/
├── cg                          # unified launcher: cg <agent> <build|start>, cg browser start|stop|status
├── Containerfile.base          # shared base: apt essentials (python3/pip/uv), node + pnpm/yarn,
│                               #   pinned glab/gh/jira/cfl, non-root user, baked sync scripts
├── Containerfile               # pi image — thin layer on the base
├── Containerfile.browser       # additive layer, parameterised FROM (ARG CAGED_IMAGE): Playwright + Chromium
├── Containerfile.webui         # additive layer on the browser layer: node-pty toolchain + pi-web-ui
├── Containerfile.dsh           # dsh image — thin layer on the base
├── Containerfile.commandcode   # Command Code image — thin layer on the base
├── seed/                       # the LIVE agent home, bind-mounted at /agent-home (see below)
│   ├── .pi/agent/              # pi's ~/.pi: models.json, settings.json, AGENTS.md (generated), skills/ (generated)
│   ├── .dsh/                   # dsh's $DSH_HOME: cordis.patch.yml + generated profiles/settings
│   ├── .commandcode/           # Command Code HOME state: settings.json (tracked; bypass mode)
│   ├── .config/                # XDG_CONFIG_HOME — non-secret CLI config, gitignored
│   ├── skills-src/             # git-tracked local skills (source of truth)
│   ├── skills-sync/vendor/     # gitignored host clones of the external skill repos
│   ├── prompt-src/global.md    # the global prompt every agent gets (source of truth)
│   ├── skills.json             # declarative skills config (all agents)
│   └── prompts.json            # global-prompt install targets
├── scripts/                    # build-container.sh, start-container.sh, build-caged-base.sh,
│                               #   entrypoint.sh + dsh-/commandcode-entrypoint.sh, skills-sync.mjs,
│                               #   prompt-sync.mjs, host-browser.sh, package-cf.sh
├── packages/cf/                # the Confluence reader CLI packed into the base image
└── docs/                       # SECURITY.md, CLI-AUTH.md, BROWSER.md, APPLE-CONTAINER.md, AGENT-INTEGRATION.md
```

## Build and run

The user runs these **on the host** (Apple silicon, Apple's `container` tool; Node.js on the host is required because the build clones the git skill sources into the seed). There is no `container` binary inside the container, so an agent can edit files and run the sync scripts, but never build or start an image itself — when a change needs a build, hand the command to the user and say so.

```sh
cg pi build                  # base -> pi -> browser chain; PI_VERSION=x.y.z to pin
cg pi start                  # pi TUI on the browser layer, from the repo you want as /workspace
cg pi start -b               # rebuild the image first, then start
cg dsh build && cg dsh start # dsh Web UI on http://127.0.0.1:3080
cg webui start               # pi-web-ui on http://127.0.0.1:8787 (build: cg webui build)
cg cmdc start                # Command Code CLI
cg browser start|stop|status # host Chrome + CDP bridge for the browser host-attach mode
```

`cg` mounts the directory you run it from as `/workspace`; the remaining `start` arguments replace the image's default command. `browser` is build-only on the image side. Everything forwards to `scripts/build-container.sh` and `scripts/start-container.sh`, where the defaults and per-image knobs are defined — read those two scripts rather than trusting a copied table.

## Image chains — where a change belongs

```
caged-base:latest ──► caged:latest ──────────► caged-browser:latest ──► caged-webui:latest
caged-base:latest ──► commandcode:latest ────► commandcode-browser:latest
```

- **`Containerfile.base`** holds everything shared: apt packages, the node toolchain, the pinned `glab`/`gh`/`jira`/`cfl` CLIs, the non-root user, the sync scripts. A CLI, package-manager or pin change belongs here, never in an agent layer.
- **Agent layers** (`Containerfile`, `Containerfile.dsh`, `Containerfile.commandcode`) stay thin: only the agent install.
- **`Containerfile.browser`** is additive with a parameterised `FROM` (`ARG CAGED_IMAGE`), so the same file serves the pi chain and the cmdc chain. Chromium is baked in because the runtime `/tmp` is a noexec tmpfs. Keep it off the base — dsh would inherit the bloat.
- **`Containerfile.webui`** is additive on the browser layer, for the same reason.
- Build steps skip individually with `CAGED_SKIP_BASE=1`, `CAGED_SKIP_PI=1`, `CAGED_SKIP_BROWSER=1` (useful after touching only the top layer, e.g. `Containerfile.webui`).

## The seed is the live config

`seed/` is bind-mounted **both ways** at `/agent-home` (`$HOME`) for every agent mode, so there is no baked-in config and no seeding step: whatever you write in `seed/` takes effect on the *next* container start, with no image rebuild. That makes the seed the source of truth — and it makes the generated artifacts in it traps:

| Edit this (tracked) | Never edit this (generated, gitignored) |
|---|---|
| `seed/skills.json` (declarations), `seed/skills-src/` (your own skills) | `seed/.pi/agent/skills/`, `seed/.dsh/skills/`, `seed/.commandcode/skills/` |
| `seed/prompt-src/global.md`, `seed/prompts.json` | `seed/.pi/agent/AGENTS.md`, `seed/.commandcode/AGENTS.md` |
| `seed/.pi/agent/models.json`, `seed/.pi/agent/settings.json` | — (live config, edit directly; effective next start) |
| `seed/.dsh/cordis.patch.yml` | `seed/.dsh/settings.yaml`, `profiles/`, `storages/`, `.credentials.yaml` |

- **skills-sync** copies each enabled skill from the vendored git repos and `skills-src/` into every target dir listed in `seed/skills.json`'s `linkTargets`, marking its copies with `.caged-skill-managed`. Managed copies are refreshed and stale ones removed, so dropping a skill from `enabled` uninstalls it; unmanaged skills are never clobbered.
- **prompt-sync** copies `seed/prompt-src/global.md` verbatim into each target in `seed/prompts.json` (pi and cmdc), marked with `.caged-prompt-managed.<agent>` — the global prompt is byte-identical across agents, so fix wording once in `global.md`.
- Git sources are cloned **on the host at build time** into `seed/skills-sync/vendor/` (`CAGED_SKIP_SKILLS_SYNC=1` reuses an existing vendor dir). At container start each entrypoint only runs `--link-only --target <agent>`, so start needs no network and no git.
- Iterate by hand with `node scripts/skills-sync.mjs [--dry-run|--link-only|--clone-only]` and `node scripts/prompt-sync.mjs [--dry-run|--target <agent>]`. Both are safe to re-run.

## Mounts and runtime state

| Path in container | Backing | Mode | Notes |
|---|---|---|---|
| `/workspace` | the dir `cg <agent> start` ran from (`CAGED_WORKSPACE`) | rw | the code the agent works on |
| `/agent-home` (`$HOME`) | `seed/` (`CAGED_AGENT_HOME`) | rw | shared live home: `.pi`, `.dsh`, `.commandcode`, `.config` |

Everything else in `$HOME` stays on the read-only rootfs; home-derived caches are pointed at the `/tmp` tmpfs (`npm_config_cache`, `XDG_CACHE_HOME`), so the only writable host-backed surfaces are those two mounts.

- **Sessions live per-project on the host, not in the seed.** `scripts/entrypoint.sh` moves `seed/.pi/agent/sessions` into `/workspace/.pi/sessions` and leaves a symlink behind, because the pi SDK ignores both the `settings.json` `sessionDir` key and `PI_CODING_AGENT_SESSION_DIR` when writing — relocating the directory is the only way the TUI and the Web UI share one history. dsh mirrors this at `/workspace/.dsh/sessions` via `cordis.patch.yml`.
- **Runtime state stays out of git.** `.gitignore` is the authority — it covers `auth.json`, the session symlink target, generated skills/prompt copies, `seed/.config/`, the dsh generated files, and the legacy `seed/cli-auth/`. Known gap: `seed/.pi/agent/provider-keys.json` (pi runtime state, currently `{}`) is **not** ignored yet, so check `git status` before a blanket `git add -A`.
- Workspaces should gitignore the per-project runtime dirs caged creates in them: `.pi/sessions/`, `.pi-web/`, `.dsh/sessions/`, `.commandcode/`.

## Leading invariants (the load-bearing rules)

- **Non-root, no escalation.** uid 1000, `--cap-drop ALL`, read-only rootfs, `/tmp` tmpfs. Apple's `container` tool cannot express `--security-opt=no-new-privileges` or `--userns=keep-id`, and its `--tmpfs` takes a path only (no `noexec,nosuid,size`) — podman/docker can express all of it. That divergence and its consequences are recorded in `docs/APPLE-CONTAINER.md`. Never add a `sudo` path or a privilege loophole — it dissolves the whole point.
- **Open network is deliberate.** Not a sandbox to add; document trade-offs in `docs/SECURITY.md` instead of trying to lock egress.
- **Fail-fast seed validation.** `scripts/entrypoint.sh` validates the seed mount (missing/incomplete seed, malformed `skills.json`, read-only seed) and exits non-zero with a diagnostic instead of letting the agent run half-configured. Preserve that property when you touch an entrypoint.
- **Agent permission mode is "allow all" by design.** The container *is* the sandbox, so dsh runs with `DSH_PERMISSION_MODE=danger-full-access` and no approval prompts — its own Landlock/bwrap confinement would add nothing and can fight the read-only rootfs. Same reasoning keeps the browser path skill-driven rather than MCP-driven (`docs/BROWSER.md`).

## Secrets never live in the repo

Provider keys (`MY_DEEPSEEK_API_KEY`, `VOLCENGINE_API_KEY`, `MY_OPENROUTER_API_KEY`, `LOCAL_API_KEY`, `COMMANDCODE_API_KEY`) and the CLI tokens (`GITLAB_TOKEN`, `GH_TOKEN`, `JIRA_API_TOKEN`, `CFL_API_TOKEN`) are passed as container env vars by the operator: `models.json` and `seed/.dsh/settings.yaml` reference them **by name**, never by value. All four CLIs are token-only — no `auth login`, nothing secret at rest (their non-secret config lands in the gitignored `seed/.config/`).

Never write a real key into the repo — anything there is readable by the agent you are caging. If a key is missing, tell the user which env var to set; don't fabricate one. Auth behavior, the `ATLASSIAN_*` → `CFL_*`/`JIRA_*` mapping and the pitfalls: `docs/CLI-AUTH.md`.

## Version pins

Each base-image CLI is pinned in `Containerfile.base` and sha256-verified per architecture against the release's own checksums, following one pattern: a versioned download URL, a `case "${TARGETARCH}"` with the amd64/arm64 hashes, then `sha256sum -c`. Bumping one is a two-file edit:

1. `Containerfile.base` — the `ARG <NAME>_VERSION` default **and** both hashes in the `case`.
2. `scripts/build-caged-base.sh` — its two default references (the log line and the `--build-arg`).

Agent versions (`PI_VERSION`, `PI_WEB_UI_VERSION`, `DSH_VERSION`, `COMMAND_CODE_VERSION`) default to `latest`, which `build-container.sh` resolves against the npm registry before passing the build-arg: a literal `latest` would freeze the install layer in the build cache forever, so the resolved version is what invalidates it when a release actually lands.

## Gotchas worth knowing before you touch anything

- **Apple `container` is not docker.** No orchestration (deliberate — the container's only job is isolation, so there is no compose file and shouldn't be one); host names don't resolve from inside, use the vmnet gateway `192.168.64.1`; `.dockerignore` deep-negation is not honored; no `--security-opt`/`--userns`. Details: `docs/APPLE-CONTAINER.md`.
- **Ctrl+C needs a TTY.** Without `-it`, Apple `container`'s non-TTY signal path is broken upstream and Ctrl+C never reaches the guest — that is why `cg dsh start` passes `-it` even though dsh is a web server.
- **node-pty compiles on Linux.** dsh's terminal dependency ships no Linux prebuilds, so the shared base carries the C++ toolchain (`python3`, `build-essential`) for dsh and webui. First build is slow; the cached base layer makes later ones cheap.
- **Missing provider keys fail late.** Every key defaults to empty, so a missing one surfaces only when that model is used — a delayed, hard-to-trace failure rather than a start-time check.
- **Memory needs pinning.** The Apple `container` guest defaults to 1 GB, which OOMs pi on larger tasks, so `cg pi start` pins `--memory 2g` (`CAGED_MEMORY`) and web mode 4 GB (`PI_WEBUI_MEMORY`). The builder gets 2 CPUs / 2 GB, which npm dependency resolution for the larger agent trees can exceed — raise it on the build (e.g. `container build --memory=6g`).
- **Skill basename collisions are warned about, not resolved.** Two vendor repos shipping the same skill name both get installed; which one an agent loads depends on target-dir order.
- **One container per seed.** The seed mount is rw everywhere, so running the TUI and the Web UI against the same `seed/.pi` at once is unsupported.
- **Web-mode updates are rebuilds.** The rootfs is read-only, so pi-web-ui's self-update and `server install` paths don't apply; rebuild the image (`PI_WEB_UI_VERSION` pins it). Its bundled pi SDK copy can lag the global pi — config format is compatible, they don't interfere; see `docs/SECURITY.md` for the web-mode posture.
- **dsh specifics.** It lives flat at the repo root — keep it there, don't re-nest it under `dsh/`. The web server binds `0.0.0.0:3080` *inside* the container via the shipped `seed/.dsh/cordis.patch.yml` (the runtime schema accepts it, only the CLI flag parser rejects it), while the host side is published to loopback only; the same patch keeps session JSONL at `/workspace/.dsh/sessions`. Adding a new agent image has its own SOP: `docs/AGENT-INTEGRATION.md`.
- **pi startup latency is container I/O**, not a bug: loading its two extensions costs ~1.3s before the TUI appears, and neither baking them in nor pre-priming caches changed it. The `/workspace` bind on macOS is also slower than native for small-file I/O (`npm install` in the workspace).

## Verifying a change

Pick the check that matches what you touched, and state the completion criterion rather than "looks right":

- **Seed config, skills or prompt:** `node scripts/skills-sync.mjs --dry-run` and/or `node scripts/prompt-sync.mjs --dry-run` — every declared source and target accounted for, no unmanaged file scheduled for clobbering. No build needed; the change is live on the next container start, which the user must do.
- **A version pin:** verify the new hashes against the release's official checksums **for the exact URL the Containerfile builds**, both architectures, and confirm the tarball's internal layout still matches the install step (the `bin/<name>` path and the `--version` output). Then the user rebuilds (`cg <agent> build`) and checks the tool's version inside the container.
- **An image or script change:** the user builds and starts the affected chain (`cg <agent> build`, `cg <agent> start -b`), and the changed behavior is observable in the running container — name what to look for.
- **Hardening:** the `container run --rm -it --read-only --cap-drop ALL --tmpfs /tmp -v "$PWD/seed/.pi:/agent-home/.pi" caged:latest sh -c '...'` probe in `docs/SECURITY.md` — uid 1000, writes outside the mounts fail, `/tmp` writable.
- **Repo hygiene:** `git grep` for the old value/name you changed (a bump touches the Containerfile, the build script and any doc that names it) and confirm no pointer now targets a file that does not exist.

## Where the detail lives

| Doc | Reach for it when |
|---|---|
| `docs/SECURITY.md` | hardening, threat model, accepted risks, the web-mode posture, the restriction probe |
| `docs/CLI-AUTH.md` | glab/gh/jira-cli/cfl auth, config locations, why token-only, first-time setup |
| `docs/BROWSER.md` | browser layer design, `browserd`, host-attach mode, why not an MCP server |
| `docs/APPLE-CONTAINER.md` | anything where the runtime diverges from docker (networking, ignore rules, signals, flags it cannot express) |
| `docs/AGENT-INTEGRATION.md` | adding a new agent image (privilege, sessions under `/workspace`, global-prompt sync) |

Two files are named `AGENTS.md` in this repo, for two different readers — don't conflate them:

| File | Reader | Purpose |
|---|---|---|
| `seed/.pi/agent/AGENTS.md` | an agent *inside* the container | runtime environment primer, **generated** from `seed/prompt-src/global.md` |
| this file (`AGENTS.md` at the repo root) | you, working *on* the repo | how to build, cage and iterate |

caged is an internal project built with Apple's `container` tool on Apple silicon macOS. The image is a plain OCI image, so podman/docker can run it directly with the equivalent hardening flags.
