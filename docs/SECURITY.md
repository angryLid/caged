# caged SECURITY model

caged runs @earendil-works/pi-coding-agent in a podman container. The agent has
the ability to execute arbitrary shell commands in the workspace — that is its
whole job. The point of caged is to make sure that power can never escape the
workspace or compromise the host.

## Threat model

An attacker here is: a malicious prompt, a compromised model provider, or a
malicious extension/skill that pi loads. Their goal is to read secrets, touch
the host filesystem beyond the mount, or persist on the host.

| Risk | Mitigation | Status |
|------|-----------|--------|
| Read host files | only `/workspace` and `/pi-agent` are mounted; no `-v /`, rootfs is read-only | ✅ |
| Write host files | read-only rootfs; `/workspace` rw is the only writable host-backed mount | ✅ |
| Escape via root | runs as UID 1000 non-root with `--userns=keep-id` | ✅ |
| Gain capabilities | `--cap-drop ALL` + `--security-opt no-new-privileges` | ✅ |
| Kernel exploit | container seccomp profile (podman default) | ✅ |
| Exfiltrate secrets via network | **⚠️ intentionally NOT mitigated** — network is fully open by design (pi talks to model providers). See notes below. | ⚠️ |
| Persistence on host | named volume `caged-pi-agent` is the only persisted state; wipe it to reset | ✅ |
| Zombie processes | tini as PID 1 | ✅ |

## Deliberate trade-offs (accepted risks)

1. **Open network.** Required to reach model providers and to let pi install
   packages / `npm install` / clone repos. This means a compromised agent could
   exfiltrate whatever it can read inside `/workspace` and `/pi-agent`.
   → Keep your real secrets **out of `/workspace`**, or run `caged` on a throwaway
   checkout of the repo. Provision keys via `auth.json` in `/pi-agent` and never
   commit them.

2. **Read-write `/workspace`.** pi needs it to edit code. If a repo should be
   treated as read-only, mount it `:ro` and let pi only read, or fork it into
   the workspace.

3. **Host GPU / docker socket / CI creds are NOT mounted** by default. If you
   need them, you are expanding the blast radius — add them explicitly and
   document why.

## Layered defense quick reference

* Image: non-root USER pi, pinned agent version, minimal base layer.
* Seed: `seed/` ships only **configuration, never secrets** — `models.json`
  references key env-var names, real values arrive via container env at
  runtime and live only in the process/volume `auth.json`.
* Runtime (compose.yaml): read-only rootfs + tmpfs + cap_drop ALL +
  no_new_privileges + keep-id userns.
* Volume hygiene: everything pi persists lives under one named volume.

## Verifying the container is actually restricted

```sh
podman run --rm -it --read-only --cap-drop ALL --security-opt no-new-privileges \
  --userns=keep-id -v caged-pi-agent:/pi-agent caged:latest sh -c '
    id
    touch /etc/test 2>&1 | head -1
    touch /tmp/test && echo "tmp writable"
    mount | grep -cE "on / (type overlay|type bind)" 
  '
```
Expect: user is 1000, `/etc/test` fails, `/tmp` writable.
