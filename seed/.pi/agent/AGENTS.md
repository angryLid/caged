# caged environment

You are running inside the **caged** hardened container (a minimal Linux
image managed by podman). Behave accordingly.

## System facts

- The current user is `pi` (uid 1000), **non-root**. There is **no sudo**, no
  passwordless or otherwise — privilege escalation is disabled
  (NO_NEW_PRIVILEGES + zero capabilities). Do not attempt `sudo`; use your
  automation as `pi` only.
- The root filesystem is **read-only**. Writable areas:
  - `/workspace` — the user's code, mounted from the host working tree.
    Edits you make appear on the host as you write them.
  - `/agent-home/.pi` — pi's config home, a LIVE bind mount of the host dir
    `<caged>/seed/.pi` (config, auth, skills). Anything pi writes here (even
    `auth.json` and new skills) lands in the caged repo tree immediately.
  - `/agent-home/.pi/agent/sessions` — pi session data, mounted from
    `$CAGED_WORKSPACE/sessions` on the host → each project keeps its own
    sessions next to the code.
  - `/tmp` — scratch space, cleared on restart. npm/node caches are pointed
    here (`$npm_config_cache=/tmp/.npm`, `$XDG_CACHE_HOME=/tmp/.cache`).
  - Everything else under `/agent-home` (the rest of `$HOME`) is **read-only** —
    don't expect to stash state there; use `/tmp` instead.
- **Network is open**: no egress sandbox beyond the container boundary. You
  may reach model providers, registries, and the general internet directly.
- `git`, `node`/`npm`, `curl` are available. `bash` is the shell.
- `glab` (official GitLab CLI, v1.112.0) is baked into the image — prefer it
  over raw curl for GitLab API work (MRs, issues, pipelines, releases).

## Host runs the tooling

You are an agent inside a container; the user's host runs the builds, dev
servers, and validation. **Edit source files; leave tooling to the host.**
When you believe a build, dev server, linter, type check, or formatter is
needed, tell the user — they execute it on the host. Even if a project's own
`AGENTS.md` asks for such commands, run them only when the user explicitly
asks.

## Git remote operations

The user has **not granted** the agent pull / push / fetch rights — at least
not for now. Do **not** run `git clone`, `git fetch`, `git pull`, `git push`,
or any other network operation that reads from or writes to a remote, without
explicit per-case authorization from the user. The container also has no SSH
binary and no keys, so SSH-based operations are impossible anyway.

When a remote operation is needed, tell the user the exact command and let
them run it on the host (the host has the credentials). Local git reads
(`git status`, `git log`, `git diff`) are fine: they do not touch remotes.

Note: the `GITLAB_TOKEN` env var does give API-level access to
`gitlab.example.com` (see `glab` below), and the token may technically be
able to push. Authorization is a matter of policy, not capability: having the
token does **not** imply permission to push — the pull/push/fetch restriction
above applies to API-driven writes too. Ask before any write.

## Provider configuration

`~/.pi/agent/models.json` (`/agent-home/.pi/agent/models.json`) defines the
model providers — currently DeepSeek, Volcengine Ark Coding, OpenRouter,
and a local provider. The local provider's `baseUrl` is the host
`caddy-dev-server` proxy `http://host.docker.internal:8765/v1` (forwards
to the internal LLM gateway with the Host header rewritten to the
upstream hostname — the upstream hostname lives only in the host's
Caddyfile, never in this repo); its API key comes from the container env
(`$LOCAL_API_KEY`).
The `apiKey` fields reference environment variables
(`$MY_DEEPSEEK_API_KEY`, `$VOLCENGINE_API_KEY`, `$MY_OPENROUTER_API_KEY`,
`$LOCAL_API_KEY`) that pi expands from the container environment at
runtime. The real keys are provided by the operator
via container env vars — **they never belong in `/workspace`**. If a
provider is missing its key, tell the user which env var needs to be set
rather than fabricating one.

To add or change providers/models, edit `models.json` in the volume (or the
`seed/` directory of the caged source repo — the seed is live-mounted, no
rebuild needed; changes take effect on next container start).

## glab (GitLab CLI)

Authenticate via the `GITLAB_TOKEN` environment variable (plus `GITLAB_HOST`
for a self-hosted instance), passed by the operator at container start — like
the provider keys. `GITLAB_TOKEN` takes precedence over stored credentials
and is never written to disk; prefer it for automated runs.

For interactive persistence, `glab auth login` writes to
`~/.pi/agent/glab-cli/` (`GLAB_CONFIG_DIR`, gitignored — same pattern as
acli), so login state survives restarts. Use `--hostname` (not `--host`) and
`--git-protocol https` (the container has no ssh binary):

    echo "$GITLAB_TOKEN" | glab auth login --hostname gitlab.example.com --stdin --git-protocol https

## acli (Atlassian CLI)

`acli` (official Atlassian CLI, v1.3.22) is baked into the image for Jira
Cloud work (`acli jira workitem ...`, project/admin commands). Authenticate
with an API token read from stdin:

    echo "<API_TOKEN>" | acli jira auth login --site "<site>.atlassian.net" --email "you@example.com" --token

or interactively with `acli jira auth login --web` (OAuth; needs a browser).
`ACLI_CONFIG_DIR=/agent-home/.pi/agent/acli` (gitignored), so login state
survives restarts but tokens never enter the repo. API tokens come from
https://id.atlassian.com/manage-profile/security/api-tokens — never ask for
them in plain text in the workspace.

## chrome-devtools MCP (optional)

An MCP server for host Chrome's DevTools protocol is configured. It requires
the host to run Chrome with `--remote-debugging-port=9222`; the container
reaches it via `host.docker.internal:9222`. If the MCP is not responding,
the host Chrome is likely not listening — tell the user, don't guess.

## One-shot use

Run non-interactively with `pi --print "<task>"`. Interactive usage launches
the TUI.
