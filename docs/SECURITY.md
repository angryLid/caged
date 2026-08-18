# caged SECURITY model

caged runs @earendil-works/pi-coding-agent in a single disposable container
designed purely for isolation (no orchestration — see
[APPLE-CONTAINER.md](APPLE-CONTAINER.md)). The agent has the ability to
execute arbitrary shell commands in the workspace — that is its whole job.
The point of caged is to make sure that power can never escape the workspace
or compromise the host.

## Threat model

An attacker here is: a malicious prompt, a compromised model provider, or a
malicious extension/skill that pi loads. Their goal is to read secrets, touch
the host filesystem beyond the mount, or persist on the host.

| Risk | Mitigation | Status |
|------|-----------|--------|
| Read host files | only `/workspace` (which backs per-project session data at `/workspace/.pi/sessions`) and `caged/seed/.pi` (mounted at `/agent-home/.pi`, pi's config home) are mounted; no `-v /`, rootfs is read-only | ✅ |
| Write host files | read-only rootfs; `/workspace` rw and the live `~/.pi` bind at `/agent-home/.pi` (== `caged/seed/.pi`) rw are the only writable host-backed mounts | ✅ |
| Escape via root | runs as UID 1000 non-root | ✅ |
| Gain capabilities | `--cap-drop ALL` + `--security-opt no-new-privileges` | ✅ |
| Kernel exploit | container seccomp profile | ✅ |
| Exfiltrate secrets via network | **⚠️ intentionally NOT mitigated** — network is fully open by design (pi talks to model providers). See notes below. | ⚠️ |
| Persistence on host | live `~/.pi` bind `caged/seed/.pi` → `/agent-home/.pi` (config/auth/skills at `seed/.pi/agent`, sessions at `$CAGED_WORKSPACE/.pi/sessions`) | ✅ |
| Zombie processes | tini as PID 1 | ✅ |

## Deliberate trade-offs (accepted risks)

1. **Open network.** Required to reach model providers and to let pi install
   packages / `npm install` / clone repos. This means a compromised agent could
   exfiltrate whatever it can read inside `/workspace` and the live `~/.pi`
   bind. → Keep your real secrets **out of `/workspace`**, or run `caged` on a
   throwaway checkout of the repo. Provision keys via `auth.json` in
   `seed/.pi/agent/` (gitignored) and never commit them.

2. **Read-write `/workspace`.** pi needs it to edit code. If a repo should be
   treated as read-only, mount it `:ro` and let pi only read, or fork it into
   the workspace.

3. **Host GPU / docker socket / CI creds are NOT mounted** by default. If you
   need them, you are expanding the blast radius — add them explicitly and
   document why.

4. **GitLab CLI token at rest in the live seed.** `glab auth login` persists
   a plaintext token to `seed/.pi/agent/glab-cli/config.yml` (gitignored,
   `0600`) so interactive auth survives container restarts — see
   [CLI-AUTH.md](CLI-AUTH.md) for the full risk analysis. `glab`
   still prefers `GITLAB_TOKEN` from the env when it is set.

## pi-web-ui (Web UI) mode

`scripts/start-container.sh webui` serves the same agent through a browser
instead of the TUI. The threat surface is unchanged **in kind** — whoever can
drive the WebSocket can run the agent with exactly the TUI's power (arbitrary
bash in `/workspace`, read of the live seed) — so the extra surface is the
listening port plus the origin check:

* The server binds `0.0.0.0` **inside** the container (required for the
  `-p` mapping to reach it), but the host side is published to
  `127.0.0.1:8787` **only** — the UI is not reachable from the LAN. Keep it
  that way; anyone who can reach the port controls the agent.
* Cross-origin WebSocket pages are rejected (403, Origin/Host same-authority
  check); `PI_WEB_ALLOW_ORIGINS` is deliberately not set.
* Provider `headers` / API keys never leave the server process (not sent to
  the browser; the model UI edits everything else and the server preserves
  the headers).
* Everything else is the same hardened container: read-only rootfs, uid
  1000, `--cap-drop ALL`, the same two mounts (`/workspace`, the live
  seed), open network with the same accepted exfiltration trade-off.

## Layered defense quick reference

* Image: non-root USER pi, pinned agent version, minimal base layer.
* Seed: `seed/` ships only **configuration, never secrets** — `models.json`
  references key env-var names, real values arrive via container env at
  runtime and live only in the process/volume `auth.json`.
* Runtime (`scripts/start-container.sh` + `scripts/entrypoint.sh`): read-only
  rootfs + tmpfs + cap_drop ALL (+ `no_new_privileges` and keep-id on podman/
  docker; not expressible on Apple's `container` tool — see
  [APPLE-CONTAINER.md](APPLE-CONTAINER.md)).
* Volume hygiene: pi's config home lives in the live `~/.pi` bind
  (`caged/seed/.pi`, synced to the host repo); the rest of `$HOME` is
  read-only with caches on `/tmp`; sessions live per-project at
  `$CAGED_WORKSPACE/.pi/sessions`; `seed/.pi/agent/auth.json` is gitignored.

## Verifying the container is actually restricted

```sh
container run --rm -it --read-only --cap-drop ALL --tmpfs /tmp \
  -v "$PWD/seed/.pi:/agent-home/.pi" caged:latest sh -c '
    id
    touch /etc/test 2>&1 | head -1
    touch /tmp/test && echo "tmp writable"
    mount | grep -cE "on / (type overlay|type bind)" 
  '
```
Expect: user is 1000, `/etc/test` fails, `/tmp` writable.
