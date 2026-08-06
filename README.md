# caged

Hardened podman/docker container to run
[`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
(`pi`) safely against your code.

> **What caged is**: a minimal, locked-down runtime for an AI coding agent that
> can execute arbitrary bash commands. Non-root user, read-only rootfs,
> no capabilities, no extra privileges, one disposable volume for all state.
>
> **What caged explicitly is NOT**: a network sandbox. pi needs open networking
> to reach model providers — that part is on purpose. See
> [SECURITY.md](docs/SECURITY.md) for the full threat model.

## Layout

```
caged/
├── Containerfile        # image definition (non-root, pinned pi version)
├── compose.yaml         # the single runtime entry (podman compose / podman-compose)
├── seed/                # pi "global config" (~/.pi) — baked into the image,
│   │                    # copied into a fresh /pi-agent volume on first run
│   └── agent/           # models.json (providers), settings.json, mcp.json,
│                        # AGENTS.md, skills/; + devtools-forward.js, start-chrome-devtools-mcp.sh
├── scripts/
│   └── entrypoint.sh    # volume bootstrap + tini, runs as USER pi
└── docs/SECURITY.md     # threat model & accepted trade-offs
```

## Quickstart

Requirements: podman >= 4 on macOS (or docker with `userns_mode` support) plus
`podman-compose` (`brew install podman-compose`).

```sh
# 1. build (first run or after seed/ changes — compose auto-builds when the
#    image is missing; force with `podman compose ... build --no-cache`)
cd caged && podman compose build

# 2. interactive TUI — run from the repo you want as the workspace:
cd /path/to/your/repo
podman compose -f /path/to/caged/compose.yaml up

# 3. one-shot (non-interactive) run:
podman compose -f /path/to/caged/compose.yaml run --rm pi pi --print "refactor this module"
```

Both commands mount the **directory you run them from** as `/workspace`.

## What gets mounted

| Path in container | Backing | Read/write | Purpose |
|---|---|---|---|
| `/workspace`   | dir you ran `compose` from, or `$CAGED_WORKSPACE` | rw | **the code pi works on** |
| `/pi-agent`    | named volume `$CAGED_VOLUME` (default `caged-pi-agent`) | rw | pi home (`~/.pi`: config, auth, downloaded tooling) |
| `/pi-agent/.pi/agent/sessions` | `$CAGED_WORKSPACE/sessions` on the host | rw | **pi session data — per-project, on the host** |

Named volume `caged-pi-agent` persists between runs. On first use of a *fresh*
empty volume, podman copies the contents of `/pi-agent` from the image — the
seed — into it. `podman volume rm caged-pi-agent` wipes it, and the next run
re-seeds from the image.

**Session data lives per-project on the host**, not in the volume: when you run
`caged compose … up` from `~/folder`, pi's sessions are written to
`~/folder/sessions/` (podman-compose creates the directory if missing). So each
project keeps its own session history next to the code — `~/folder/sessions`.
`podman volume rm caged-pi-agent` therefore **does not** delete your sessions;
only the config/auth/tools volume is affected.

## Seed config (`seed/`)

`seed/` mirrors pi's `~/.pi` home and ships in the image:

* `agent/models.json` — providers: **DeepSeek**, **Volcengine Ark Coding**
  (minimax-m3 / doubao-seed / glm-5.2), **OpenRouter**, **Local** (private,
  env-configured base URL + key)
* `agent/settings.json` — trust + `pi-mcp-adapter` extension
* `agent/mcp.json` — chrome-devtools MCP (needs host Chrome on `:9222`, optional)
* `agent/skills/` — caged-persistence, create-post, bgm-metadata, markdown-link, mdx-notes
* `agent/AGENTS.md` — environment primer pi loads for the container
* `devtools-forward.js`, `start-chrome-devtools-mcp.sh` — CDP helpers

To change the shipped config, edit `seed/` and rebuild; the live volume
(.e.g. `/pi-agent/.pi`) is what pi actually reads.

## Provider keys

`models.json` references keys by env var name (`$MY_DEEPSEEK_API_KEY`,
`$VOLCENGINE_API_KEY`, `$MY_OPENROUTER_API_KEY`, and for the local
provider `$LOCAL_API_KEY` + `$LOCAL_LLM_BASE_URL`); pi expands these from
the container environment at runtime. Pass them when starting:

```sh
MY_DEEPSEEK_API_KEY=sk-... VOLCENGINE_API_KEY=ark-... \
  LOCAL_API_KEY=... LOCAL_LLM_BASE_URL=http://... \
  podman compose -f /path/to/caged/compose.yaml up
```

For interactive TUI auth flows that don't use `models.json`, pi stores
credentials in `auth.json` inside the agent dir:

pi stores credentials in `auth.json` inside the agent dir
(`/pi-agent/agent/auth.json` on the volume). Two options:

```sh
podman compose -f /path/to/caged/compose.yaml run --rm pi pi auth
```

Never put API keys in `/workspace` — anything there is readable by pi.

## chrome-devtools MCP

`seed/agent/mcp.json` registers a chrome-devtools MCP server. It forwards the
container-local port `19222` to the host's Chrome CDP and requires:

1. Host Chrome running with `--remote-debugging-port=9222`
2. `host.docker.internal` resolvable from the container (podman on macOS
   provides it)

Without host Chrome listening, pi will report the MCP server as unavailable —
that's expected, not a caged bug.

## Environment knobs

`compose.yaml` interpolates these from the calling shell; defaults listed.

| Env var | Default | Meaning |
|---|---|---|
| `CAGED_IMAGE` | `caged:latest` | image tag to run |
| `CAGED_WORKSPACE` | `$PWD` | host dir mounted at `/workspace` |
| `CAGED_VOLUME` | `caged-pi-agent` | named volume mounted at `/pi-agent` |
| `MY_DEEPSEEK_API_KEY` | *(unset)* | DeepSeek provider key (passed into container) |
| `VOLCENGINE_API_KEY` | *(unset)* | Volcengine Ark provider key (passed into container) |
| `MY_OPENROUTER_API_KEY` | *(unset)* | OpenRouter provider key (passed into container) |
| `LOCAL_API_KEY` | *(unset)* | Local LLM provider key (passed into container) |
| `LOCAL_LLM_BASE_URL` | *(unset)* | Local LLM base URL, e.g. `http://llm.local/v1` (passed into container) |

## Runtime hardening (applied by compose.yaml)

* `--read-only` — root filesystem immutable (only `/workspace`, `/pi-agent`, `/tmp` writable)
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
