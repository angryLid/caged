# caged

A hardened, disposable container to run AI coding agents in — **isolation
for [`pi`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
(`@earendil-works/pi-coding-agent`) by default**.

Coding agents like pi execute arbitrary bash commands against your code, and
out of the box pi ships **no permission management of its own** — anything it
runs, it runs with whatever rights you have on the host. caged closes that
gap: a minimal Linux container where the agent works as a **non-root user on
a read-only filesystem**, with no capabilities and no extra privileges, so it
can only ever touch the workspace you explicitly hand it.

The same posture extends to a **sibling image for
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`@deepseek-ai/dsh`)** — a second agent with the same hardening and live-seed
philosophy, running dsh's browser Web UI (or one-shot headless mode) instead
of pi's TUI. See [dsh (DeepSeek Harness)](#dsh-deepseek-harness).

> **What caged is**: a minimal, locked-down runtime for an AI coding agent that
> can execute arbitrary bash commands. Non-root user, read-only rootfs,
> no capabilities, no extra privileges, one disposable volume for all state.
>
> **What caged is explicitly NOT**: a network sandbox. pi needs open networking
> to reach model providers — that part is on purpose. See
> [SECURITY.md](docs/SECURITY.md) for the full threat model.

## What's inside

* **GitLab CLI (`glab` v1.112.0)** — official GitLab CLI baked into the
  image: MRs, issues, pipelines, releases. Authenticate once with
  `GITLAB_TOKEN` (env var), nothing stored in the repo.
* **GitHub CLI (`gh` v2.97.0)** — official GitHub CLI baked into the
  image: PRs, issues, releases, Actions workflows. Authenticate once with
  `GH_TOKEN` (env var) or a persisted `gh auth login`.
* **Atlassian CLI (`acli` v1.3.22)** — official Atlassian CLI baked in:
  **Jira Cloud** work items, projects, admin APIs (also Confluence &
  Bitbucket). API-token login; state survives restarts.
* **Chrome DevTools MCP extension** — pi can drive your host Chrome through
  the chrome-devtools MCP server (browse, search, screenshots, JS
  evaluation). Optional: needs host Chrome listening on `:9222`.
* **Multiple LLM providers** — DeepSeek, Volcengine Ark, OpenRouter, plus a
  private local gateway; keys are passed via environment variables, never
  baked into the image or committed to the repo.
* **Live shared agent home** — the complete `seed/` directory is a two-way bind
  mount of `/agent-home` for all modes; pi uses `.pi`, dsh uses `.dsh`, and
  shared CLI auth lives under `cli-auth/`.
