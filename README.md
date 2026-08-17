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
* **Atlassian CLI (`acli` v1.3.22)** — official Atlassian CLI baked in:
  **Jira Cloud** work items, projects, admin APIs (also Confluence &
  Bitbucket). API-token login; state survives restarts.
* **Chrome DevTools MCP extension** — pi can drive your host Chrome through
  the chrome-devtools MCP server (browse, search, screenshots, JS
  evaluation). Optional: needs host Chrome listening on `:9222`.
* **Multiple LLM providers** — DeepSeek, Volcengine Ark, OpenRouter, plus a
  private local gateway; keys are passed via environment variables, never
  baked into the image or committed to the repo.
* **Live seed config** — pi's entire `~/.pi` is a two-way bind mount of
  `seed/`: edit configs in this repo and they take effect on the next
  container start — no image rebuild.
* **Open networking** — deliberate, so pi can reach model providers and the
  internet (see [docs/SECURITY.md](docs/SECURITY.md) for the trade-offs).

## Layout

```
caged/
├── Containerfile        # pi image (non-root, pinned pi version)
├── Containerfile.base   # shared base for both images: apt essentials, glab, acli, non-root user
├── Containerfile.dsh    # OPTIONAL: DeepSeek Harness (`@deepseek-ai/dsh`) image
├── seed/                # agent homes — LIVE bind-mount sources
│   ├── .pi/agent/       # pi's ~/.pi: models.json (providers), settings.json,
│   │                    #   mcp.json, AGENTS.md, skills.json, skills/, scripts/
│   └── .dsh/            # dsh's $DSH_HOME: cordis.patch.yml + generated config
├── scripts/
│   ├── build-caged-base.sh  # shared base image build (Containerfile.base) — built automatically by the one below
│   ├── build-container.sh   # Apple `container` build:  build-container.sh pi|dsh  (arg required, no default)
│   ├── start-container.sh   # Apple `container` run (interactive pi TUI)
│   ├── dsh-start-container.sh # same, for dsh (Web UI on host loopback)
│   ├── entrypoint.sh        # pi seed validation (fail-fast) + tini, runs as USER pi
│   ├── dsh-entrypoint.sh    # dsh seed validation + tini
│   ├── dsh-ensure-workspace.mjs # dsh: register /workspace as Web default
│   └── skills-sync.mjs      # declarative skills sync (see `## Skills (“skills-sync”)`)
├── README.dsh.md        # dsh docs: build/run, port mapping, security notes
└── docs/
    ├── SECURITY.md           # threat model & accepted trade-offs
    ├── CLI-AUTH.md           # glab/acli auth behavior, persistence & risks
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
#    shared base image (Containerfile.base: apt essentials, glab, acli,
#    non-root user) is built automatically first. Optionally pick a pi
#    version:   PI_VERSION=x.y.z scripts/build-container.sh pi
scripts/build-container.sh pi

