# CLI auth behavior — glab, gh, jira-cli & cfl

How the baked-in CLIs authenticate, why everything is token-driven, and where
their (non-secret) config lands. This file replaces the older
"persist the login into a managed dir" design.

## Decision status

**Accepted, by design (2026-09).** caged runs like a CI/CD pipeline: **all
four CLIs authenticate via an env TOKEN, nothing else**. `glab` uses
`GITLAB_TOKEN`, `gh` uses `GH_TOKEN`, `jira-cli` uses `JIRA_API_TOKEN`, and
`cfl` (Confluence) uses `CFL_URL` + `CFL_EMAIL` + `CFL_API_TOKEN` — the same
Atlassian API token you already pass as `JIRA_API_TOKEN`. No interactive
`auth login` is needed (or documented) for any of them. We do not point any
CLI at a custom config location: they follow their own defaults, which land
inside the seed (gitignored), and caged does not manage their behavior beyond
that.

## The four models — one pattern

| | glab (GitLab) | gh (GitHub) | jira-cli (Jira, `jira`) | cfl (Confluence Cloud, `cfl`) |
|---|---|---|---|---|
| Token env var | `GITLAB_TOKEN` (+ `GITLAB_HOST` for self-hosted) | `GH_TOKEN` (+ `GH_HOST` for GH Enterprise) | `JIRA_API_TOKEN` | `CFL_URL` + `CFL_EMAIL` + `CFL_API_TOKEN` (token auto-derived from `JIRA_API_TOKEN` by `start-container.sh`; alternatively the shared `ATLASSIAN_HOST`/`ATLASSIAN_EMAIL`/`ATLASSIAN_API_TOKEN` trio is forwarded by `start-container.sh` and assigned to the `CFL_*`/`JIRA_API_TOKEN` vars by the image entrypoint inside the container) |
| Works with zero prior setup? | ✅ | ✅ | ✅ token-wise; config must exist (see below) | ✅ token-wise; URL+email from env, config not required |
| Token written to disk by caged? | ❌ never — env only | ❌ never | ❌ never (jira-cli has no token-at-rest path at all; `jira init` writes no token) | ❌ never in caged — `cfl set-credential` (keyring/backend) is unused; env is resolved first |
| Persisted login command | `glab auth login` (exists, **not used here**) | `gh auth login` (exists, **not used here**) | none exists | `cfl init` (writes non-secret config only) / `cfl set-credential` (token store, **not used here**) |
| Config file | `$XDG_CONFIG_HOME/glab-cli/config.yml` (+ `aliases.yml`) | `$XDG_CONFIG_HOME/gh/hosts.yml`, `config.yml` | `$XDG_CONFIG_HOME/.jira/.config.yml` | `$XDG_CONFIG_HOME/cfl/config.yml` |
| Config sensitivity | non-secret (host/user settings; token only if you `auth login`, which we don't) | non-secret (host/user; token only via `auth login`, unused here) | non-secret (site URL, login, project, board) | non-secret (URL, email, default space) |

## Where config lives (defaults, not managed)

`XDG_CONFIG_HOME` is set to `/agent-home/.config` by `start-container.sh`, so
each CLI's default config path resolves inside the seed and survives restarts:

| CLI | Config path (in container) | Seed path |
|---|---|---|
| glab | `$XDG_CONFIG_HOME/glab-cli/` | `seed/.config/glab-cli/` |
| gh | `$XDG_CONFIG_HOME/gh/` | `seed/.config/gh/` |
| jira-cli | `$XDG_CONFIG_HOME/.jira/` | `seed/.config/.jira/` |
| cfl | `$XDG_CONFIG_HOME/cfl/config.yml` | `seed/.config/cfl/config.yml` |

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
  `login` command; `jira init` writes no token key). cfl normally stores the
  token in an OS keyring or backend (its `set-credential` / `init` path) —
  but it resolves **env vars before ever touching the keyring**, so with
  `CFL_API_TOKEN` set the keyring is never opened (and this container has no
  keyring to open anyway).
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
- **cfl (Confluence) wants three env vars.** `CFL_URL` (e.g.
  `https://your-site.atlassian.net`), `CFL_EMAIL`, and `CFL_API_TOKEN`. The
  token is the **same Atlassian API token** as `JIRA_API_TOKEN`, but cfl does
  **not** read `JIRA_API_TOKEN` itself. Convenience: `start-container.sh`
  derives `CFL_API_TOKEN` from `JIRA_API_TOKEN` (and vice versa) at start, so
  passing either one token env var covers both CLIs; `CFL_URL`/`CFL_EMAIL`
  are still individually required. Missing any of the three and cfl fails on
  first use; there is no caged-managed fallback.
