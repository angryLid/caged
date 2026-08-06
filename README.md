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
├── Containerfile        # image definition (non-root, pinned pi version)
├── compose.yaml         # the single runtime entry (podman compose / podman-compose)
├── seed/                # pi's home (~/.pi) — LIVE bind-mount source for $HOME
│   └── .pi/agent/       # models.json (providers), settings.json, mcp.json,
│                        # AGENTS.md, skills/, scripts/ (CDP helpers)
├── scripts/
│   ├── entrypoint.sh    # seed validation (fail-fast) + tini, runs as USER pi
│   └── skills-sync.mjs  # declarative skills sync (see `## Skills (“skills-sync”)`)
└── docs/SECURITY.md     # threat model & accepted trade-offs
```

## Skills (“skills-sync”)

This project ships a small **declarative** mechanism for pulling in external
agent skills and enabling a subset of them — see `skills.json` at the repo
root. It is tool-agnostic (works with any agent that reads skills from a
directory).

Skills are installed **into the seed** (`seed/.pi/agent/skills/`), pi's live
config home that is bind-mounted at `/agent-home/.pi/agent` at runtime. The
repos are cloned into `seed/.pi/agent/skills-sync/vendor/` and each enabled
skill is exposed as a relative symlink in `seed/.pi/agent/skills/` pointing
back into that vendor dir. Keeping the repos inside the seed means the
relative links stay valid inside the container's mount layout (everything
under `/agent-home/.pi/agent`).

Because the seed is bind-mounted (not baked into the image) the sync runs at
**container start** — the entrypoint calls the script with `--seed
/agent-home/.pi/agent` before launching pi (best-effort; a network hiccup or
missing config just logs a warning and pi still starts). You can also run it
by hand, e.g. after editing `skills.json`:

```bash
node scripts/skills-sync.mjs            # clone/pull repos + (re)link into seed/.pi/agent/skills
node scripts/skills-sync.mjs --dry-run  # preview without changing anything
```

- **`skills.json`** — the source of truth: a `repos[]` list (each with a URL,
  `skillsDir`, and an `enabled` list of skill relative paths) plus a
  `linkTargets[]` list of dirs, relative to the seed, to place symlinks
  (default `skills` → `seed/.pi/agent/skills`).
- The script **clones** each repo into `seed/.pi/agent/skills-sync/vendor/<name>`
  (or `git pull`s it), then creates **relative symlinks** into each link
  target. Stale links are removed, so dropping a skill from `enabled` unlinks it.
  Hand-written skills committed in `seed/.pi/agent/skills/` (bgm-metadata,
  caged-persistence, create-post, markdown-link, mdx-notes, skills-sync) are
  never touched.
- `seed/.pi/agent/skills-sync/vendor/` and the generated skill symlinks are
  **gitignored** and regenerated at every container start — edit `skills.json`,
  then re-run the script (or restart the container).

> pi can also run this for you: ask it to “sync skills” (uses the `skills-sync` skill).

## Quickstart

Requirements: podman >= 4 on macOS (or docker with `userns_mode` support) plus
`podman-compose` (`brew install podman-compose`).

```sh
# 1. build (only needed the first time, or when the Containerfile changes —
#    compose auto-builds when the image is missing; force with
#    `podman compose ... build --no-cache`)
cd caged && podman compose build

# 2. interactive TUI — run from the repo you want as the workspace.
#    Prefer `run` over `up`: podman-compose's `up` doesn't forward terminal
#    size/SIGWINCH or TERM on macOS, which garbles pi's full-screen TUI.
#    `run` shells out to `podman run -it` and forwards the terminal properly.
cd /path/to/your/repo
podman compose -f /path/to/caged/compose.yaml run --rm pi

