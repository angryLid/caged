# CLI auth behavior — glab, gh & acli

How the baked-in CLIs find their credentials, why the login is persisted
to the live seed mount, and the traps around it. The token-at-rest decision
and its risk analysis live here as well.

## Decision status

**Accepted, by design (2026-08).** Persisting the CLIs' tokens at rest on the
live shared agent-home seed mount supersedes the earlier "env-only, no
persistence" posture (previously listed in the README's known issues). `gh`
follows the same pattern as `glab`/`acli` (env token when set, persisted login
as the fallback).

## The three models

| | glab (GitLab) | gh (GitHub) | acli (Atlassian/Jira) |
|---|---|---|---|
| Reads an auth token env var implicitly? | ✅ `GITLAB_TOKEN` (+ `GITLAB_HOST` for self-hosted) — works with zero prior login | ✅ `GH_TOKEN` (+ `GH_HOST` for GH Enterprise) — works with zero prior login | ❌ no env path; the token enters only via `acli jira auth login --token` |
| With no login and no env token | targets gitlab.com (or the configured host) → fails | targets github.com (or the configured host) → fails | refuses: `unauthorized: use 'acli jira auth login' to authenticate` |
| Precedence | env token > stored config | env token > stored config | stored config only (env ignored) |
| Re-auth needed | only when the token rotates | only when the token rotates | only when the token rotates |

Verified on the running image (glab 1.112.0, gh 2.97.0, acli 1.3.22): with an
empty config dir, `glab api user` succeeds from `GITLAB_TOKEN` alone and
`gh api user` succeeds from `GH_TOKEN` alone, while `acli jira auth status`
still errors with `JIRA_API_TOKEN` set.

## Where the credentials live

| | glab | gh | acli |
|---|---|---|---|
| Persisted login dir | `/agent-home/cli-auth/glab/` — shared live agent-home mount used by pi, pi-webui, and dsh | `/agent-home/cli-auth/gh/` — shared live agent-home mount used by pi, pi-webui, and dsh | `/agent-home/cli-auth/acli/` — shared live agent-home mount used by pi, pi-webui, and dsh |
| Token file | `glab-cli/config.yml` → `hosts.<hostname>.token` + per-host user/api/ssh settings; `aliases.yml` | `hosts.yml` → `github.com.oauth_token` (per-host `user`/`oauth_token`/..); `config.yml` | `acli/acli/jira_config.yaml` (per-product configs; token in the jira one) |
| Permissions | `0600` file, `0700` dir (verified) | `0600` file, `0700` dir (verified) | `0600` file, `0700` dir (verified) |
| Git | ignored via `.gitignore` | ignored via `.gitignore` | ignored via `.gitignore` |

All three stores are **plaintext**: the container has no OS keyring (no
D-Bus / Secret Service), so every CLI falls back to a plaintext config file.

## Why persist the login

- **Login once per token lifetime, not per container start.** All three CLIs
  reuse the stored credential on every command; without persistence every
  restart needs the token fed in again.
- **Restart survival.** The config dirs point into the live shared
  `/agent-home` seed mount, so the login outlives the container and is
  available to pi, pi-webui, and dsh.
- **`glab` and `gh` keep their automation fast path.** `GITLAB_TOKEN` /
  `GH_TOKEN` still win when set, so one-shot and CI runs behave exactly as
  before — persistence only adds a fallback. acli has no env fast path, so
  persistence is its only supported path.

## Risk assessment

| Threat | Mitigation | Residual risk | Applies to |
|---|---|---|---|
| Repo push accidentally includes the token | gitignored, never tracked | `git add -f` or future `.gitignore` edits could include it — review diffs before pushing | all |
| Full-dir backup/sync leaks the token | `0600`/`0700` perms; gitignored | tools that copy the whole tree (`rsync -a`, tarballs, Time Machine, cloud sync) copy ignored files too — the token leaves the machine with any full-tree copy | all |
| Another host user / host malware reads the file | owner-only perms; container runs as the same uid 1000 = host user | **host compromise == token compromise**; nothing in caged changes that | all |
| Compromised agent inside the container exfiltrates it | glab/gh: identical exposure to env `GITLAB_TOKEN`/`GH_TOKEN` and `auth.json` — no marginal risk; acli: the file is the *only* carrier (no env copy exists) | one more readable secret; token expiry/rotation limits the blast radius | all |
| Token expiry/rotation leaves a stale credential | documented re-login path; operator rotates tokens | late auth failures until re-login; a newer env token can silently shadow the stale stored one (glab, gh) | all |
| Config tampering (agent overwrites the config file) | no integrity protection — same as all of `~/.pi` and `/workspace` | an attacker that can write the seed can do worse things anyway; not a new boundary | all |

## Pitfalls

- **`JIRA_API_TOKEN` is a decoy.** The container env carries it, but the
  official acli never reads it — nor `ATLASSIAN_*` / `JIRA_URL` style vars,
  which belong to third-party atlassian-cli clones. If acli reports
  unauthorized, `auth login` with the token is the only fix; adding env vars
  changes nothing.
- **Env tokens are host-bound (glab, gh).** A `GITLAB_TOKEN` only matches
  the host named by `GITLAB_HOST` (or a matching git remote); a `GH_TOKEN`
  likewise matches `GH_HOST`. With the host var unset, the CLI targets
  github.com/gitlab.com and a token minted for another host fails with a
  quiet 401 — easy to misread as a bad token.
- **`auth status` reports the winning source, not the persistent one.**
  With the env token set, `glab auth status` / `gh auth status` always claim
  the token comes from the environment even when a stored credential exists.
  Unset the env (`env -u GITLAB_TOKEN glab auth status`,
  `env -u GH_TOKEN gh auth status`) to verify the persisted login.

## Accepted / out of scope

* No fail-fast check for a missing token at container start — by explicit
  request; failures surface when the CLI is actually used.
* No OS keyring: no D-Bus / Secret Service in the container; plaintext
  config-file fallback is by design (glab warns once, gh and acli do not).
* glab `git_protocol: ssh` is dead config — the container ships no ssh
  binary. Log in with `--git-protocol https`.
* The `git credential` helper is not configured — `gh auth login` / `gh auth
  setup-git` persist a token for `gh` itself; password-protected HTTPS push/
  fetch over git uses separate credentials. Point users at `gh auth login`.

## Verify

```sh
glab api user                        # env-token path succeeds, no login needed
glab auth status                     # shows which source wins
env -u GITLAB_TOKEN glab auth status # proves the stored credential works
gh api user                          # env-token path succeeds, no login needed
gh auth status                       # shows which source wins
env -u GH_TOKEN gh auth status       # proves the stored credential works
acli jira auth status                # stored credential only
```

## Re-login commands

```sh
echo "$GITLAB_TOKEN" | glab auth login --hostname gitlab.example.com --stdin --git-protocol https
echo "$JIRA_API_TOKEN" | acli jira auth login --site mysite.atlassian.net --email you@example.com --token
echo "$GH_TOKEN" | gh auth login --hostname github.com --with-token
```