# CLI auth behavior — glab & acli

How the two baked-in CLIs find their credentials, why the login is persisted
to the live seed mount, and the traps around it. The token-at-rest decision
and its risk analysis live here as well.

## Decision status

**Accepted, by design (2026-08).** Persisting `glab`'s token at rest on the
live seed mount supersedes the earlier "env-only, no persistence" posture
(previously listed in the README's known issues), and mirrors the existing
`acli` pattern.

## The two models

| | glab (GitLab) | acli (Atlassian/Jira) |
|---|---|---|
| Reads an auth token env var implicitly? | ✅ `GITLAB_TOKEN` (+ `GITLAB_HOST` for self-hosted) — works with zero prior login | ❌ no env path; the token enters only via `acli jira auth login --token` |
| With no login and no env token | targets gitlab.com (or the configured host) → fails | refuses: `unauthorized: use 'acli jira auth login' to authenticate` |
| Precedence | env token > stored config | stored config only (env ignored) |
| Re-auth needed | only when the token rotates | only when the token rotates |

Verified on the running image (glab 1.112.0, acli 1.3.22): with an empty
config dir, `glab api user` succeeds from `GITLAB_TOKEN` alone, while
`acli jira auth status` still errors with `JIRA_API_TOKEN` set.

## Where the credentials live

| | glab | acli |
|---|---|---|
| Persisted login dir | `~/.pi/agent/glab-cli/` — live `~/.pi` mount, set via `GLAB_CONFIG_DIR` in `compose.yaml` | `~/.pi/agent/acli/` — live `~/.pi` mount, set via `ACLI_CONFIG_DIR` |
| Token file | `glab-cli/config.yml` → `hosts.<hostname>.token` + per-host user/api/ssh settings; `aliases.yml` | `acli/acli/jira_config.yaml` (per-product configs; token in the jira one) |
| Permissions | `0600` file, `0700` dir (verified) | `0600` file, `0700` dir (verified) |
| Git | ignored via `.gitignore` | ignored via `.gitignore` |

Both stores are **plaintext**: the container has no OS keyring (no D-Bus /
Secret Service), so both CLIs fall back to a plaintext config file.

## Why persist the login

- **Login once per token lifetime, not per container start.** Both CLIs
  reuse the stored credential on every command; without persistence every
  restart needs the token fed in again.
- **Restart survival.** The config dirs point into the live `~/.pi` seed
  mount, so the login outlives the container.
- **glab keeps its automation fast path.** `GITLAB_TOKEN` still wins when
  set, so one-shot and CI runs behave exactly as before — persistence only
  adds a fallback. acli has no env fast path, so persistence is its only
  supported path.

## Risk assessment

| Threat | Mitigation | Residual risk | Applies to |
|---|---|---|---|
| Repo push accidentally includes the token | gitignored, never tracked | `git add -f` or future `.gitignore` edits could include it — review diffs before pushing | both |
| Full-dir backup/sync leaks the token | `0600`/`0700` perms; gitignored | tools that copy the whole tree (`rsync -a`, tarballs, Time Machine, cloud sync) copy ignored files too — the token leaves the machine with any full-tree copy | both |
| Another host user / host malware reads the file | owner-only perms; container runs as the same uid 1000 = host user | **host compromise == token compromise**; nothing in caged changes that | both |
| Compromised agent inside the container exfiltrates it | glab: identical exposure to env `GITLAB_TOKEN` and `auth.json` — no marginal risk; acli: the file is the *only* carrier (no env copy exists) | one more readable secret; token expiry/rotation limits the blast radius | both |
| Token expiry/rotation leaves a stale credential | documented re-login path; operator rotates tokens | late auth failures until re-login; a newer env token can silently shadow the stale stored one (glab) | both |
| Config tampering (agent overwrites the config file) | no integrity protection — same as all of `~/.pi` and `/workspace` | an attacker that can write the seed can do worse things anyway; not a new boundary | both |

## Pitfalls

- **`JIRA_API_TOKEN` is a decoy.** The container env carries it, but the
  official acli never reads it — nor `ATLASSIAN_*` / `JIRA_URL` style vars,
  which belong to third-party atlassian-cli clones. If acli reports
  unauthorized, `auth login` with the token is the only fix; adding env vars
  changes nothing.
- **glab env tokens are host-bound.** A `GITLAB_TOKEN` only matches the host
  named by `GITLAB_HOST` (or a matching git remote). With `GITLAB_HOST`
  unset, glab targets gitlab.com and the token fails with a quiet 401 — easy
  to misread as a bad token.
- **`auth status` reports the winning source, not the persistent one.** With
  `GITLAB_TOKEN` set, `glab auth status` always claims the token comes from
  the environment even when a stored credential exists. Unset the env
  (`env -u GITLAB_TOKEN glab auth status`) to verify the persisted login.

## Accepted / out of scope

* No fail-fast check for a missing token at container start — by explicit
  request; failures surface when the CLI is actually used.
* No OS keyring: no D-Bus / Secret Service in the container; plaintext
  config-file fallback is by design (glab warns once, acli does not).
* glab `git_protocol: ssh` is dead config — the container ships no ssh
  binary. Log in with `--git-protocol https`.

## Verify

```sh
glab api user                        # env-token path succeeds, no login needed
glab auth status                     # shows which source wins
env -u GITLAB_TOKEN glab auth status # proves the stored credential works
acli jira auth status                # stored credential only
```

## Re-login commands

```sh
echo "$GITLAB_TOKEN" | glab auth login --hostname gitlab.example.com --stdin --git-protocol https
echo "$JIRA_API_TOKEN" | acli jira auth login --site mysite.atlassian.net --email you@example.com --token
```