# 3. one-shot (non-interactive) run:
podman compose -f /path/to/caged/compose.yaml run --rm pi pi --print "refactor this module"
```

Both commands mount the **directory you run them from** as `/workspace`.

> **TUI looks jagged/aliased?** (podman-compose 1.x `up` only) — that's a known
> podman-compose TTY limitation: it creates a pty but never forwards the
> terminal size or TERM. Fix: use `run` (above), or run the equivalent
> `podman run -it` one-liner from [docs/SECURITY.md](docs/SECURITY.md)
> (verify block) with your mounts. Resizing the terminal window once also
> often snaps the renderer back into place.

## What gets mounted

| Path in container | Backing | Read/write | Purpose |
|---|---|---|---|
| `/workspace`   | dir you ran `compose` from, or `$CAGED_WORKSPACE` | rw | **the code pi works on** |
| `/agent-home/.pi` (`~/.pi`) | `<caged>/seed/.pi` (`$CAGED_PI_HOME`) | rw | **pi's live config home** — maps 1:1 to `seed/.pi`; everything pi configures lands back on the host |
| `/agent-home/.pi/agent` | *(part of the mount above)* — `seed/.pi/agent` | rw | pi's config dir (`models.json`, `settings.json`, `mcp.json`, `AGENTS.md`, `skills/`) |
| `/agent-home/.pi/agent/sessions` | `$CAGED_WORKSPACE/sessions` on the host | rw | **pi session data — per-project, on the host** |

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

**Session data lives per-project on the host** as a nested mount
(`/agent-home/.pi/agent/sessions` is masked by it): when you run `caged compose
… up` from `~/folder`, pi's sessions are written to `~/folder/sessions/`
(podman-compose creates the directory if missing). Deleting `seed/.pi/agent`
or `auth.json` does **not** touch your sessions or your API keys' cached
auth.

## Seed config (`seed/`)

`seed/.pi/` mirrors pi's config home `~/.pi` on the host and is mounted live
(not baked into the image):

* `.pi/agent/models.json` — providers: **DeepSeek**, **Volcengine Ark Coding**
  (minimax-m3 / doubao-seed / glm-5.2), **OpenRouter**, **Local** (private,
  env-configured base URL + key)
* `.pi/agent/settings.json` — trust + `pi-mcp-adapter` extension
* `.pi/agent/mcp.json` — chrome-devtools MCP (needs host Chrome on `:9222`, optional)
* `.pi/agent/skills/` — caged-persistence, create-post, bgm-metadata, markdown-link, mdx-notes
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
`caddy-dev-server` proxy `http://host.docker.internal:8765/v1`, which
forwards to the internal LLM gateway with the Host header rewritten to
the upstream hostname (that hostname lives only in the host's Caddyfile,
never in this repo). Pass the keys when starting:

```sh
MY_DEEPSEEK_API_KEY=sk-... VOLCENGINE_API_KEY=ark-... \
  LOCAL_API_KEY=... \
  podman compose -f /path/to/caged/compose.yaml up
```

For interactive TUI auth flows that don't use `models.json`, pi stores
credentials in `auth.json` inside the agent dir:

pi stores credentials in `auth.json` inside the agent dir
(`/agent-home/.pi/agent/auth.json` on the volume). Two options:

```sh
podman compose -f /path/to/caged/compose.yaml run --rm pi pi auth
```

Never put API keys in `/workspace` — anything there is readable by pi.

## chrome-devtools MCP

`seed/.pi/agent/mcp.json` registers a chrome-devtools MCP server. It forwards
the container-local port `19222` to the host's Chrome CDP and requires:

1. Host Chrome running with `--remote-debugging-port=9222`
2. `host.docker.internal` resolvable from the container (podman on macOS
   provides it)

Without host Chrome listening, pi will report the MCP server as unavailable —
that's expected, not a caged bug.

## glab (GitLab CLI)