* **pi-web-ui Web UI (optional)** — a browser chat frontend for pi, in a
  separate additive image (`scripts/build-container.sh webui` +
  `scripts/start-container.sh webui`) — see
  [pi-web-ui (Web UI)](#pi-web-ui-web-ui).
* **DeepSeek Harness (`dsh`) image (optional)** — a sibling container for
  [`@deepseek-ai/dsh`](https://github.com/deepseek-ai/deepseek-harness): the
  same hardening for dsh's browser Web UI and one-shot headless mode — see
  [dsh (DeepSeek Harness)](#dsh-deepseek-harness).
* **Open networking** — deliberate, so pi can reach model providers and the
  internet (see [docs/SECURITY.md](docs/SECURITY.md) for the trade-offs).

## Layout

```
caged/
├── Containerfile        # pi image (non-root, pinned pi version)
├── Containerfile.base   # shared base for both images: apt essentials (including python3), glab, gh, acli, non-root user
├── Containerfile.dsh    # OPTIONAL: DeepSeek Harness (`@deepseek-ai/dsh`) image
├── Containerfile.webui  # OPTIONAL: pi-web-ui Web chat UI (additive layer on caged:latest)
├── seed/                # agent homes — LIVE bind-mount sources
│   ├── .pi/agent/       # pi's ~/.pi: models.json (providers), settings.json,
│   │                    #   mcp.json, AGENTS.md, skills.json, skills/, scripts/
│   └── .dsh/            # dsh's $DSH_HOME: cordis.patch.yml + generated config
├── scripts/
│   ├── build-caged-base.sh  # shared base image build (Containerfile.base) — built automatically by the one below
│   ├── build-container.sh   # Apple `container` build:  build-container.sh pi|dsh|webui  (arg required, no default)
│   ├── start-container.sh   # Apple `container` run: pi|webui|dsh + command args
│   ├── entrypoint.sh        # pi seed validation (fail-fast) + tini, runs as USER agent
│   ├── dsh-entrypoint.sh    # dsh seed validation + tini
│   ├── dsh-ensure-workspace.mjs # dsh: register /workspace as Web default
│   └── skills-sync.mjs      # declarative skills sync (see `## Skills (“skills-sync”)`)
├── README.md             # this file — docs for both images (pi by default, dsh as sibling)
└── docs/
    ├── SECURITY.md           # threat model & accepted trade-offs
    ├── CLI-AUTH.md           # glab/gh/acli auth behavior, persistence & risks
    └── APPLE-CONTAINER.md    # running via Apple's container tool

> `scripts/skills-sync.mjs` is also baked into the image (see `Containerfile`)
> so the container start can install skills **without** the workspace mounted.
```

## Skills (“skills-sync”)

This project ships a small **declarative** mechanism for pulling in external
agent skills and enabling a subset of them — see `seed/.pi/agent/skills.json`
(managed in the seed, alongside the rest of the config). It is tool-agnostic
(works with any agent that reads skills from a directory).

Skills come from two kinds of source, resolved serially in declaration order
(later sources override earlier ones on basename collision):

* **`type: "git"`** — clonable repos. These are cloned **at image build time**
  (network) into a vendor dir baked into the image (`/opt/caged/skills/vendor`).
  At **container start** the entrypoint only copies the enabled skills from
  that baked set into the seed's skills dir — **no network, no git at start**.
* **`type: "local"`** — skills you maintain directly in this repo, in
  `seed/.pi/agent/skills-src/` (git-tracked, the source of truth). They live in
  the seed already, so they need **no image build step** — the entrypoint
  copies enabled local skills straight from `skills-src/` into `skills/` at
  container start, alongside the git ones.

Skills are installed into the seed (`seed/.pi/agent/skills/`), pi's live
config home bind-mounted at `/agent-home/.pi/agent` at runtime. Each enabled
skill is copied in as a real directory (not a symlink) and marked with a
hidden `.caged-skill-managed` file, so the tool can later tell its own copies
apart from unmanaged skills.

You can also run the sync by hand, e.g. after editing `skills.json` (local dev
mode clones + installs in one step):

```bash
node scripts/skills-sync.mjs            # clone/pull git sources, then install into seed/.pi/agent/skills
node scripts/skills-sync.mjs --dry-run  # preview without changing anything
node scripts/skills-sync.mjs --link-only     # install only, from an existing vendor + local sources (no git/network)
node scripts/skills-sync.mjs --clone-only    # clone/pull git sources only (image build step)
```

- **`seed/.pi/agent/skills.json`** — the source of truth: a `sources[]` list.
  Each git source has `type`, `url`, `skillsDir`, and an `enabled` list of
  skill relative paths; each local source has `type`, `dir` (relative to the
  seed), and an `enabled` list. Plus a `linkTargets[]` list of dirs, relative
  to the seed, to install skills into (default `skills` →
  `seed/.pi/agent/skills`).
- The script **clones** each git source into the vendor dir (or `git pull`s
  it), resolves local sources from `skills-src/`, then **copies** each enabled
  skill into the target. Stale managed copies are removed, so dropping a skill
  from `enabled` uninstalls it. Unmanaged skills (anything not carrying a
  marker) are never clobbered.
- The generated copies in `skills/` and the local-dev vendor are **gitignored**
  and regenerated — edit **`skills-src/`** (your own skills) or `skills.json`
  (declarations), then re-run the script (or rebuild + restart the container to
  pick up newly-added git repos).

> pi can also run this for you: ask it to “sync skills” (uses the `skills-sync` skill).

> pi can also run this for you: ask it to “sync skills” (uses the `skills-sync` skill).

## Quickstart

Requirements: Apple's native [`container`](https://github.com/apple/container)
tool on Apple silicon (Linux containers as lightweight VMs).

```sh
# 1. build (only needed the first time, or when the images change). The
#    shared base image (Containerfile.base: apt essentials including python3,
#    glab, gh, acli, non-root user) is built automatically first. Optionally pick a pi
#    version:   PI_VERSION=x.y.z scripts/build-container.sh pi
scripts/build-container.sh pi

# 2. run from the repo you want as the workspace. The unified launcher accepts
#    a mode (pi, webui, or dsh); pi is the default.
cd /path/to/your/repo
/path/to/caged/scripts/start-container.sh              # pi TUI
/path/to/caged/scripts/start-container.sh webui       # pi Web UI
/path/to/caged/scripts/start-container.sh dsh         # dsh Web UI
/path/to/caged/scripts/start-container.sh pi --continue # pass command args
```

`start-container.sh` mounts the **directory you run it from** as `/workspace`. Its first argument selects the runtime (`pi`, `webui`, or `dsh`, defaulting to `pi`); remaining arguments replace the image's default command.

> **Why scripts, not compose?** caged runs a *single* disposable container — the
> container's only job is isolation, so a compose/multi-container stack would add
> nothing. And Apple's `container` tool doesn't support compose orchestration
> anyway, which fits perfectly. Build/run via `scripts/build-container.sh pi` +
> `scripts/start-container.sh`; full detail in
> [docs/APPLE-CONTAINER.md](docs/APPLE-CONTAINER.md).

## What gets mounted

| Path in container | Backing | Read/write | Purpose |
|---|---|---|---|
| `/workspace`   | the dir you ran `start-container.sh` from, or `$CAGED_WORKSPACE` | rw | **the code pi works on** (also backs pi's per-project session data, see below) |
| `/agent-home` (`$HOME`) | `<caged>/seed` (`$CAGED_AGENT_HOME`) | rw | **shared live agent home** — contains `.pi`, `.dsh`, and shared CLI auth; all agent modes use the same mount |
| `/agent-home/.pi/agent` | *(part of the mount above)* — `seed/.pi/agent` | rw | pi's config dir (`models.json`, `settings.json`, `mcp.json`, `AGENTS.md`, `skills/`) |

`$HOME` is `/agent-home`, and the complete `caged/seed` directory is a live
bind mount there for every mode. Pi uses `/agent-home/.pi`, dsh uses
`/agent-home/.dsh`, and shared CLI authentication uses
`/agent-home/cli-auth`. Whatever an agent writes under this home lands directly
in the repo tree. There is **no baked-in config inside the image** and no
fresh-volume seeding step — the seed *is* the live agent home.
Iterate on seed files and they take effect on the *next* container start —
no image rebuild required.

The rest of `$HOME` stays read-only (rootfs): home-derived caches are pointed
at the `/tmp` tmpfs (`npm_config_cache`, `XDG_CACHE_HOME`), keeping the
container stateful-free apart from the two mounts and scratch.

The entrypoint validates the mount **before** launching pi: if the seed is
missing or incomplete, `mcp.json` references a missing executable, or the
seed is read-only, it exits non-zero with a diagnostic instead of letting pi
run half-configured. This also catches a wrong `$CAGED_AGENT_HOME` — e.g. a path that does not
contain `.pi/agent` (the required-files check fails immediately).

Keep runtime state out of git: `seed/.pi/agent/auth.json` and
`seed/.pi/agent/sessions/` are ignored (see `.gitignore`). `auth.json` is
written the first time you authenticate, so don't worry if it doesn't exist
yet.

**Session data lives per-project on the host without a dedicated mount**: pi
no longer writes sessions into its config home. `seed/.pi/agent/settings.json`
sets `"sessionDir": "/workspace/.pi/sessions"`, and since `/workspace` is the
live workspace bind, that lands in `$CAGED_WORKSPACE/.pi/sessions` on the host
— the same location as before, so no directory-level migration is needed.
`pi -c`, `pi -r` and the `/resume` picker scan that directory. Deleting
`seed/.pi/agent` or `auth.json` does **not** touch your sessions or your API
keys' cached auth.

> **Layout note for pre-existing sessions:** with a custom `sessionDir`, pi
> stores session files *flat* in that directory instead of under a per-cwd
> subdirectory. Sessions written by an older container (which mounted
> `/agent-home/.pi/agent/sessions`) live in `.pi/sessions/<encoded-workspace-path>/`
> and no longer show up in the picker automatically — open them with
> `pi --session <path>` or move the `.jsonl` files up one level into
> `.pi/sessions/`.

## Seed config (`seed/`)

`seed/.pi/` mirrors pi's config home `~/.pi` on the host and is mounted live
(not baked into the image):

* `.pi/agent/models.json` — providers: **DeepSeek**, **Volcengine Ark Coding**
  (minimax-m3 / doubao-seed / glm-5.2), **OpenRouter**, **Local** (private,
  env-configured base URL + key)
* `.pi/agent/settings.json` — trust + `pi-mcp-adapter` extension
* `.pi/agent/mcp.json` — chrome-devtools MCP (needs host Chrome on `:9222`, optional)
* `.pi/agent/skills.json` — declarative skills config (see [`Skills`](#skills-skills-sync))
* `.pi/agent/skills/` — hand-written skills (caged-persistence, create-post, bgm-metadata, markdown-link, mdx-notes); downloaded skills are copied in here at container start
* `.pi/agent/AGENTS.md` — environment primer pi loads for the container
* `.pi/agent/scripts/` — `start-chrome-devtools-mcp.sh`, `devtools-forward.js` (CDP helpers, referenced by `mcp.json`)

To change the config, just edit `seed/.pi/agent/` — it is the live config,
mounted into the container (effective on next container start). No rebuild
round-trip.

## Provider keys

`models.json` references keys by env var name (`$MY_DEEPSEEK_API_KEY`,
`$VOLCENGINE_API_KEY`, `$MY_OPENROUTER_API_KEY`, and for the local
provider `$LOCAL_API_KEY`); pi expands these from the container
environment at runtime. The local provider's `baseUrl` is the host
`caddy-dev-server` proxy `http://192.168.64.1:8765/v1` — the Apple
`container` vmnet gateway, i.e. the host as seen from inside a container,
which forwards to the internal LLM gateway with the Host header rewritten to
the upstream hostname (that hostname lives only in the host's Caddyfile,
never in this repo). Export the keys in your shell before starting:

```sh
MY_DEEPSEEK_API_KEY=sk-... VOLCENGINE_API_KEY=ark-... \
  LOCAL_API_KEY=... scripts/start-container.sh
```

For interactive TUI auth flows that don't use `models.json`, pi stores
credentials in `auth.json` inside the agent dir
(`/agent-home/.pi/agent/auth.json` on the volume):

```sh
scripts/start-container.sh     # then run  pi auth  inside the TUI
```

Never put API keys in `/workspace` — anything there is readable by pi.

## chrome-devtools MCP

`seed/.pi/agent/mcp.json` registers a chrome-devtools MCP server. It forwards
the container-local port `19222` to the host's Chrome CDP and requires:

1. Host Chrome running with `--remote-debugging-port=9222`
2. Host Chrome's CDP reachable at `192.168.64.1:9222` (the Apple
   `container` vmnet gateway; on macOS Chrome binds loopback only, so bridge
   it with socat — see `docs/APPLE-CONTAINER.md`.)

Without host Chrome listening, pi will report the MCP server as unavailable —
that's expected, not a caged bug.

## glab (GitLab CLI)

[`glab`](https://gitlab.com/gitlab-org/cli) — the official GitLab CLI — is
baked into the shared base image (v1.112.0, pinned `ARG GLAB_VERSION`
in `Containerfile.base`, sha256-verified against the official checksums);
both the pi and the dsh image inherit it. Use it for
MRs, issues, pipelines, releases, etc. instead of hand-rolled curl against
the GitLab API.

Two ways to authenticate:

* **Env token (primary, for automated runs).** Pass `GITLAB_TOKEN` (plus
  `GITLAB_HOST=https://gitlab.example.com` for a self-hosted instance) when
  starting; it takes precedence over stored credentials and never touches
  disk:

  ```sh
  GITLAB_TOKEN=glpat-... scripts/start-container.sh
  # then run  glab issue list  inside the pi TUI
  ```

* **Persisted login (interactive).** `GLAB_CONFIG_DIR` points at
  `/agent-home/cli-auth/glab` on the live shared `/agent-home` mount, so
  `glab auth login` state survives container restarts (gitignored, like
  `acli` and `auth.json`):

  ```sh
  echo "$GITLAB_TOKEN" | scripts/start-container.sh
  # then pipe the same token into  glab auth login ...  inside the TUI
  ```

  Run from any directory (the workspace can be a throwaway dir). The token is
  stored as plaintext (`0600`, gitignored) — the trade-offs are analysed in
  [docs/CLI-AUTH.md](docs/CLI-AUTH.md).

## gh (GitHub CLI)

[`gh`](https://cli.github.com/) — the official GitHub CLI — is baked into the
shared base image (v2.97.0, pinned `ARG GH_VERSION` in
`Containerfile.base`, sha256-verified against the official per-release
checksums); both the pi and the dsh image inherit it. Use it for PRs, issues,
releases, and Actions workflows instead of hand-rolled curl against the
GitHub API.

Two ways to authenticate (mirroring `glab`):

* **Env token (primary, for automated runs).** Pass `GH_TOKEN` (+ `GH_HOST`
  for a GitHub Enterprise host) when starting; it takes precedence over
  stored credentials and never touches disk:

  ```sh
  GH_TOKEN=github_pat_... scripts/start-container.sh
  # then run  gh pr list  inside the pi TUI
  ```

* **Persisted login (interactive).** `GH_CONFIG_DIR` points at
  `/agent-home/cli-auth/gh` on the live shared `/agent-home` mount, so
  `gh auth login` state survives container restarts (gitignored, like
  `glab`/`acli` and `auth.json`):

  ```sh
  GH_TOKEN=github_pat_... scripts/start-container.sh
  # then run  gh auth login --with-token  inside the TUI
  ```

  The token is stored as plaintext (`0600`, gitignored) — the trade-offs are
  analysed alongside `glab`/`acli` in [docs/CLI-AUTH.md](docs/CLI-AUTH.md).

## acli (Atlassian CLI)

[`acli`](https://developer.atlassian.com/cloud/acli/) — Atlassian's official
command line interface (Jira Cloud, Confluence, Bitbucket, admin APIs) — is
baked into the shared base image (v1.3.22, pinned `ARG ACLI_VERSION`
in `Containerfile.base`); both the pi and the dsh image inherit it.
Atlassian only publishes `latest`-style URLs, so the pin is
enforced via the versioned `.deb` filename + the sha256 taken from
Atlassian's own apt repo `Packages` index, mirroring the `glab` pattern.

Authenticate with an API token (created at
`id.atlassian.com/manage-profile/security/api-tokens`) read from stdin:

```sh
JIRA_API_TOKEN=... scripts/start-container.sh
# then run  acli jira auth login --site "mysite.atlassian.net" \
#     --email you@example.com --token   inside the TUI
```

`ACLI_CONFIG_DIR` points at `/agent-home/cli-auth/acli` — on the live shared
`/agent-home` mount, so login state survives restarts while the token stays out
of git (`seed/cli-auth/acli/` is ignored, like `auth.json`). No secret env var
is needed; unlike `glab` there is no env-token passthrough, so authenticating
once per setup is the supported path. Auth behavior and pitfalls for both
CLIs: [docs/CLI-AUTH.md](docs/CLI-AUTH.md).

## pi-web-ui (Web UI)

[`pi-web-ui`](https://pi.dev/packages/pi-web-ui) is a browser chat interface
for pi: the pi SDK runs in-process in a Node server and streams thinking
blocks, tool calls and bash output to the browser over WebSocket — with a
built-in terminal, file tree, git panel, model management, multiple parallel
conversations and a goal mode. This repo ships it as an **optional second
frontend** for the same caged container, mirroring how dsh runs as a Web UI
sibling.

**Build** — a separate additive image, so TUI-only users never carry the
web toolchain:

```sh
scripts/build-container.sh webui        # builds base -> pi -> webui (caged-webui:latest)
```

`Containerfile.webui` is a thin layer `FROM caged:latest`: it adds only the
node-pty C++ build toolchain (`build-essential`; `python3` is already in the
shared base as a common scripting runtime — node-pty ships no Linux prebuilds,
so it must `node-gyp rebuild` at install time) and the pinned `pi-web-ui`,
then changes the CMD. The entrypoint, the build-time
skill vendor and the chrome-devtools MCP are inherited unchanged. Rollback
is trivial: stop using it, the pi TUI image is untouched.

**Run** — same workflow as the TUI, from the repo you want as the workspace:

```sh
cd /path/to/your/repo
/path/to/caged/scripts/start-container.sh webui # UI on http://127.0.0.1:8787
```

The web container gets the same hardening (`--read-only`, `--cap-drop ALL`,
`--tmpfs /tmp`) and the same two mounts (`/workspace`, the live seed), and
`pi-web-ui` reads `PI_CODING_AGENT_DIR` (`/agent-home/.pi/agent`) exactly
like the pi CLI — so `seed/.pi/agent`'s `models.json`, skills, settings and
`AGENTS.md` apply as-is, with no extra configuration. Differences from the
TUI run:

* The server binds `0.0.0.0:8787` **inside** the container (`PI_WEB_HOST`)
  and the host side is published to `127.0.0.1:${PI_WEBUI_HOST_PORT}` only
  (`PI_WEBUI_HOST_PORT=8787`) — the UI is reachable at
  `http://127.0.0.1:8787` and stays off the LAN.
* Chat history is per-project: `PI_WEB_DATA_DIR=/workspace/.pi-web`
  (= `$CAGED_WORKSPACE/.pi-web` on the host), the same pattern as sessions.
  Gitignore `.pi-web/` in your workspace repo. The launcher also passes
  `PI_CODING_AGENT_SESSION_DIR=/workspace/.pi/sessions` explicitly, so the
  Web UI's embedded pi SDK uses the same session directory as the TUI rather
  than falling back to `/agent-home/.pi/agent/sessions`.
* Memory defaults to 4 GB (`PI_WEBUI_MEMORY`): the web mode keeps agents
  running in-process and conversations alive in the background.

Caveats:

* **Updating pi-web-ui = bump `PI_WEB_UI_VERSION` and rebuild the image.**
  The runtime rootfs is read-only, so the UI's in-app self-update and
  `pi-web-ui server install` (systemd/launchd) don't apply inside caged —
  run the foreground server only (which is what the script does).
* The web server bundles its own pi SDK copy (`^0.83`), which can lag the
  pinned global pi (`0.84.2`). The seed config format is compatible and the
  two don't interfere.
* One caged container at a time per seed: don't run the TUI (`caged-pi`)
  and the Web UI (`caged-pi-webui`) simultaneously against the same
  `seed/.pi` (both mount it rw).
* The `/webui` pi extension (from `pi install npm:pi-web-ui`) is **not**
  used: inside caged it would spawn the server bound to the container
  loopback — unreachable from the host browser — and would force the build
  toolchain into the pi image. The standalone web mode above covers the
  use case.

## dsh (DeepSeek Harness)

A hardened, disposable container for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`@deepseek-ai/dsh`) — the sibling of the repo's `pi` image. Same hardening
posture (non-root uid 1000, read-only rootfs, no capabilities, no-new-privileges)
and the same "live seed, no rebuild for config" philosophy, but for dsh's
**browser Web UI** (and one-shot headless mode) instead of pi's TUI.

> dsh is a **developer preview** that is iterating rapidly, with
> compatibility-breaking changes expected. The version is pinned in
> `Containerfile.dsh` (build-arg `DSH_VERSION`, default `0.1.0-rc.6`) so a
> release bump is explicit. dsh builds on the repo's shared base image
> `Containerfile.base` (built automatically by the build script), which
> provides apt essentials including `python3`, the glab/gh/acli CLIs and the
> non-root user — the same CLI tooling pi ships.

### What it is / isn't

- **Is**: a containerized dsh — a plugin-based coding-agent harness where the
  agent can read/edit workspace files, run bash, delegate, and plan. The Web UI
  lets you configure models and pick a workspace in the browser.
- **Is NOT**: a network sandbox. dsh needs open networking to reach model
  providers, exactly like caged — see [docs/SECURITY.md](docs/SECURITY.md)
  for that accepted trade-off.

### Layout

dsh is checked in **flat at the repo root** — sibling to the pi image (caged),
sharing the same `scripts/` and `seed/` directories (see the full tree at the
top of this file). The dsh-specific pieces:

- `Containerfile.dsh` — dsh image: thin `FROM` layer on the shared base,
  pinned dsh (`ARG DSH_VERSION`)
- `scripts/dsh-entrypoint.sh` — fail-fast seed check + tini + workspace seed
- `scripts/dsh-ensure-workspace.mjs` — best-effort: register `/workspace` as Web default
- `seed/.dsh/` — LIVE `$DSH_HOME` bind source — ships our home-level
  `cordis.patch.yml`; dsh generates `profiles/`, `settings.yaml`,
  `.credentials.yaml`, `storages/` here on first run. Session logs do **NOT**
  live here — they are per-project at `<workspace>/.dsh/sessions`.

### Run it

Like caged, dsh is a single disposable container whose only job is isolation,
so there's no orchestration — and Apple's `container` tool (the runtime) has
no compose support anyway. Build and run with the scripts:

```sh
# build (context repo root: builds the shared Containerfile.base first,
# then the dsh image with build-arg DSH_VERSION)
scripts/build-container.sh dsh
# run the web UI; opens on the host loopback
scripts/start-container.sh dsh
open http://127.0.0.1:3080
```

**Stop it**: Ctrl+C in the terminal stops it cleanly on one press — the
script runs the container with `-it` (why a server needs a TTY is explained
under "Known gotchas"). From another terminal, `container stop caged-dsh`
works too.

- **Configure a model**: Settings → Models → paste a DeepSeek API key and save.
  The key is stored in `seed/.dsh/.credentials.yaml` (or, better, pass
  `DEEPSEEK_API_KEY` at launch — dsh gives the environment top, read-only
  precedence, so the key never needs to touch disk in the repo).
- **Pick a workspace**: the entrypoint seeds `/workspace` (the mounted project
  dir) as the default Web workspace on first boot, so the Web UI opens on your
  code without a manual "Choose workspace". If you ever see a stale workspace
  left from an earlier manual run (e.g. an `agent-home` leftover), remove it in
  Settings or delete the runtime state (`seed/.dsh/storages/` +
  `<workspace>/.dsh/sessions/` — gitignored test artifacts).
- **Run a task**: start a session and send a prompt.

#### Models: pi provider set migrated (+ BYOK)

The image ships the same four provider routes as the pi agent's
`seed/.pi/agent/models.json`, tracked in the home settings document
`seed/.dsh/settings.yaml` (the `llm-pi-ai` section; the file is un-ignored
in `seed/.dsh/.gitignore`, and `$DSH_HOME` is the live bind of `seed/.dsh`):

| route | key env / credential ref | protocol |
|---|---|---|
| `DeepSeek-API` | `MY_DEEPSEEK_API_KEY` | openai-completions (`api.deepseek.com`) |
| `volcengine` | `VOLCENGINE_API_KEY` | anthropic-messages (Ark coding) |
| `my-openrouter` | `MY_OPENROUTER_API_KEY` | openai-completions |
| `local-llm` | `LOCAL_API_KEY` | openai-completions (host `192.168.64.1:8765`) |

**BYOK works out of the box**: dsh configs reference keys by name
(`apiKeyEnv`, no value ever in config/settings). Users paste their own key in
the Web UI (Settings → Models → card → key field); dsh stores it in
`seed/.dsh/.credentials.yaml` and resolves it per request — no restart, no
operator env needed. An operator-injected env var of the same name (e.g. via
`scripts/start-container.sh dsh`) shadows the stored value and renders the
field read-only. The `llm-pi-ai` adapter is dormant-capable: removing the
section empties the route set while the full pi-ai catalog stays configurable
from the Models page.

`settings.yaml` is dsh-managed, so the Models page edits the same file the
repo tracks — expect occasional noise diffs in git status after a UI change
(models/keys themselves land in `.credentials.yaml`, which stays ignored).

#### Permission model (danger-full-access by default)

dsh ships its own process sandbox (bwrap / Landlock / seatbelt) and interactive
approval prompts. caged **does not want those**: the container is already the
sandbox (non-root uid 1000, read-only rootfs, no caps), and dsh's own
confinement would likely fail inside a hardened read-only container anyway
(`SANDBOX_UNAVAILABLE`). So this image runs dsh in its official "allow all"
mode via the purpose-built env knob:

```
DSH_PERMISSION_MODE=danger-full-access   # default here
```

Set by `scripts/start-container.sh dsh`; it makes the base bundle set
`sandbox/mode: danger-full-access` (bash/fs operations run as uid 1000 with no
dsh-level file confinement) and `approval/policy: never` (no interactive
approval prompts). The agent effectively has the full rights of the `pi` user
inside the container. Override (`DSH_PERMISSION_MODE=workspace-write`, etc.) if
you want dsh's own sandbox + approval back.

#### One-shot headless (no server, prints the answer and exits)

Run with the `container` tool directly, mirroring `scripts/start-container.sh dsh` but
adding `dsh --profile headless "…"` as the command:

```sh
container run --rm \
  --read-only --cap-drop ALL --tmpfs /tmp --memory 2g \
  -v "$PWD:/workspace:rw" \
  -v "$PWD/seed:/agent-home:rw" \
  -e DSH_HOME=/agent-home/.dsh \
  -e DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-${MY_DEEPSEEK_API_KEY:-}}" \
  -e VOLCENGINE_API_KEY="${VOLCENGINE_API_KEY:-}" \
  -e MY_OPENROUTER_API_KEY="${MY_OPENROUTER_API_KEY:-}" \
  -e LOCAL_API_KEY="${LOCAL_API_KEY:-}" \
  -e DSH_PERMISSION_MODE=danger-full-access \
  dsh:latest dsh --profile headless "explain this repo and exit"
```

`scripts/start-container.sh dsh` starts the Web UI. It publishes
`127.0.0.1:${DSH_HOST_PORT} -> 3080` via `container run -p` (host
**loopback**, not the LAN), reaching the webserver (which binds `0.0.0.0:3080`
inside the container via `cordis.patch.yml`). The container port is a stable
3080; only `DSH_HOST_PORT` varies. Hardening is the tool's implementable
subset (same as the pi image): `--read-only`, `--cap-drop ALL`, `--tmpfs
/tmp`, pinned memory — no userns / no `--security-opt`. Env knobs: `DSH_IMAGE`,
`DSH_VERSION`, `CAGED_AGENT_HOME`, `CAGED_WORKSPACE`, `DSH_MEMORY` (build:
`CAGED_BASE_IMAGE`, `CAGED_SKIP_BASE`, `GLAB_VERSION`, `ACLI_VERSION`).

### Port mapping

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

Override only the host side, e.g. `DSH_HOST_PORT=8080 scripts/start-container.sh dsh`.
No `--host 0.0.0.0` flag is passed anywhere — the CLI's RCE guard is preserved;
we only set the runtime config to bind inside the container, and the host publish
stays loopback-only.

### Volume mapping

| Volume | Mount | Why |
|---|---|---|
| `${CAGED_WORKSPACE:-$PWD}` | `/workspace:rw` | the code dsh agents work on — **the default Web workspace** |
| `${CAGED_AGENT_HOME:-./seed}` | `/agent-home:rw` | Shared live agent home; dsh uses `/agent-home/.dsh`, including its config and non-session runtime state |

`$DSH_HOME` (default `~/.dsh`) is dsh's live config/data root, the analogue
of pi's `~/.pi`: `profiles/<name>/`, `settings.yaml`, `.credentials.yaml`,
`.env`, and storages live under it. Session logs are **not** kept there; the
`session-persistence-jsonl` `root` config in `cordis.patch.yml` points them at
`/workspace/.dsh/sessions` (mirroring pi's `$CAGED_WORKSPACE/.pi/sessions`
without requiring an extra mount). In this repo the config root is a live bind
of `seed/.dsh`, so:

- dsh auto-initializes its `web`/`headless` profiles on first use. We ship one
  home-level patch (`seed/.dsh/cordis.patch.yml`) that binds the webserver to
  the container network; everything else is generated at first run.
- Config edits land on the **next start**, no image rebuild.
- **Runtime state stays out of git** — `seed/.dsh/.gitignore` ignores the
  generated files; track only config you author.

### Security notes

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

### Known gotchas / untested on this host

- **Ctrl+C needs a TTY to stop cleanly (upstream signal-forwarding bug).**
  `scripts/start-container.sh dsh` passes `-it` not because dsh is a TUI but
  as a workaround: without a TTY, Apple `container`'s foreground CLI forwards
  Ctrl+C (SIGINT) to the guest via XPC in a form its own API service can't
  decode — every press prints `failed to send signal: ... "missing signal in
  xpc message"` and "signal": 2, the signal never reaches the container, and
  the CLI only force-exits after three presses. With `-it` the host terminal
  is in raw mode and Ctrl+C flows through the pty into the guest line
  discipline (the same path caged-pi uses), so one press stops the web
  container. From another terminal, `container stop caged-dsh` works
  regardless. Upstream: apple/container#1747 (SIGWINCH variant of the same
  Int64-vs-String mismatch in the non-TTY signal path).

- **node-pty must compile on Linux.** dsh's terminal dep `node-pty@1.1.0`
  ships no Linux prebuilds (only darwin/win32), so on Linux its install always
  runs `node-gyp rebuild`. The image therefore installs a C++ toolchain
  (`python3` in the shared base and `build-essential` in the cached dsh
  layer). First build is slow; subsequent ones are cached.

- First build needs enough memory for npm's dependency resolution (the whole
  `@deepseek-ai/dsh` tree is large). On a memory-constrained builder, raise it
  (e.g. `container build --memory=6g`, or add `--memory` to the build step).
- `--publish` forwards to the container IP on its **first** network; with the
  default network that is where the webserver binds, so the default path works
  as-is. If you attach dsh to a custom network, keep the publish target in mind.

## Environment knobs

`scripts/start-container.sh` (and `scripts/build-container.sh pi|dsh|webui` /
`scripts/build-caged-base.sh`) read these from the calling shell; defaults
listed.

| Env var | Default | Meaning |
|---|---|---|
| `CAGED_IMAGE` | `caged:latest` | image tag to run |
| `CAGED_BASE_IMAGE` | `caged-base:latest` | shared base image tag — built first by `build-caged-base.sh`, imported via FROM in both Containerfiles |
| `CAGED_SKIP_BASE` | `0` | set to `1` to skip the automatic base rebuild when building a derived image |
| `GLAB_VERSION` | `1.112.0` | glab version pin (build time, `build-caged-base.sh`) |
| `GH_VERSION` | `2.97.0` | gh version pin (build time, `build-caged-base.sh`) |
| `ACLI_VERSION` | `1.3.22` | acli version pin (build time, `build-caged-base.sh`) |
| `CAGED_WEB_IMAGE` | `caged-webui:latest` | pi-web-ui image tag (build + run of the web mode) |
| `PI_WEB_UI_VERSION` | `0.26.0` | pi-web-ui version pin (build time, `build-container.sh webui`) |
| `CAGED_SKIP_PI` | `0` | set to `1` to skip the pi image build when building `webui` (e.g. it is already current) |
| `PI_WEBUI_HOST_PORT` | `8787` | host-loopback port of the Web UI (`http://127.0.0.1:8787`) |
| `PI_WEBUI_MEMORY` | `4g` | RAM for the web-mode container VM (`CAGED_MEMORY` for the TUI) |
| `CAGED_WORKSPACE` | `$PWD` | host dir mounted at `/workspace` |
| `CAGED_AGENT_HOME` | `./seed` (relative to the repo root) | host dir bind-mounted at `/agent-home` (`$HOME`) — complete shared live agent home |
| `MY_DEEPSEEK_API_KEY` | *(unset)* | DeepSeek provider key (passed into container) |
| `VOLCENGINE_API_KEY` | *(unset)* | Volcengine Ark provider key (passed into container) |
| `MY_OPENROUTER_API_KEY` | *(unset)* | OpenRouter provider key (passed into container) |
| `LOCAL_API_KEY` | *(unset)* | Local LLM provider key (passed into container) |
| `GITLAB_TOKEN` | *(unset)* | `glab` (GitLab CLI) API token (passed into container) |
| `GITLAB_HOST` | *(unset)* | `glab` GitLab instance host (default `https://gitlab.com`) |
| `GH_TOKEN` | *(unset)* | `gh` (GitHub CLI) API token (passed into container) |
| `GH_HOST` | *(unset)* | `gh` GitHub Enterprise host (default `github.com`) |

> dsh's dedicated knobs — `DSH_IMAGE`, `DSH_VERSION`, `DSH_HOST_PORT`,
> `DSH_MEMORY`, `DSH_PERMISSION_MODE` — are documented in the
> [dsh (DeepSeek Harness)](#dsh-deepseek-harness) section.

## Runtime hardening (applied by scripts/start-container.sh)

* `--read-only` — root filesystem immutable (only `/workspace`, the shared `/agent-home`, and `/tmp` writable)
* `--tmpfs /tmp` — scratch, `noexec,nosuid`
* `--cap-drop ALL` — container process gets zero kernel capabilities
* `--security-opt no-new-privileges` — no setuid-style privilege escalation
* `--userns=keep-id` — stays UID 1000, maps cleanly to your host user

See [docs/SECURITY.md](docs/SECURITY.md) for the detailed threat model and the
explicitly accepted risks (open network, rw workspace).

## Known issues (accepted / deferred)

These are known rough edges we've consciously chosen **not** to fix yet.

* **Container start requires all provider keys up front, but failures are
  deferred.** Every provider key env var defaults to empty; if one is missing,
  pi only errors when that model is actually used — a delayed, hard-to-trace
  failure rather than a fail-fast startup check.
* **Skill basename collisions are warned about, not resolved.** If two vendor
  repos ship a skill with the same name (e.g. `handoff`), the tool warns but
  still installs both; pi loads only the first, so which one wins depends on
  repo order.
* **The open-network model means a compromised agent could exfiltrate keys.**
  Keys live in the container env and `auth.json`; a breached agent can read
  them and send them out. This is an accepted trade-off (see
  [docs/SECURITY.md](docs/SECURITY.md)); keep real secrets out of `/workspace`.

## Known limitations

* Running on macOS: Apple's `container` tool runs Linux containers as a VM, so
  `/workspace` bind-mount performance matters for large repos — see the earlier
  discussion about small-file I/O. `npm install` in the workspace will be
  slower than native.
* pi startup is slow while it loads its two extensions
  (`pi-mcp-adapter`, `pi-web-access`): the module imports take ~1.3s
  (measured ~820–960ms + ~470–520ms, `PI_TIMING=1`) before the TUI
  appears. This looks like container-level I/O cost for loading the
  extension tree — neither baking the extensions into the image layer nor
  pre-priming caches changed the timing on our setup. Workarounds if it
  bothers you: drop `pi-mcp-adapter`/`pi-web-access` from `packages` in
  `seed/.pi/agent/settings.json` (`"packages": []`), or accept the delay
  per container start.
* The pi version is pinned via `ARG PI_VERSION` (default `0.84.2`). Rebuild a
  specific version with `PI_VERSION=x.y.z scripts/build-container.sh pi`. (We
  deliberately don't quote a number here — the project is still iterating.)
* The web mode (`caged-webui`) bundles its own pi SDK copy (`^0.83`), which
  can lag the pinned global pi — config format is compatible, they don't
  interfere; see [pi-web-ui (Web UI)](#pi-web-ui-web-ui).

## License / notes

Internal project. Built with Apple's `container` tool on Apple silicon macOS.
The image itself remains a plain OCI image, so it can also be run directly
under podman/docker (with equivalent hardening flags) if you're not on Apple
silicon — see docs/APPLE-CONTAINER.md.
