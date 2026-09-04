# Apple `container` — the runtime

caged runs a **single disposable container whose only job is isolation**, so
container orchestration is unnecessary — and Apple's own native
[`container`](https://github.com/apple/container) tool (Linux containers as
lightweight VMs, optimized for Apple silicon) has **no compose support**
anyway, which fits. The runtime is therefore three scripts (build, base, run).

| What | Command |
|---|---|
| Build image | `cg pi build` (`dsh` / `webui` / `cmdc` for the other images) |
| Run (all modes) | `cg pi start` / `cg webui start` / `cg dsh start` / `cg cmdc start` |

`cg` is the unified launcher (replacing the old root-level `build.sh` /
`start.sh`): `cg <agent> <start|build>`, with extra arguments passed through
to the underlying scripts.


The scripts honor the env knobs `CAGED_IMAGE`, `CAGED_WORKSPACE` and
`CAGED_AGENT_HOME` plus `CONTAINER_NAME` (default `caged-pi`), and pass the
provider/CLI keys from the caller's environment. The complete `seed` is
mounted at `/agent-home` for all modes, including shared CLI auth.

## `.dockerignore`: keep `seed/` out entirely

The build context excludes `seed/` wholesale — no Containerfile COPYs anything
out of the seed. The git skill sources are cloned on the **host** into
`seed/skills-sync/vendor/` by `scripts/build-caged-base.sh`, and every other
seed file (agent homes, `skills.json`, `prompts.json`, `skills-src/`,
`prompt-src/`) reaches a container through the live bind mount at
`/agent-home`.

Keep it that way. If you ever do need one seed file inside an image, note that
`container build`'s context indexer does **not** honor the collapsed
deep-negation form — the `!` entries never re-include the file:

```dockerignore
seed/
!seed/.pi/
!seed/.pi/agent/
!seed/.pi/agent/some.json
```

Only the verbose per-level ignore/re-include form works on both engines:

```dockerignore
seed/*
!seed/.pi/
seed/.pi/*
!seed/.pi/agent/
seed/.pi/agent/*
!seed/.pi/agent/some.json
```

The repo previously shipped exactly that to smuggle `skills.json` into the
build; moving the clone to the host removed the need, which is the simpler
end state — don't reintroduce a seed `COPY` without also reintroducing the
verbose form.

## The scripts

- **`scripts/build-container.sh pi|dsh|webui`** (invoked by `cg <agent> build`) — `container build` with the project
  root as context and an absolute Containerfile path (works from any cwd). The
  image is a required argument (`pi` → `./Containerfile`, `dsh` →
  `./Containerfile.dsh`, `webui` → `./Containerfile.webui`); a build without
  one fails. Per-image build args:
  `PI_VERSION` (default `0.84.4`) for pi, `DSH_VERSION` (default
  `0.1.2-rc.1`) for dsh, `PI_WEB_UI_VERSION` (default `0.26.0`) for webui.
  The `webui` target builds the pi image first (`Containerfile.webui` is
  `FROM caged:latest`); skip with `CAGED_SKIP_PI=1`.
  `Containerfile.base` via `scripts/build-caged-base.sh` (apt essentials,
  glab, gh, acli, non-root user; tag `caged-base:latest`) — so the pi and dsh
  image builds share one cached base. Skip that with `CAGED_SKIP_BASE=1`,
  or point both at a custom `CAGED_BASE_IMAGE`.
- **`scripts/build-caged-base.sh`** — builds that base, and first clones/pulls
  the git skill sources on the host into `seed/skills-sync/vendor/` (needs
  host Node.js; skip with `CAGED_SKIP_SKILLS_SYNC=1`). The repos deliberately
  never enter an image — the seed mount carries them into every container.
- **`scripts/start-container.sh`** (invoked by `cg <agent> start`) — `container run` wiring the two mounts
  (`/workspace`, the live seed `~/.pi`), the
  environment, and the hardening flags the tool supports (`--read-only`,
  `--cap-drop ALL`, `--tmpfs /tmp`, `-it`). It also adds two things it
  manages for you:
  1. a **fail-fast host-side seed check** (`models.json` present) before
     starting,
  2. **stops a leftover same-name container** (`container stop` — SIGTERM, 5s
     timeout) before running.