[`glab`](https://gitlab.com/gitlab-org/cli) — the official GitLab CLI — is
baked into the image (v1.112.0, pinned `ARG GLAB_VERSION` in the
Containerfile, sha256-verified against the official checksums). Use it for
MRs, issues, pipelines, releases, etc. instead of hand-rolled curl against
the GitLab API.

Auth follows the same env-only pattern as the model provider keys — pass a
token when starting, it never lives in the repo:

```sh
GITLAB_TOKEN=glpat-... \
  podman compose -f /path/to/caged/compose.yaml run --rm pi glab issue list
```

For a self-hosted instance also set `GITLAB_HOST=https://gitlab.example.com`.
`XDG_CONFIG_HOME` is pointed at `/tmp` because `~/.config` is on the
read-only rootfs; `glab auth login` output therefore does **not** survive a
container restart — the env token is the supported path.

## acli (Atlassian CLI)

[`acli`](https://developer.atlassian.com/cloud/acli/) — Atlassian's official
command line interface (Jira Cloud, Confluence, Bitbucket, admin APIs) — is
baked into the image (v1.3.22, pinned `ARG ACLI_VERSION` in the
Containerfile). Atlassian only publishes `latest`-style URLs, so the pin is
enforced via the versioned `.deb` filename + the sha256 taken from
Atlassian's own apt repo `Packages` index, mirroring the `glab` pattern.

Authenticate with an API token (created at
`id.atlassian.com/manage-profile/security/api-tokens`) read from stdin:

```sh
echo "$JIRA_API_TOKEN" | \
  podman compose -f /path/to/caged/compose.yaml run --rm pi \
    acli jira auth login --site "mysite.atlassian.net" --email you@example.com --token
```

`ACLI_CONFIG_DIR` points at `/agent-home/.pi/agent/acli` — on the live
`~/.pi` mount, so login state survives restarts while the token stays out of
git (`seed/.pi/agent/acli/` is ignored, like `auth.json`). No secret env var
is needed; unlike `glab` there is no env-token passthrough, so authenticating
once per setup is the supported path.

## Environment knobs

`compose.yaml` interpolates these from the calling shell; defaults listed.

| Env var | Default | Meaning |
|---|---|---|
| `CAGED_IMAGE` | `caged:latest` | image tag to run |
| `CAGED_WORKSPACE` | `$PWD` | host dir mounted at `/workspace` |
| `CAGED_PI_HOME` | `./seed/.pi` (relative to the compose file) | host dir bind-mounted at `/agent-home/.pi` (`~/.pi`) — live seed: `seed/.pi` == `~/.pi`, synced both ways |
| `MY_DEEPSEEK_API_KEY` | *(unset)* | DeepSeek provider key (passed into container) |
| `VOLCENGINE_API_KEY` | *(unset)* | Volcengine Ark provider key (passed into container) |
| `MY_OPENROUTER_API_KEY` | *(unset)* | OpenRouter provider key (passed into container) |
| `LOCAL_API_KEY` | *(unset)* | Local LLM provider key (passed into container) |
| `GITLAB_TOKEN` | *(unset)* | `glab` (GitLab CLI) API token (passed into container) |
| `GITLAB_HOST` | *(unset)* | `glab` GitLab instance host (default `https://gitlab.com`) |

## Runtime hardening (applied by compose.yaml)

* `--read-only` — root filesystem immutable (only `/workspace`, `~/.pi` (`/agent-home/.pi`), and `/tmp` writable)
* `--tmpfs /tmp` — scratch, `noexec,nosuid`
* `--cap-drop ALL` — container process gets zero kernel capabilities
* `--security-opt no-new-privileges` — no setuid-style privilege escalation
* `--userns=keep-id` — stays UID 1000, maps cleanly to your host user

See [docs/SECURITY.md](docs/SECURITY.md) for the detailed threat model and the
explicitly accepted risks (open network, rw workspace).

## Known limitations

* Running on macOS: podman runs inside a Linux VM, so `/workspace` bind-mount
  performance matters for large repos — see the earlier discussion about
  small-file I/O. `npm install` in the workspace will be slower than native.
* The image is pinned to `@earendil-works/pi-coding-agent@0.83.0`; bump
  `ARG PI_VERSION` in the `Containerfile` and rebuild to upgrade.

## License / notes

Internal project. Built for podman 6.x on macOS; should work on any podman >= 4
or docker with `userns_mode` support.
