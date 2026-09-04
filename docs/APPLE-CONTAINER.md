# Apple `container` — docker divergences

Apple's [`container`](https://github.com/apple/container) is a container runtime optimized for Apple silicon (Linux containers as lightweight VMs). This page records only the places it diverges from docker/podman behavior that bite this project. Everything else behaves as docker does.

## No orchestration

`container` has no compose/orchestration support. This project runs a single disposable container whose only job is isolation, so nothing is lost.

## Host names don't resolve — use the gateway IP

`host.docker.internal` and `host.container.internal` do not resolve, and there is no `--add-host`. Use the vmnet gateway IP instead: **`192.168.64.1`** is the default network's gateway (the container's default route — reachable with no DNS, pf, or sudo, and it survives reboots). Verify once:

```bash
container run -it --rm alpine ip route   # default gateway = 192.168.64.1
```

Host services must listen on that address, not just loopback:

- `caddy-dev-server` (the local LLM proxy): Caddyfile `192.168.64.1:8765`. Binding the gateway IP does **not** expose the service to your LAN; avoid `0.0.0.0`.
- Chrome's CDP binds `127.0.0.1` only on macOS, so bridge it: `socat TCP-LISTEN:192.168.64.1:9222,fork TCP:127.0.0.1:9222 &`.

## `.dockerignore` deep-negation is not honored

`container build`'s context indexer does **not** honor the collapsed deep-negation form — the `!` entries never re-include the file:

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

## Hardening flags it cannot express

| Flag you'd use on podman | Apple `container` | Why / consequence |
|---|---|---|
| `--security-opt=no-new-privileges` | omitted | No `--security-opt` — the no-setuid-escalation layer is lost. |
| `--userns=keep-id` | omitted | No userns support — the guest runs as the host user, so remap is neither possible nor needed. |
| `--tmpfs /tmp:rw,noexec,nosuid,size=512m` | `--tmpfs /tmp` | Path only — no size cap, no `noexec`/`nosuid`. |
| `init: true` | `container run --init` | No loss: the entrypoint already `exec tini -s --` as PID 1. |

Net posture: `--cap-drop ALL`, non-root, and read-only rootfs still apply; the lost layers (no-new-privileges, keep-id) make this path slightly less hardened than a podman equivalent — see [SECURITY.md](SECURITY.md).

## Resource defaults

The guest VM defaults to **1 GB RAM / 4 CPUs**; the BuildKit builder builds with **2 CPUs / 2 GB**. The 1 GB default OOMs pi on larger tasks, so `cg pi start` pins `--memory 2g` (override with `CAGED_MEMORY`).

## Signal bug (no TTY)

Without `-it`, the tool's foreground signal path is broken upstream: Ctrl+C prints `failed to send signal: ... "missing signal in xpc message"` and never reaches the container ([apple/container#1747](https://github.com/apple/container/issues/1747)). `cg dsh start` passes `-it` for this reason; the alternative stop is `container stop caged-dsh`.