- **Or inject the shared `ATLASSIAN_*` trio once.** The operator may instead
  pass `ATLASSIAN_HOST` (site host, e.g. `your-site.atlassian.net` —
  `https://` is added automatically), `ATLASSIAN_EMAIL`, and
  `ATLASSIAN_API_TOKEN`. `start-container.sh` forwards all three verbatim,
  and the image entrypoint (`scripts/env-atlassian.sh`, baked into the base,
  sourced by every agent's entrypoint) assigns **inside the container**:
  `CFL_URL` and `JIRA_SERVER` ← `ATLASSIAN_HOST` (normalized to a full https
  URL; `ATLASSIAN_URL` still honored as a legacy alias), `CFL_EMAIL` and
  `JIRA_LOGIN` ← `ATLASSIAN_EMAIL`, `CFL_API_TOKEN` and `JIRA_API_TOKEN` ←
  `ATLASSIAN_API_TOKEN`. Explicit `CFL_*`/`JIRA_*` vars always win over the
  trio. One token env var in any of its three spellings (`JIRA_API_TOKEN`,
  `CFL_API_TOKEN`, `ATLASSIAN_API_TOKEN`) therefore covers both CLIs.
  Caveat: jira-cli still needs its config file to **exist** (one-time
  `jira init`); the mapped `JIRA_*` env vars only override the config's
  server/login/token values at runtime (jira-cli resolves env first), so
  host/email/token changes don't require re-running `jira init`.
- **cfl's `config show` keyring noise is expected.** With an env token set,
  `cfl config show` may print `API Token: configured (source: keyring error:
  ... secret-service unavailable ...)`. Commands still authenticate from env;
  the keyring line is diagnostic only. Never run `cfl set-credential` here
  (no keyring to store into); if a stored token is ever wanted, the escape
  hatch is `ATLASSIAN_CLI_KEYRING_BACKEND=file`, not the OS keyring.
- **`cfl init` is optional.** Env-only usage needs no config file. Non-secret
  defaults (default space) can be persisted headlessly later:
  `cfl init --non-interactive --url "$CFL_URL" --email "$CFL_EMAIL" --token-stdin`.

## Accepted / out of scope

* No fail-fast check for a missing token at container start — by explicit
  request; failures surface when the CLI is actually used.
* No OS keyring: no D-Bus / Secret Service in the container; not needed since
  all four CLIs run env-token-only (cfl resolves env before its keyring path).
* glab `git_protocol: ssh` is dead config — the container ships no ssh
  binary. Log in with `--git-protocol https`.
* The `git credential` helper is not configured — `gh auth setup-git` is not
  used here; HTTPS push/fetch over git uses separate credentials.

## Verify

```sh
glab api user          # works from GITLAB_TOKEN alone, no login, no config seed
gh api user            # works from GH_TOKEN alone
jira version           # metadata command, token not required
cfl me                 # needs CFL_URL/CFL_EMAIL/CFL_API_TOKEN (live site)
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

With the shared `ATLASSIAN_*` trio injected, the entrypoint also sets
`JIRA_SERVER`/`JIRA_LOGIN`/`JIRA_API_TOKEN` from it, and jira-cli resolves
env before config — so the values used at runtime come from the trio, and
`jira init` only needs to run once to create the (non-secret) config file.
`jira init` itself still needs the explicit `--server`/`--login` flags (it
only reads `JIRA_AUTH_TYPE` from env).

cfl (Confluence) needs **no setup at all** when run env-only — and the
token is optional: `start-container.sh` derives `CFL_API_TOKEN` from
`JIRA_API_TOKEN` at start, so only `CFL_URL`/`CFL_EMAIL` are strictly new:

```sh
export CFL_URL="https://mysite.atlassian.net"
export CFL_EMAIL="you@example.com"
# CFL_API_TOKEN is auto-derived from JIRA_API_TOKEN by start-container.sh;
# set it explicitly to override (e.g. a scoped token).
cfl me                                   # verify
cfl page view 12345                      # read a page as Markdown
```

Or inject the shared trio instead — it covers both CLIs with three vars, and
the entrypoint does the assignment inside the container (`https://` is added
to a bare host automatically):

```sh
export ATLASSIAN_HOST="mysite.atlassian.net"   # bare host is fine
export ATLASSIAN_EMAIL="you@example.com"
export ATLASSIAN_API_TOKEN="..."               # same Atlassian API token
cg pi start                                    # cfl + jira both work
```

### Complete init commands (one-time, inside the container)

Run inside a container started with the `ATLASSIAN_*` trio — the entrypoint
has already exported `JIRA_SERVER`/`JIRA_LOGIN`/`JIRA_API_TOKEN` and
`CFL_URL`/`CFL_EMAIL`/`CFL_API_TOKEN` from it:

```sh
# jira-cli — required once. Validates against the live instance; the token is
# read from env automatically, but --server/--login must be explicit (v1.7.0
# init only falls back to env for JIRA_AUTH_TYPE).
jira init --installation cloud \
  --server "$JIRA_SERVER" --login "$JIRA_LOGIN" \
  --auth-type basic --force
jira project list                    # verify

# cfl — optional: env-only works with zero setup (cfl me already verifies);
# init only persists non-secret defaults such as default_space.
cfl init --non-interactive \
  --url "$CFL_URL" --email "$CFL_EMAIL" --token-stdin <<<"$CFL_API_TOKEN"
```

`jira init` writes `$XDG_CONFIG_HOME/.jira/.config.yml` (gitignored
`seed/.config/.jira/`); `cfl init` writes the non-secret config under
`seed/.config/` (gitignored). Afterward, server/login/token at runtime come
from the mapped env, so rotations need no re-init. `--force`/
`--non-interactive` skip/replace prompting; `--project`/`--board` set the
jira defaults. The container has no OS keyring and cfl resolves env before
the keyring, so neither command stores the token — the keyring line in
`cfl config show` is expected diagnostic noise. `cfl init --non-interactive
--token-stdin` is the headless variant documented against cfl v1.3.96; run
`cfl init --help` if a flag is rejected.