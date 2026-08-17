# Apple `container` — alternative runtime

caged's reference runtime is podman/docker **compose** (`compose.yaml`). On
Apple silicon Macs you can instead run the same stack with Apple's native
[`container`](https://github.com/apple/container) tool — Linux containers as
lightweight VMs, optimized for Apple silicon. It has **no compose support**,
and its build-context indexing mishandles the classic deep-negation
`.dockerignore` form, so this path is two scripts plus an adjusted
`.dockerignore`:

| What | podman / docker | Apple `container` |
|---|---|---|
| Build image | `podman compose build` | `scripts/build-container.sh` |
| Run (TUI) | `podman compose -f compose.yaml run --rm pi` | `scripts/start-container.sh` |

Both scripts honor the same env knobs as compose (`CAGED_IMAGE`,
`CAGED_WORKSPACE`, `CAGED_PI_HOME`) plus `CONTAINER_NAME` (default
`caged-pi`), and pass the provider/CLI keys from the caller's environment
exactly like `compose.yaml`'s `environment:` block.

## `.dockerignore`: per-level negation

`seed/` must stay out of the build context except one file: the Containerfile
COPYs `seed/.pi/agent/skills.json` at build time to drive the build-time
skill clone. The obvious way to write that is the collapsed deep-negation
form:

```dockerignore
seed/
!seed/.pi/
!seed/.pi/agent/
!seed/.pi/agent/skills.json
```

`container build`'s context indexer doesn't honor it — the `!` entries never
re-include the file, so `skills.json` never reaches the build and the
build-time clone breaks. The per-level ignore/re-include form works on both
engines and is what the repo ships:

```dockerignore
seed/*
!seed/.pi/
seed/.pi/*
!seed/.pi/agent/
seed/.pi/agent/*
!seed/.pi/agent/skills.json
```

Don't "simplify" it back to the collapsed form — it regresses the Apple
path.

## The two scripts

- **`scripts/build-container.sh`** — `container build` with the project root
  as context and an absolute Containerfile path (works from any cwd);
  `PI_VERSION` build-arg, same default as compose.
- **`scripts/start-container.sh`** — `container run` translating
  compose.yaml's `run` semantics: the same three mounts (`/workspace`, the
  live seed `~/.pi`, per-project `sessions`), the same environment, and the
  hardening flags the tool supports (`--read-only`, `--cap-drop ALL`,
  `--tmpfs /tmp`, `-it`). It also adds three things compose handles for you:
  1. a **fail-fast host-side seed check** (`models.json` present) before
     starting,
  2. **pre-creates `$WORKSPACE_HOST/.pi/sessions`** (podman-compose creates it on
     demand),
  3. **stops a leftover same-name container** (`container stop` — SIGTERM, 5s
     timeout) before running.

## Reaching host services

`models.json` points the `local-llm` provider at
`http://192.168.64.1:8765/v1`, and `start-chrome-devtools-mcp.sh` defaults
its forwarder to `192.168.64.1:9222`. **`192.168.64.1` is the vmnet gateway
of the `container` default network — the host's bridge interface as seen
from inside every container** (it's the containers' default route, so it's
reachable with no DNS, pf, or sudo setup, and it survives reboots). Verify
it once on your machine:

```bash
container run -it --rm alpine ip route   # default gateway = 192.168.64.1
```

The one requirement is that the **host services listen on that address**,
not just loopback:

- `caddy-dev-server` (the local LLM proxy) must listen on
  `192.168.64.1:8765` (e.g. Caddyfile `192.168.64.1:8765`). The gateway IP
  is only visible to container VMs — binding it does **not** expose the
  service to your LAN; avoid `0.0.0.0` for that reason.
- Chrome's CDP port binds `127.0.0.1` only on macOS, so bridge it to the
  gateway IP: `socat TCP-LISTEN:192.168.64.1:9222,fork TCP:127.0.0.1:9222 &`
  (Chrome still runs with `--remote-debugging-port=9222` as usual).
- macOS's Application Firewall may block incoming connections on
  non-loopback addresses — allow `caddy`/`socat` if the probe below
  connects but containers get refused.

`start-container.sh` probes `192.168.64.1:8765` at startup (warns, doesn't
fail) when `LOCAL_API_KEY` is set.

Why not a hostname? apple/container has no `--add-host` and won't resolve
`host.docker.internal` or `host.container.internal` without the documented
`container system dns create --localhost` + `[dns] domain` machinery (sudo,
pf rules that die on reboot, Private Relay caveats — see
[apple/container#673](https://github.com/apple/container/issues/673) and
[#346](https://github.com/apple/container/issues/346)). A static IP avoids
all of it.

### podman/docker (compose) compatibility — deferred

`models.json` is shared between the Apple and compose runtimes, and pi does
not interpolate env vars in `baseUrl`, so the single static value above
targets the Apple vmnet gateway; the compose/podman path currently can't
reach it. To implement later: map a stable host address in `compose.yaml`
(Docker Desktop's `host.docker.internal` or podman's `host.containers.internal`
with `extra_hosts: host-gateway`) and bind caddy per runtime. Not done yet,
by design.

## Deliberate divergences from compose.yaml

Compatibility-driven, not oversights. Keep them in mind when diffing the
script against compose:

| compose.yaml | start-container.sh | Why / consequence |
|---|---|---|
| `init: true` (podman init as PID 1) | omitted | **No loss here**: the image's entrypoint already `exec tini -s --` as PID 1 (`scripts/entrypoint.sh`), which reaps children and forwards signals. `container run --init` exists if you want the outer init too. |
| `tmpfs: /tmp:rw,noexec,nosuid,size=512m` | `--tmpfs /tmp` | The tool's `--tmpfs` takes only a path — **no size cap, no `noexec`/`nosuid`** on the Apple path |
| `security_opt: no-new-privileges` | omitted | **No `--security-opt` in the tool** — the no-setuid-escalation layer is lost on this path |
| `userns_mode: keep-id` | omitted | **No userns support** — the guest runs as the host user directly, so uid remap is neither possible nor needed |

Net security posture vs podman: `--cap-drop ALL`, non-root, and the
read-only rootfs still apply; the two lost layers (`no-new-privileges`,
userns keep-id) make the Apple path **slightly less hardened**. podman
remains the reference posture — see [SECURITY.md](SECURITY.md).

## Resource defaults

The guest is a VM with **1 GB RAM / 4 CPUs by default**, and the BuildKit
builder builds with **2 CPUs / 2 GB**. The scripts don't override
`--memory`/`--cpus`. If pi or a workspace build feels slow (or pi OOMs),
raise them, e.g. `container run ... --memory 8g --cpus 8` (or edit
`start-container.sh`).

## Keeping them in sync

`compose.yaml` is the reference: when its volumes or `environment:` list
change, mirror the change in `start-container.sh`.
