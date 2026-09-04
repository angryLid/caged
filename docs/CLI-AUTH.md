# CLI auth behavior — glab, gh & jira-cli

How the baked-in CLIs authenticate, why everything is token-driven, and where
their (non-secret) config lands. This file replaces the older
"persist the login into a managed dir" design.

## Decision status

**Accepted, by design (2026-09).** caged runs like a CI/CD pipeline: **all
three CLIs authenticate via an env TOKEN, nothing else**. `glab` uses
`GITLAB_TOKEN`, `gh` uses `GH_TOKEN`, `jira-cli` uses `JIRA_API_TOKEN`. No
interactive `auth login` is needed (or documented) for any of them. We do not
point any CLI at a custom config location: they follow their own defaults,
which land inside the seed (gitignored), and caged does not manage their
behavior beyond that.

## The three models — one pattern

| | glab (GitLab) | gh (GitHub) | jira-cli (Jira, `jira`) |
|---|---|---|---|
| Token env var | `GITLAB_TOKEN` (+ `GITLAB_HOST` for self-hosted) | `GH_TOKEN` (+ `GH_HOST` for GH Enterprise) | `JIRA_API_TOKEN` |
| Works with zero prior setup? | ✅ | ✅ | ✅ token-wise; config must exist (see below) |
| Token written to disk by caged? | ❌ never — env only | ❌ never | ❌ never (jira-cli has no token-at-rest path at all; `jira init` writes no token) |
| Persisted login command | `glab auth login` (exists, **not used here**) | `gh auth login` (exists, **not used here**) | none exists |
| Config file | `$XDG_CONFIG_HOME/glab-cli/config.yml` (+ `aliases.yml`) | `$XDG_CONFIG_HOME/gh/hosts.yml`, `config.yml` | `$XDG_CONFIG_HOME/.jira/.config.yml` |
| Config sensitivity | non-secret (host/user settings; token only if you `auth login`, which we don't) | non-secret (host/user; token only via `auth login`, unused here) | non-secret (site URL, login, project, board) |

## Where config lives (defaults, not managed)

`XDG_CONFIG_HOME` is set to `/agent-home/.config` by `start-container.sh`, so
each CLI's default config path resolves inside the seed and survives restarts:

| CLI | Config path (in container) | Seed path |
|---|---|---|
| glab | `$XDG_CONFIG_HOME/glab-cli/` | `seed/.config/glab-cli/` |
| gh | `$XDG_CONFIG_HOME/gh/` | `seed/.config/gh/` |
| jira-cli | `$XDG_CONFIG_HOME/.jira/` | `seed/.config/.jira/` |

All of `seed/.config/` is gitignored. caged does **not** create, seed, or
inspect these files — the CLIs create them lazily on first use (glab/gh) or
via `jira init` (jira-cli). Do not document or depend on their internals.

> **Legacy `seed/cli-auth/`.** Older caged releases persisted CLI logins under
> `seed/cli-auth/{glab,gh,acli}/` and directed the CLIs there via
> `GLAB_CONFIG_DIR` / `GH_CONFIG_DIR` / `ACLI_CONFIG_DIR`. That is obsolete:
> the env vars are gone and the dir is fully gitignored. `seed/cli-auth/acli/`
> may still hold token-bearing configs from a pre-migration run — acli is no
> longer installed and nothing reads them; delete the dir whenever convenient.

## Why token-only

- **Matches how the container is run.** caged is launched per task, like a CI
  job; tokens are passed by the operator exactly like `GITLAB_TOKEN` flows
  through a pipeline. No interactive login, no browser, no keyring.
- **No token at rest (strictly).** With env-token-only use, glab and gh never
  write their token to a config file (their `auth login` does, but we don't
  run it). jira-cli cannot store a token at rest even in principle (no
  `login` command; `jira init` writes no token key).
- **Restart survival is not needed for auth.** The token comes with each
  container start; only the non-secret config (host, default project) is
  persisted, and only because the CLI requires it (jira-cli) or writes it
  lazily (glab/gh).

## Risk assessment

| Threat | Mitigation | Residual risk | Applies to |
|---|---|---|---|
| Repo push accidentally includes a token | tokens are env-only; `seed/.config/` and `seed/cli-auth/` gitignored | `git add -f` or future `.gitignore` edits could include legacy files — review diffs | all |
| Full-dir backup/sync leaks a token | no token file exists (env-only use); legacy acli files remain `0600` + gitignored | tools that copy the whole tree copy ignored files too — legacy `seed/cli-auth/acli/` leaves the machine with any full-tree copy until deleted | legacy acli only |
| Compromised agent inside the container exfiltrates the token | identical exposure to the env vars the operator already passes — no marginal risk | token expiry/rotation limits the blast radius | all |
| Token expiry/rotation leaves a stale credential | operator rotates the env var; no stale at-rest copy to shadow it | late auth failures until the env var is updated | all |
| Config tampering (agent overwrites a CLI config file) | non-secret config only; no integrity protection — same as all of `~/.pi` and `/workspace` | an attacker that can write the seed can do worse things anyway | all |

## Pitfalls

- **`JIRA_API_TOKEN` is real for jira-cli.** The Atlassian *acli* that
  previously shipped ignored it (its only path was
  `acli jira auth login --token`); `jira-cli` reads it implicitly for every
  command. If `jira` reports unauthorized, check the env var first.
- **jira still needs a config file, not just a token.** glab/gh derive the
  host from `GITLAB_HOST`/remotes/HOST and work with env token alone, but
  jira-cli requires the blueprint from `jira init` (site URL, login, default
  project). A fresh container with only `JIRA_API_TOKEN` set but no config
  fails with a token/setup hint.
- **`jira init` validates against the live instance.** It calls
  `GET /rest/api/2/myself` and refuses to write a config for an unreachable or
  untrusted site (`Unable to generate configuration:` / `404 Not Found`). Use
  the full `https://` URL and a working token the first time. It reads the
  token from the env (it does **not** read stdin).
- **Env tokens are host-bound (glab, gh).** A `GITLAB_TOKEN` only matches the
  host named by `GITLAB_HOST` (or a matching git remote); a `GH_TOKEN`
  likewise matches `GH_HOST`. With the host var unset, the CLI targets
  github.com/gitlab.com and a token minted for another host fails with a
  quiet 401 — easy to misread as a bad token.
- **No OS keyring in this container** (no D-Bus / Secret Service). jira-cli's
  keyring lookup always misses (its env path comes first); glab/gh are used
  env-only so no keyring is needed.

## Accepted / out of scope

* No fail-fast check for a missing token at container start — by explicit
  request; failures surface when the CLI is actually used.
* No OS keyring: no D-Bus / Secret Service in the container; not needed since
  all three CLIs run env-token-only.
* glab `git_protocol: ssh` is dead config — the container ships no ssh
  binary. Log in with `--git-protocol https`.
* The `git credential` helper is not configured — `gh auth setup-git` is not
  used here; HTTPS push/fetch over git uses separate credentials.

## Verify

```sh
glab api user          # works from GITLAB_TOKEN alone, no login, no config seed
gh api user            # works from GH_TOKEN alone
jira version           # metadata command, token not required
git -C seed/.config ls 2>/dev/null   # (optional) where CLI configs land
```

## First-time setup

Nothing to do for glab/gh — pass the env tokens when starting the container.
jira-cli needs its config generated once (token comes from the env):

```sh
export JIRA_API_TOKEN=...            # required: init validates against the instance
jira init --installation cloud \
  --server "https://mysite.atlassian.net" \
  --login "you@example.com" --auth-type basic --force
jira project list                    # verify
```

`jira init` writes `$XDG_CONFIG_HOME/.jira/.config.yml` (= the gitignored
`seed/.config/.jira/`); `--force` overwrites an existing config,
`--project`/`--board` set the defaults.