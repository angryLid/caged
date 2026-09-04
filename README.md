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

The same posture extends to **sibling images for
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`@deepseek-ai/dsh`) and [Command Code](https://commandcode.ai/) (`command-code`) — sibling agents with the same hardening and live-seed
philosophy, running dsh's browser Web UI (or one-shot headless mode) instead
of pi's TUI. See [dsh (DeepSeek Harness)](#dsh-deepseek-harness) and [Command Code](#command-code).

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
* **Jira CLI (`jira` v1.7.0)** — community-maintained, MIT-licensed
  [jira-cli](https://github.com/ankitpokhrel/jira-cli) baked in: **Jira Cloud
  & Server/Data Center** work items, epics, sprints, boards, releases, projects
  (replaces the Atlassian-maintained `acli`). Env-token auth
  (`JIRA_API_TOKEN`), no token stored on disk; scripting-friendly output
  (`--plain`/`--raw` JSON/`--csv`).
* **Confluence CLI (`cfl` v1.3.96)** — MIT-licensed
  [atlassian-cli](https://github.com/open-cli-collective/atlassian-cli)
  Confluence Cloud CLI baked in: read/search/create/edit pages, spaces,
  attachments; `page view` renders **Markdown** by default — made for agents.
  Env-token auth (`CFL_URL`/`CFL_EMAIL`/`CFL_API_TOKEN`, same Atlassian API
  token as `JIRA_API_TOKEN`), no token at rest.
* **Python dependency tools** — `python`, `pip`, and `uv` are installed in the
  shared base image for Python scripting, virtual environments, and dependency
  management.
* **Node.js package managers** — `pnpm` and `yarn` are installed globally and
  available to every derived image.
* **Chrome DevTools MCP extension** — pi can drive your host Chrome through
  the chrome-devtools MCP server (browse, search, screenshots, JS
  evaluation). Optional: needs host Chrome listening on `:9222`.
* **Multiple LLM providers** — DeepSeek, Volcengine Ark, OpenRouter, plus a
  private local gateway; keys are passed via environment variables, never
  baked into the image or committed to the repo.
* **Live shared agent home** — the complete `seed/` directory is a two-way bind
  mount of `/agent-home` for all modes; pi uses `.pi`, dsh uses `.dsh`, and
  CLI configs follow the CLIs' own defaults under `$XDG_CONFIG_HOME`
  (= `seed/.config/`, gitignored). Auth is token-only via env vars.
* **pi-web-ui Web UI (optional)** — a browser chat frontend for pi, in a
  separate additive image (`cg webui build` + `cg webui start`) — see
  [pi-web-ui (Web UI)](#pi-web-ui-web-ui).
* **Command Code image (optional)** — `cmdc`, a sibling container for [Command Code](https://commandcode.ai/), which requires Node.js 22+ and stores its login/state under `seed/.commandcode/`.
* **DeepSeek Harness (`dsh`) image (optional)** — a sibling container for
  [`@deepseek-ai/dsh`](https://github.com/deepseek-ai/deepseek-harness): the
  same hardening for dsh's browser Web UI and one-shot headless mode — see
  [dsh (DeepSeek Harness)](#dsh-deepseek-harness).
* **Open networking** — deliberate, so pi can reach model providers and the
  internet (see [docs/SECURITY.md](docs/SECURITY.md) for the trade-offs).

## Layout

```
caged/
├── cg                     # unified launcher: cg <agent> <start|build> (replaces build.sh / start.sh)
├── Containerfile        # pi image (non-root, pinned pi version)
├── Containerfile.base   # shared base for all images: apt essentials (including python3/pip, uv, pnpm, yarn), glab, gh, jira-cli, cfl, non-root user, sync scripts
├── Containerfile.dsh    # OPTIONAL: DeepSeek Harness (`@deepseek-ai/dsh`) image
├── Containerfile.commandcode # OPTIONAL: Command Code image
├── Containerfile.webui  # OPTIONAL: pi-web-ui Web chat UI (additive layer on caged:latest)
├── seed/                # agent homes — LIVE bind-mount sources
│   ├── .pi/agent/       # pi's ~/.pi: models.json (providers), settings.json,
│   │                    #   mcp.json, AGENTS.md, skills/, scripts/
│   ├── .dsh/            # dsh's $DSH_HOME: cordis.patch.yml + generated config, skills/
│   ├── .commandcode/    # Command Code's HOME state: settings.json (bypass), skills/
│   ├── skills-src/      # git-tracked local skills (source of truth, shared by all agents)
│   ├── skills-sync/     # gitignored: host clones of the external skill repos (vendor/)
│   └── skills.json      # declarative skills config (shared by all agents)
├── scripts/
│   ├── build-caged-base.sh  # shared base image build (Containerfile.base) — built automatically by the one below
│   ├── build-container.sh   # Apple `container` build:  build-container.sh pi|dsh|webui|cmdc  (arg required, no default)
│   ├── start-container.sh   # Apple `container` run: pi|webui|dsh|cmdc + command args
│   ├── entrypoint.sh        # pi seed validation (fail-fast) + skills sync + tini, runs as USER agent
│   ├── dsh-entrypoint.sh    # dsh seed validation + skills sync + tini
│   ├── commandcode-entrypoint.sh # cmdc: relocate sessions to /workspace + skills sync
│   ├── dsh-ensure-workspace.mjs # dsh: register /workspace as Web default
│   └── skills-sync.mjs      # declarative skills sync (see `## Skills (“skills-sync”)`)
├── README.md             # this file — docs for both images (pi by default, dsh as sibling)
└── docs/
    ├── SECURITY.md           # threat model & accepted trade-offs
    ├── CLI-AUTH.md           # glab/gh/jira-cli/cfl auth behavior, persistence & risks
    ├── APPLE-CONTAINER.md    # running via Apple's container tool
    └── AGENT-INTEGRATION.md  # SOP for adding a new agent image to caged

> `scripts/skills-sync.mjs` is also baked into the base image (see
> `Containerfile.base`) so every container start can install skills **without**
> the workspace mounted. Only the script is — the skill repos themselves are
> not in the image; they live in the seed.
```

## Skills (“skills-sync”)

This project ships a small **declarative** mechanism for pulling in external
agent skills and enabling a subset of them — see `seed/skills.json` (managed
in the seed, alongside the rest of the config). It is shared by **all three
agent images** (pi, dsh, Command Code): each enabled skill is installable into
every directory listed in `linkTargets`. Each agent's entrypoint runs the
same `--link-only --target <agent>` sync at container start, so a pi container
start only refreshes pi's skills dir, a dsh start only dsh's, and so on.
It works with any agent that reads the Agent Skills standard (a directory per
skill with a `SKILL.md`).

Skills come from two kinds of source, resolved serially in declaration order
(later sources override earlier ones on basename collision):

* **`type: "git"`** — clonable repos. These are cloned **on the host, at build
  time** (`scripts/build-caged-base.sh`, i.e. any `cg <agent> build`) into a
  vendor dir inside the seed (`seed/skills-sync/vendor/skills/`). The repos are
  **not** baked into the image — the seed is bind-mounted into every container
  anyway, so at **container start** each entrypoint just copies the enabled
  skills out of that vendor into the seed's skills dirs — **no network, no git
  at start**. Skip the clone step with `CAGED_SKIP_SKILLS_SYNC=1` (offline
  rebuilds reuse whatever is already vendored).
* **`type: "local"`** — skills you maintain directly in this repo, in
  `seed/skills-src/` (git-tracked, the source of truth). They live in the seed
  already, so they need **no image build step** — the entrypoint copies
  enabled local skills straight from `skills-src/` into each target `skills/`
  dir at container start, alongside the git ones.

Skills are installed into the seed, one directory per agent:
`seed/.pi/agent/skills/` (pi), `seed/.dsh/skills/` (dsh), and
`seed/.commandcode/skills/` (Command Code) — each is the live bind-mounted
skills dir that the corresponding agent scans at runtime. Each enabled skill
is copied in as a real directory (not a symlink) and marked with a hidden
`.caged-skill-managed` file, so the tool can later tell its own copies apart
from unmanaged skills.

You can also run the sync by hand, e.g. after editing `skills.json` (local dev
mode clones + installs in one step):

```bash
node scripts/skills-sync.mjs            # clone/pull git sources, then install into all seed skills dirs
node scripts/skills-sync.mjs --dry-run  # preview without changing anything
node scripts/skills-sync.mjs --link-only     # install only, from an existing vendor + local sources (no git/network)
node scripts/skills-sync.mjs --link-only --target pi    # install into one agent's dir only (what container start does)
node scripts/skills-sync.mjs --clone-only    # clone/pull git sources only (what the build script runs)
```

- **`seed/skills.json`** — the source of truth: a `sources[]` list. Each git
  source has `type`, `url`, `skillsDir`, and an `enabled` list of skill
  relative paths; each local source has `type`, `dir` (relative to the seed
  root), and an `enabled` list. Plus a `linkTargets[]` list of dirs, relative
  to the seed root, to install skills into — one entry per agent (default
  `skills` → `seed/skills`).
- The script **clones** each git source into the vendor dir (or `git pull`s
  it), resolves local sources from `seed/skills-src/`, then **copies** each
  enabled skill into every target. Stale managed copies are removed, so
  dropping a skill from `enabled` uninstalls it. Unmanaged skills (anything
  not carrying a marker) are never clobbered.
- The generated copies in each `skills/` dir and the vendor clones are
  **gitignored** and regenerated — edit **`seed/skills-src/`** (your own
  skills) or `seed/skills.json` (declarations), then re-run the script. Adding
  a whole new git source needs no image rebuild either, just a re-run (or any
  `cg <agent> build`, which clones as part of the base step).

> Any agent can run this for you: ask it to “sync skills” (uses the
> `skills-sync` skill, installed into every agent's skills dir).

## Global prompt (“prompt-sync”)

Every agent carries the same **always-loaded environment primer** — the caged
rules (non-root, write-in-English, one-line comments, host-runs-tooling,
server-side confirmation, no secrets in the workspace). It is maintained once
and synced verbatim into every agent's user-level prompt file, so the global
prompt is byte-identical everywhere (no per-agent variants).

* **`seed/prompt-src/global.md`** — the single source of truth (git-tracked).
  Edit this file; never the generated copies.
* **`seed/prompts.json`** — declares the source and the install targets,
  mirroring `skills.json`. Currently two agents:
  * `pi` → `seed/.pi/agent/AGENTS.md` (pi's env primer)
  * `cmdc` → `seed/.commandcode/AGENTS.md` (Command Code's user-level memory)
* **`scripts/prompt-sync.mjs`** — copies `global.md` into each target (a single
  file, no merge), guarded by a hidden `.caged-prompt-managed` marker so
  hand-written prompts are never clobbered. Baked into the base image at
  `/opt/caged/prompt-sync.mjs`; each entrypoint installs its own target at
  container start (best-effort).

```bash
node scripts/prompt-sync.mjs            # install into all seed targets (local dev)
node scripts/prompt-sync.mjs --dry-run  # preview without changing anything
node scripts/prompt-sync.mjs --target cmdc   # install into one target only (what container start does)
```

The generated copies (`seed/.pi/agent/AGENTS.md`, `seed/.commandcode/AGENTS.md`)
are **gitignored** and regenerated — change the prompt by editing
`seed/prompt-src/global.md`, then re-run the sync (or just restart the
container). Add a new agent to the global prompt by appending its user-level
prompt file to `prompts.json`'s `linkTargets` and wiring the `--target` call
into that agent's entrypoint.

## Quickstart

Requirements: Apple's native [`container`](https://github.com/apple/container)
tool on Apple silicon (Linux containers as lightweight VMs), plus **Node.js on
the host** — the build clones the git skill sources into the seed with
`scripts/skills-sync.mjs` (skip that step with `CAGED_SKIP_SKILLS_SYNC=1`).

```sh
# 1. build (only needed the first time, or when the images change). The
#    shared base image (Containerfile.base: apt essentials including python3,
#    glab, gh, jira-cli, cfl, non-root user) is built automatically first, and the git
#    skill repos are cloned into seed/skills-sync/vendor/ on the host.
#    Optionally pick a pi version:   PI_VERSION=x.y.z cg pi build
cg pi build

# 2. run from the repo you want as the workspace. The unified launcher accepts
#    an agent (pi, webui, dsh, or cmdc) and a command (start); pi is the default agent.
cd /path/to/your/repo
/path/to/caged/cg pi start              # pi TUI
/path/to/caged/cg webui start           # pi Web UI
/path/to/caged/cg dsh start             # dsh Web UI
/path/to/caged/cg cmdc start            # Command Code CLI
/path/to/caged/cg pi start --continue   # pass command args
```

`cg` mounts the **directory you run it from** as `/workspace`. Its first argument selects the agent (`pi`, `webui`, `dsh`, or `cmdc`), the second the command (`build` or `start`); remaining arguments are passed through — for `start`, they replace the image's default command. `cg` replaces the old root-level `build.sh` and `start.sh` wrappers and forwards to `scripts/build-container.sh` and `scripts/start-container.sh`, so all environment overrides keep working unchanged.

> **Why scripts, not compose?** caged runs a *single* disposable container — the
> container's only job is isolation, so a compose/multi-container stack would add
> nothing. And Apple's `container` tool doesn't support compose orchestration
> anyway, which fits perfectly. Build/run via `cg pi build` +
> `cg pi start`; full detail in
> [docs/APPLE-CONTAINER.md](docs/APPLE-CONTAINER.md).

## What gets mounted

| Path in container | Backing | Read/write | Purpose |
|---|---|---|---|
| `/workspace`   | the dir you ran `cg pi start` from, or `$CAGED_WORKSPACE` | rw | **the code pi works on** (also backs pi's per-project session data, see below) |
| `/agent-home` (`$HOME`) | `<caged>/seed` (`$CAGED_AGENT_HOME`) | rw | **shared live agent home** — contains `.pi`, `.dsh`, and CLI configs (their own defaults under `.config`); all agent modes use the same mount |
| `/agent-home/.pi/agent` | *(part of the mount above)* — `seed/.pi/agent` | rw | pi's config dir (`models.json`, `settings.json`, `mcp.json`, `AGENTS.md`, `skills/`) |

`$HOME` is `/agent-home`, and the complete `caged/seed` directory is a live
bind mount there for every mode. Pi uses `/agent-home/.pi`, dsh uses
`/agent-home/.dsh`, and CLI configs follow the CLIs' own defaults under
`/agent-home/.config` (auth is env-token only, nothing secret is persisted).
Whatever an agent writes under this home lands directly
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

* `.pi/agent/models.json` — providers: **DeepSeek**, **OpenRouter**,
  **JustWoker**, **Local** (private, env-configured base URL + key; models
  `Coding` — DeepSeek V4 Flash, `GLM-5.3-Flash`, `Qwen3.8-flash-next`, all
  ¤0.75/¤0.75 in and out, all pinned to 270k context / 16k output. Only
  `Qwen3.8-flash-next` takes images; `GLM-5.3-Flash` runs with vision and
  prefill cache off to free VRAM for the KV cache, so it is a poor fit for
  RAG-style work)
* `.pi/agent/settings.json` — trust + `pi-mcp-adapter` extension
* `.pi/agent/mcp.json` — chrome-devtools MCP (needs host Chrome on `:9222`, optional)
* `.pi/agent/skills/` — pi's installed skills (generated by skills-sync at
  container start; sources of truth: `seed/skills.json` + `seed/skills-src/`)
* `.pi/agent/AGENTS.md` — pi's environment primer (generated by prompt-sync at
  container start; source of truth: `seed/prompt-src/global.md` + `seed/prompts.json`).
  The **same** primer is installed to cmdc's `~/.commandcode/AGENTS.md`, so the
  global prompt is identical across agents — edit `seed/prompt-src/global.md`,
  never the generated copies.
* `.pi/agent/scripts/` — `start-chrome-devtools-mcp.sh`, `devtools-forward.js` (CDP helpers, referenced by `mcp.json`)

To change the config, just edit `seed/.pi/agent/` — it is the live config,
mounted into the container (effective on next container start). No rebuild
round-trip.

## Provider keys

`models.json` references keys by env var name (`$MY_DEEPSEEK_API_KEY`,
`$VOLCENGINE_API_KEY`, `$MY_OPENROUTER_API_KEY`, `$JUSTWOKER_API_KEY`, and for
the local provider `$LOCAL_API_KEY`); pi expands these from the container
environment at runtime. The local provider's `baseUrl` is the host
`caddy-dev-server` proxy `http://192.168.64.1:8765/v1` — the Apple
`container` vmnet gateway, i.e. the host as seen from inside a container,
which forwards to the internal LLM gateway with the Host header rewritten to
the upstream hostname (that hostname lives only in the host's Caddyfile,
never in this repo). Export the keys in your shell before starting:

```sh
MY_DEEPSEEK_API_KEY=sk-... VOLCENGINE_API_KEY=ark-... \
  LOCAL_API_KEY=... cg pi start
```

For interactive TUI auth flows that don't use `models.json`, pi stores
credentials in `auth.json` inside the agent dir
(`/agent-home/.pi/agent/auth.json` on the volume):

```sh
cg pi start     # then run  pi auth  inside the TUI
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

Authenticate with an env token (CI/CD style — no `auth login`, no stored
credential):

```sh
GITLAB_TOKEN=glpat-... cg pi start
# then run  glab issue list  inside the pi TUI
```

For a self-hosted instance also pass `GITLAB_HOST=https://gitlab.example.com`
(bytes are matched per-host, see [docs/CLI-AUTH.md](docs/CLI-AUTH.md)).
`glab` writes its non-secret config (host/user settings) to its default
location under the seed; caged does not manage it.

## gh (GitHub CLI)

[`gh`](https://cli.github.com/) — the official GitHub CLI — is baked into the
shared base image (v2.97.0, pinned `ARG GH_VERSION` in
`Containerfile.base`, sha256-verified against the official per-release
checksums); both the pi and the dsh image inherit it. Use it for PRs, issues,
releases, and Actions workflows instead of hand-rolled curl against the
GitHub API.

Authenticate with an env token (mirroring `glab` — no `auth login`, no stored
credential):

```sh
GH_TOKEN=github_pat_... cg pi start
# then run  gh pr list  inside the pi TUI
```

For a GitHub Enterprise host pass `GH_HOST` as well. The token never touches
disk; `gh` lazily writes its non-secret config to its default location under
the seed. Trade-offs shared with `glab`/`jira-cli`:
[docs/CLI-AUTH.md](docs/CLI-AUTH.md).

## jira-cli (Jira)

[`jira-cli`](https://github.com/ankitpokhrel/jira-cli) (binary `jira`) — a
community-maintained, MIT-licensed Jira client (Jira Cloud + Server/Data
Center, v2 & v3 APIs) — is baked into the shared base image (v1.7.0, pinned
`ARG JIRA_VERSION` in `Containerfile.base`); both the pi and the dsh image
inherit it. It replaces the Atlassian-maintained `acli` for Jira work-item
workflows (issue/epic/sprint/board/release/project) and is deliberately
coding-agent friendly: `--plain` / `--raw` (JSON) / `--csv` output,
`--no-input` scripting, raw-JQL search, and a native `board` command group.
The release is pinned via the versioned tarball + `checksums.txt` sha256,
mirroring the `glab` pattern.

Authenticate with an API token (created at
`id.atlassian.com/manage-profile/security/api-tokens`) via the **env var** —
no login command, no token at rest:

```sh
JIRA_API_TOKEN=... cg pi start
# then run  jira project list  inside the pi TUI
```

jira-cli needs a one-time `jira init` (site URL, login, default project/board)
before first use — the token for that comes from the same `JIRA_API_TOKEN`
env var. The init writes its non-secret config to jira-cli's default location,
which resolves to the seed (`XDG_CONFIG_HOME` → gitignored `seed/.config/`),
so it survives restarts without caged managing it. Unlike `glab` there is no
persisted token to renew: the token always comes from `JIRA_API_TOKEN`, so
re-auth happens only when the token rotates. With the shared `ATLASSIAN_*`
trio injected, `start-container.sh` sets `JIRA_SERVER`/`JIRA_LOGIN`
from it at launch, and jira-cli resolves env before config — so server/login/token
rotations need no `jira init` re-run. Auth behavior and pitfalls for
all four CLIs: [docs/CLI-AUTH.md](docs/CLI-AUTH.md).

## cfl (Confluence)

[`cfl`](https://github.com/open-cli-collective/atlassian-cli) (binary `cfl`) —
the Confluence Cloud CLI from the MIT-licensed `open-cli-collective/atlassian-cli`
monorepo — is baked into the shared base image (v1.3.96, pinned `ARG CFL_VERSION`
in `Containerfile.base`); both the pi and the dsh image inherit it. It fills
the gap jira-cli leaves: **Confluence pages** (read/search/create/edit/copy),
spaces, attachments, comments and labels, via the Confluence v2 REST API.
Cloud only — [mcp-atlassian](https://github.com/sooperset/mcp-atlassian) is the
alternative if you ever need Server/Data Center.

Deliberately agent-friendly: `cfl page view <id>` renders the page body as
**Markdown** (ADF/XHTML on request via `--body-format`), `cfl page list
--space KEY` and `cfl search "query" --space KEY`/`--cql "..."` cover
discovery, `--output plain`/`--full` shape terminal output, and
`--non-interactive` (plus `init --token-stdin`/`--token-from-env`) keeps every
flow scriptable. Env-token auth, no token at rest:

```sh
CFL_URL=https://your-site.atlassian.net CFL_EMAIL=you@example.com \
CFL_API_TOKEN=... cg pi start
# then run  cfl page view 12345  inside the pi TUI
```

The token is the **same Atlassian API token** as `JIRA_API_TOKEN`. You only
need to pass **one** of the two: `start-container.sh` derives the other at
start, so existing `JIRA_API_TOKEN`-only setups gain Confluence access with
zero extra env vars:

```sh
# Same Atlassian token for both CLIs — either one is enough:
JIRA_API_TOKEN=... cg pi start            # cfl gets CFL_API_TOKEN from it
# CFL_API_TOKEN=... cg pi start           # jira gets JIRA_API_TOKEN from it
# then run  cfl page view 12345  inside the pi TUI
```

Alternatively, inject the shared `ATLASSIAN_*` trio once — `start-container.sh`
maps it onto the CLI vars on the host at launch (a bare `ATLASSIAN_HOST` gets
an `https://` prefix):

```sh
ATLASSIAN_HOST=your-site.atlassian.net ATLASSIAN_EMAIL=you@example.com \
ATLASSIAN_API_TOKEN=... cg pi start      # cfl and jira both authenticate
```

Unlike jira-cli there is no config prerequisite: the three `CFL_*` env vars
alone suffice (`CFL_EMAIL`/`CFL_URL` are still individually required; only
the token is shared). `cfl init` exists for optional non-secret defaults
(default space) and is headless-capable, but caged does not require it. The
OS-keyring token store (`cfl set-credential`) is never used — this container
has no keyring, and env vars resolve first anyway. Auth behavior and
pitfalls: [docs/CLI-AUTH.md](docs/CLI-AUTH.md).

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
cg webui build        # builds base -> pi -> webui (caged-webui:latest)
```

`Containerfile.webui` is a thin layer `FROM caged:latest`: it adds the pinned
`pi-web-ui` package and changes the CMD. The shared base includes the node-pty
C++ build toolchain (`build-essential` and `python3`); node-pty ships no Linux
prebuilds, so it must run `node-gyp rebuild` at install time. The entrypoint, the
skills-sync script and the chrome-devtools MCP are inherited unchanged. Rollback
is trivial: stop using it, the pi TUI image is untouched.

**Run** — same workflow as the TUI, from the repo you want as the workspace:

```sh
cd /path/to/your/repo
/path/to/caged/cg webui start # UI on http://127.0.0.1:8787
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
  pinned global pi (`0.84.4`). The seed config format is compatible and the
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
> `Containerfile.dsh` (build-arg `DSH_VERSION`, default `0.1.2-rc.1`) so a
> release bump is explicit. dsh builds on the repo's shared base image
> `Containerfile.base` (built automatically by the build script), which
> provides apt essentials including `python3`, the glab/gh/jira-cli/cfl CLIs
> and the non-root user — the same CLI tooling pi ships.

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
no compose support anyway. Build and run with `cg`:

```sh
# build (context repo root: builds the shared Containerfile.base first,
# then the dsh image with build-arg DSH_VERSION)
cg dsh build
# run the web UI; opens on the host loopback
cg dsh start
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

The image ships three of the pi agent's four provider routes from
`seed/.pi/agent/models.json` (volcengine was dropped) plus a dsh-only Nube.sh
gateway, tracked in the home settings document
`seed/.dsh/settings.yaml` (the `llm-pi-ai` section; the file is un-ignored
in `seed/.dsh/.gitignore`, and `$DSH_HOME` is the live bind of `seed/.dsh`):

| route | key env / credential ref | protocol |
|---|---|---|
| `DeepSeek-API` | `MY_DEEPSEEK_API_KEY` | openai-completions (`api.deepseek.com`) |
| `my-openrouter` | `MY_OPENROUTER_API_KEY` | openai-completions |
| `justwoker` | `JUSTWOKER_API_KEY` | openai-completions (`api.justwoker.icu/v1`) |
| `local-llm` | `LOCAL_API_KEY` | openai-completions (host `192.168.64.1:8765`; `Coding` / `GLM-5.3-Flash` / `Qwen3.8-flash-next`, 270k/16k) |
| `nube` | `NUBE_KEY` | openai-completions (`ai.nube.sh/api/v1`, model `DeepSeek-V4-Flash` 270k/16k) |

**BYOK works out of the box**: dsh configs reference keys by name
(`apiKeyEnv`, no value ever in config/settings). Users paste their own key in
the Web UI (Settings → Models → card → key field); dsh stores it in
`seed/.dsh/.credentials.yaml` and resolves it per request — no restart, no
operator env needed. An operator-injected env var of the same name (e.g. via
`cg dsh start`) shadows the stored value and renders the
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

Set by `cg dsh start`; it makes the base bundle set
`sandbox/mode: danger-full-access` (bash/fs operations run as uid 1000 with no
dsh-level file confinement) and `approval/policy: never` (no interactive
approval prompts). The agent effectively has the full rights of the `pi` user
inside the container. Override (`DSH_PERMISSION_MODE=workspace-write`, etc.) if
you want dsh's own sandbox + approval back.

#### One-shot headless (no server, prints the answer and exits)

Run with the `container` tool directly, mirroring `cg dsh start` but
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

`cg dsh start` starts the Web UI. It publishes
`127.0.0.1:${DSH_HOST_PORT} -> 3080` via `container run -p` (host
**loopback**, not the LAN), reaching the webserver (which binds `0.0.0.0:3080`
inside the container via `cordis.patch.yml`). The container port is a stable
3080; only `DSH_HOST_PORT` varies. Hardening is the tool's implementable
subset (same as the pi image): `--read-only`, `--cap-drop ALL`, `--tmpfs
/tmp`, pinned memory — no userns / no `--security-opt`. Env knobs: `DSH_IMAGE`,
`DSH_VERSION`, `CAGED_AGENT_HOME`, `CAGED_WORKSPACE`, `DSH_MEMORY` (build:
`CAGED_BASE_IMAGE`, `CAGED_SKIP_BASE`, `GLAB_VERSION`, `JIRA_VERSION`).

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

Override only the host side, e.g. `DSH_HOST_PORT=8080 cg dsh start`.
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
  `cg dsh start` passes `-it` not because dsh is a TUI but
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
  runs `node-gyp rebuild`. The shared base therefore installs the C++ toolchain
  (`python3` and `build-essential`) for both dsh and webui. First build is
  slow; subsequent builds reuse the cached base layer.

- First build needs enough memory for npm's dependency resolution (the whole
  `@deepseek-ai/dsh` tree is large). On a memory-constrained builder, raise it
  (e.g. `container build --memory=6g`, or add `--memory` to the build step).
- `--publish` forwards to the container IP on its **first** network; with the
  default network that is where the webserver binds, so the default path works
  as-is. If you attach dsh to a custom network, keep the publish target in mind.

## Environment knobs

`cg` (forwarding to `scripts/start-container.sh` and
`scripts/build-container.sh pi|dsh|webui` /
`scripts/build-caged-base.sh`) reads these from the calling shell; defaults
listed.

| Env var | Default | Meaning |
|---|---|---|
| `CAGED_IMAGE` | `caged:latest` | image tag to run |
| `CAGED_BASE_IMAGE` | `caged-base:latest` | shared base image tag — built first by `build-caged-base.sh`, imported via FROM in both Containerfiles |
| `CAGED_SKIP_BASE` | `0` | set to `1` to skip the automatic base rebuild when building a derived image |
| `GLAB_VERSION` | `1.112.0` | glab version pin (build time, `build-caged-base.sh`) |
| `GH_VERSION` | `2.97.0` | gh version pin (build time, `build-caged-base.sh`) |
| `JIRA_VERSION` | `1.7.0` | jira-cli version pin (build time, `build-caged-base.sh`) |
| `CFL_VERSION` | `1.3.96` | cfl (Confluence) version pin (build time, `build-caged-base.sh`) |
| `PNPM_VERSION` | `10.15.0` | pnpm version pin (build time, `build-caged-base.sh`) |
| `YARN_VERSION` | `1.22.22` | yarn version pin (build time, `build-caged-base.sh`) |
| `CAGED_WEB_IMAGE` | `caged-webui:latest` | pi-web-ui image tag (build + run of the web mode) |
| `PI_WEB_UI_VERSION` | `0.26.0` | pi-web-ui version pin (build time, `cg webui build`) |
| `CAGED_SKIP_PI` | `0` | set to `1` to skip the pi image build when building `webui` (e.g. it is already current) |
| `PI_WEBUI_HOST_PORT` | `8787` | host-loopback port of the Web UI (`http://127.0.0.1:8787`) |
| `PI_WEBUI_MEMORY` | `4g` | RAM for the web-mode container VM (`CAGED_MEMORY` for the TUI) |
| `CAGED_WORKSPACE` | `$PWD` | host dir mounted at `/workspace` |
| `CAGED_AGENT_HOME` | `./seed` (relative to the repo root) | host dir bind-mounted at `/agent-home` (`$HOME`) — complete shared live agent home |
| `MY_DEEPSEEK_API_KEY` | *(unset)* | DeepSeek provider key (passed into container) |
| `VOLCENGINE_API_KEY` | *(unset)* | Volcengine Ark provider key (passed into container) |
| `MY_OPENROUTER_API_KEY` | *(unset)* | OpenRouter provider key (passed into container) |
| `LOCAL_API_KEY` | *(unset)* | Local LLM provider key (passed into container) |
| `NUBE_KEY` | *(unset)* | Nube.sh gateway provider key (`ai.nube.sh/api/v1`, dsh mode) |
| `JUSTWOKER_API_KEY` | *(unset)* | JustWoker gateway provider key (`api.justwoker.icu`, pi mode) |
| `GITLAB_TOKEN` | *(unset)* | `glab` (GitLab CLI) API token (passed into container) |
| `GITLAB_HOST` | *(unset)* | `glab` GitLab instance host (default `https://gitlab.com`) |
| `GH_TOKEN` | *(unset)* | `gh` (GitHub CLI) API token (passed into container) |
| `GH_HOST` | *(unset)* | `gh` GitHub Enterprise host (default `github.com`) |
| `JIRA_API_TOKEN` | *(unset)* | `jira` (jira-cli) API token (passed into container); if unset, derived from `CFL_API_TOKEN` at start — the two are the same Atlassian token |
| `CFL_URL` | *(unset)* | `cfl` (Confluence) site URL, e.g. `https://your-site.atlassian.net` (passed into container) |
| `CFL_EMAIL` | *(unset)* | `cfl` (Confluence) login email (passed into container) |
| `CFL_API_TOKEN` | *(unset)* | `cfl` (Confluence) API token — the same Atlassian token as `JIRA_API_TOKEN` (passed into container); if unset, derived from `JIRA_API_TOKEN` at start |
| `ATLASSIAN_HOST` | *(unset)* | Shared Atlassian site host, e.g. `your-site.atlassian.net` (start-container.sh maps it to `CFL_URL`/`JIRA_SERVER` at launch, adding `https://` to a bare host) |
| `ATLASSIAN_EMAIL` | *(unset)* | Shared Atlassian login email (start-container.sh maps it to `CFL_EMAIL`/`JIRA_LOGIN` at launch) |
| `ATLASSIAN_API_TOKEN` | *(unset)* | Shared Atlassian API token (start-container.sh maps it to `CFL_API_TOKEN`/`JIRA_API_TOKEN` at launch — same token as `JIRA_API_TOKEN`/`CFL_API_TOKEN`) |

> dsh's dedicated knobs — `DSH_IMAGE`, `DSH_VERSION`, `DSH_HOST_PORT`,
> `DSH_MEMORY`, `DSH_PERMISSION_MODE` — are documented in the
> [dsh (DeepSeek Harness)](#dsh-deepseek-harness) section.

## Runtime hardening (applied by `cg start` → scripts/start-container.sh)

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
* The pi version is pinned via `ARG PI_VERSION` (default `0.84.4`). Rebuild a
  specific version with `PI_VERSION=x.y.z cg pi build`. (We
  deliberately don't quote a number here — the project is still iterating.)
* The web mode (`caged-webui`) bundles its own pi SDK copy (`^0.83`), which
  can lag the pinned global pi — config format is compatible, they don't
  interfere; see [pi-web-ui (Web UI)](#pi-web-ui-web-ui).

## License / notes

Internal project. Built with Apple's `container` tool on Apple silicon macOS.
The image itself remains a plain OCI image, so it can also be run directly
under podman/docker (with equivalent hardening flags) if you're not on Apple
silicon — see docs/APPLE-CONTAINER.md.