`cg dsh start` keeps the same hardening flags and also
passes `-it`, even though dsh is a web server (no TUI). dsh session logs are
routed to `/workspace/.dsh/sessions` natively via `seed/.dsh/cordis.patch.yml`
(no extra session volume mount needed). pi does the same for its sessions:
`seed/.pi/agent/settings.json` sets `sessionDir` to `/workspace/.pi/sessions`,
so they land in `$CAGED_WORKSPACE/.pi/sessions` through the `/workspace` bind
— no dedicated mount there either. Web UI mode also passes
`PI_CODING_AGENT_SESSION_DIR=/workspace/.pi/sessions` explicitly because its
embedded pi SDK does not necessarily use the seed settings file. That is a workaround:
without a TTY, the tool's foreground signal path is broken upstream — the CLI
XPCs SIGINT into the guest with a signal field the API service reads as a
different type, so every Ctrl+C prints `failed to send signal: ... "missing
signal in xpc message"` and the signal never reaches the container (see
apple/container#1747, the SIGWINCH variant). With `-it` the host terminal is
raw and Ctrl+C flows through the pty into the guest, stopping the container
cleanly on one press. Don't "simplify" the flag away; the alternative stop is
`container stop caged-dsh`.

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

`cg dsh start` probes `192.168.64.1:8765` at startup (warns, doesn't
fail) when `LOCAL_API_KEY` is set.

Why not a hostname? apple/container has no `--add-host` and won't resolve
`host.docker.internal` or `host.container.internal` without the documented
`container system dns create --localhost` + `[dns] domain` machinery (sudo,
pf rules that die on reboot, Private Relay caveats — see
[apple/container#673](https://github.com/apple/container/issues/673) and
[#346](https://github.com/apple/container/issues/346)). A static IP avoids
all of it.

> **Note.** The image remains a plain OCI image, so it can also be run
> directly under podman/docker with equivalent hardening flags if you're not
> on Apple silicon. The `models.json` local-provider `baseUrl`
> (`http://192.168.64.1:8765/v1`) targets the Apple vmnet gateway; if you run
> the image under podman/docker instead, set a resolver that maps the host
> bridge into that path. We only support the Apple `container` path here.

## Hardening applied

The image's own hardening (non-root, read-only rootfs, tini as PID 1) is in
the Containerfile and `scripts/entrypoint.sh`. `cg start` (via
`scripts/start-container.sh`) adds what
the tool supports: `--read-only`, `--cap-drop ALL`, `--tmpfs /tmp`, `-it`.

Layers the tool cannot express (compared to a podman `--run` equivalent):

| Flag you'd use on podman | Apple `container` | Why / consequence |
|---|---|---|
| `init: true` (podman init as PID 1) | omitted | **No loss here**: the image's entrypoint already `exec tini -s --` as PID 1 (`scripts/entrypoint.sh`), which reaps children and forwards signals. `container run --init` exists if you want the outer init too. |
| `--tmpfs /tmp:rw,noexec,nosuid,size=512m` | `--tmpfs /tmp` | The tool's `--tmpfs` takes only a path — **no size cap, no `noexec`/`nosuid`** on the Apple path |
| `--security-opt=no-new-privileges` | omitted | **No `--security-opt` in the tool** — the no-setuid-escalation layer is lost on this path |
| `--userns=keep-id` | omitted | **No userns support** — the guest runs as the host user directly, so uid remap is neither possible nor needed |

Net posture: `--cap-drop ALL`, non-root, and the read-only rootfs still
apply; the two lost layers (`no-new-privileges`, userns keep-id) make this
path **slightly less hardened** than a podman equivalent — see
[SECURITY.md](SECURITY.md).

## Resource defaults

The tool's guest is a VM with **1 GB RAM / 4 CPUs by default**, and the
BuildKit builder builds with **2 CPUs / 2 GB**.

- `cg pi start` pins `--memory 2g` at runtime — the 1 GB default OOMs
  pi on larger tasks. Override with `CAGED_MEMORY` (e.g.
  `CAGED_MEMORY=8g cg pi start`). CPUs stay at the 4-CPU
  default; if heavy workspace builds feel slow, add `--cpus` alongside.
- the build script (`scripts/build-container.sh pi|dsh`) keeps the builder defaults (2 CPU / 2 GB); if an image
  build OOMs, add `--memory` there too.

A machine-wide default is possible via the tool's own config file
(`[container] memory`/`cpus` keys, see
[container-system-config](https://github.com/apple/container/blob/main/docs/container-system-config.md))
— the script pins the value instead so behavior is reproducible on any host.

> `cg pi start` is the single runtime entry. Select `pi`
> (default), `webui`, `dsh`, or `cmdc` as the agent argument; remaining
> arguments replace the image's default command.