# 2. interactive TUI — run from the repo you want as the workspace, then
#    start the disposable container. It mounts the directory you run it from
#    as /workspace and drops you into pi's TUI.
cd /path/to/your/repo
/path/to/caged/scripts/start-container.sh
```

`start-container.sh` mounts the **directory you run it from** as `/workspace`.

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
| `/agent-home/.pi` (`~/.pi`) | `<caged>/seed/.pi` (`$CAGED_PI_HOME`) | rw | **pi's live config home** — maps 1:1 to `seed/.pi`; everything pi configures lands back on the host |
| `/agent-home/.pi/agent` | *(part of the mount above)* — `seed/.pi/agent` | rw | pi's config dir (`models.json`, `settings.json`, `mcp.json`, `AGENTS.md`, `skills/`) |

`$HOME` is `/agent-home` and only `~/.pi` (`/agent-home/.pi`) is a live bind mount
of `caged/seed/.pi` — one level of indirection below `$HOME`, so the repo tree
only ever reflects pi's config home, never stray `$HOME` state. Whatever pi
writes under `~/.pi` (settings, models, mcp.json, skills, even `auth.json`)
lands directly in the repo tree. There is **no baked-in config inside the
image** and no fresh-volume seeding step — the seed *is* the live config.
Iterate on seed files and they take effect on the *next* container start —
no image rebuild required.

The rest of `$HOME` stays read-only (rootfs): home-derived caches are pointed
at the `/tmp` tmpfs (`npm_config_cache`, `XDG_CACHE_HOME`), keeping the
container stateful-free apart from the two mounts and scratch.

The entrypoint validates the mount **before** launching pi: if the seed is
missing or incomplete, `mcp.json` references a missing executable, or the
seed is read-only, it exits non-zero with a diagnostic instead of letting pi
run half-configured. This also catches a wrong `$CAGED_PI_HOME` — e.g. an
old value that pointed at a higher-level dir (a dangling `~/.pi/agent` fails
the required-files check immediately).

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
  `/agent-home/.pi/agent/glab-cli` on the live `~/.pi` mount, so
  `glab auth login` state survives container restarts (gitignored, like
  `acli` and `auth.json`):

  ```sh
  echo "$GITLAB_TOKEN" | scripts/start-container.sh
  # then pipe the same token into  glab auth login ...  inside the TUI
  ```

  Run from any directory (the workspace can be a throwaway dir). The token is
  stored as plaintext (`0600`, gitignored) — the trade-offs are analysed in
  [docs/CLI-AUTH.md](docs/CLI-AUTH.md).

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

`ACLI_CONFIG_DIR` points at `/agent-home/.pi/agent/acli` — on the live
`~/.pi` mount, so login state survives restarts while the token stays out of
git (`seed/.pi/agent/acli/` is ignored, like `auth.json`). No secret env var
is needed; unlike `glab` there is no env-token passthrough, so authenticating
once per setup is the supported path. Auth behavior and pitfalls for both
CLIs: [docs/CLI-AUTH.md](docs/CLI-AUTH.md).

## Environment knobs

`scripts/start-container.sh` (and `scripts/build-container.sh pi|dsh` /
`scripts/build-caged-base.sh`) read these from the calling shell; defaults
listed.

| Env var | Default | Meaning |
|---|---|---|
| `CAGED_IMAGE` | `caged:latest` | image tag to run |
| `CAGED_BASE_IMAGE` | `caged-base:latest` | shared base image tag — built first by `build-caged-base.sh`, imported via FROM in both Containerfiles |
| `CAGED_SKIP_BASE` | `0` | set to `1` to skip the automatic base rebuild when building a derived image |
| `GLAB_VERSION` | `1.112.0` | glab version pin (build time, `build-caged-base.sh`) |
| `ACLI_VERSION` | `1.3.22` | acli version pin (build time, `build-caged-base.sh`) |
| `CAGED_WORKSPACE` | `$PWD` | host dir mounted at `/workspace` |
| `CAGED_PI_HOME` | `./seed/.pi` (relative to the repo root) | host dir bind-mounted at `/agent-home/.pi` (`~/.pi`) — live seed: `seed/.pi` == `~/.pi`, synced both ways |
| `MY_DEEPSEEK_API_KEY` | *(unset)* | DeepSeek provider key (passed into container) |
| `VOLCENGINE_API_KEY` | *(unset)* | Volcengine Ark provider key (passed into container) |
| `MY_OPENROUTER_API_KEY` | *(unset)* | OpenRouter provider key (passed into container) |
| `LOCAL_API_KEY` | *(unset)* | Local LLM provider key (passed into container) |
| `GITLAB_TOKEN` | *(unset)* | `glab` (GitLab CLI) API token (passed into container) |
| `GITLAB_HOST` | *(unset)* | `glab` GitLab instance host (default `https://gitlab.com`) |

## Runtime hardening (applied by scripts/start-container.sh)

* `--read-only` — root filesystem immutable (only `/workspace`, `~/.pi` (`/agent-home/.pi`), and `/tmp` writable)
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

## License / notes

Internal project. Built with Apple's `container` tool on Apple silicon macOS.
The image itself remains a plain OCI image, so it can also be run directly
under podman/docker (with equivalent hardening flags) if you're not on Apple
silicon — see docs/APPLE-CONTAINER.md.
