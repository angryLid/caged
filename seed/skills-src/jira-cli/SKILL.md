---
name: jira-cli
description: "Reference guide for jira-cli (github.com/ankitpokhrel/jira-cli) - a community-maintained, MIT-licensed Jira command-line client for Jira Cloud and Jira Server/Data Center. Use this skill when the user wants to perform Jira operations (create/edit/search/transition work items, comment, link, assign, clone), manage projects, boards, sprints, epics, releases, or automate Jira workflows from the terminal. Covers the `jira` binary: issue (create, edit, list, view, assign, move, comment, link, clone, delete, worklog), epic, sprint, board, release, project, and search with raw JQL. Output is scripting-friendly (--plain, --raw JSON, --csv). Auth is env-token based (JIRA_API_TOKEN), no persisted login needed."
compatibility: "Requires the `jira` binary (github.com/ankitpokhrel/jira-cli) installed and a config generated with `jira init` (written to jira-cli's default location, $XDG_CONFIG_HOME/.jira/.config.yml). Auth comes from the JIRA_API_TOKEN env var (never stored on disk); optional env vars: JIRA_AUTH_TYPE (basic|bearer), JIRA_CONFIG_FILE (alternate config path)."
metadata:
  required_tools: "jira"
  optional_env_vars: "JIRA_API_TOKEN, JIRA_AUTH_TYPE, JIRA_CONFIG_FILE"
---

# jira-cli Reference

## Prerequisites

This skill requires the `jira` binary (https://github.com/ankitpokhrel/jira-cli)
to be installed and a generated config file. The binary is NOT bundled with
this skill. Verify availability:

```bash
jira version        # prints (Version="...", GitCommit=..., Platform=...)
jira --help         # command overview
```

If not configured yet, run `jira init` once (see Authentication).

## Authentication

jira-cli is **env-token only** — there is no persisted login, no `auth login`
command, and no token is ever written to disk. Check the token is present
before running commands:

```bash
jira project list   # contact command; fails with a hint if no token
```

- **Token (required):** `JIRA_API_TOKEN` env var — a Jira API token
  (https://id.atlassian.com/manage-profile/security/api-tokens). Basic auth is
  the default; for Data Center PATs set `JIRA_AUTH_TYPE=bearer`.
- **Config (required once):** the instance URL / login / default project live
  in a config file at jira-cli's default location
  (`$XDG_CONFIG_HOME/.jira/.config.yml`; in this container that is the
  gitignored `seed/.config/.jira/.config.yml` — caged does not manage it).
  Generate it with:

  ```bash
  export JIRA_API_TOKEN=...             # init validates against the live site
  jira init --installation cloud \
    --server "https://mysite.atlassian.net" \
    --login "you@example.com" --auth-type basic --force
  ```

  `jira init` calls `GET /rest/api/2/myself` to verify the site and token, so
  it needs a reachable instance and a working token. Add `--project KEY` /
  `--board "<name>"` to set defaults. To use an alternate config, point
  `-c/--config` or `JIRA_CONFIG_FILE` at it (v1.7.0+).

## Output modes (scripting / agents)

`jira issue list` renders an interactive TUI by default — for agents use the
plain/structured flags:

| Flag | Effect |
|---|---|
| `--plain` | plain text rows instead of the TUI |
| `--csv` | CSV rows (v1.7.0+) |
| `--raw` | **full JSON** of the underlying API response (v1.7.0+) |
| `--no-headers` | drop the header row (with `--plain` only) |
| `--no-truncate` | show all columns (with `--plain` only) |
| `--columns key,summary,status` | pick columns (with `--plain` only) |
| `--delimiter <d>` | custom column delimiter, default tab (plain only) |

Examples:

```bash
jira issue list --plain --columns key,status,assignee,summary
jira issue list --csv
jira issue list --raw                       # JSON issues array
jira issue list --plain --no-headers -q 'project = PROJ ORDER BY rank' | cut -f1
```

## Common commands

### Issue

```bash
jira issue list                              # interactive by default
jira issue list -s"To Do" -a$(jira me)       # status + assignee filters
jira issue list -q 'project = PROJ AND status = "In Progress" ORDER BY rank DESC'  # raw JQL
jira issue list --order-by rank --reverse    # board order (rank)
jira issue create -tBug -s"Summary" -yHigh -lbug -b"Description" --no-input
jira issue edit PROJ-1 -s"New summary" --no-input
jira issue assign PROJ-1 "user@example.com"
jira issue move PROJ-1 "In Progress"          # transition by status name
jira issue view PROJ-1                        # detail + linked issues + comments
jira issue view PROJ-1 --comments 5
jira issue comment add PROJ-1 "comment body"
echo "body" | jira issue comment add PROJ-1   # stdin works too
jira issue link PROJ-1 PROJ-2 Blocks
jira issue unlink PROJ-1 PROJ-2
jira issue clone PROJ-1
jira issue delete PROJ-1                       # destructive — confirm first
jira issue worklog add PROJ-1 "2d 3h" --no-input
jira issue worklog add PROJ-1 "10m" --comment "note" --no-input
```

### Epic / Sprint / Board / Release

```bash
jira epic list                        # epics (--table for tabular)
jira epic list PROJ-1                 # issues in an epic
jira epic create -n"Epic name" -s"Summary" -b"Description" --no-input
jira epic add EPIC-1 PROJ-1 PROJ-2    # add issues to epic
jira epic remove PROJ-1
jira sprint list                      # sprints (--table)
jira sprint list --current -a$(jira me)
jira sprint list SPRINT_ID            # issues in a sprint
jira sprint add SPRINT_ID PROJ-1
jira board list                       # boards in the project
jira release list                     # project versions/releases
```

### Project / metadata

```bash
jira project list
jira me                               # current user (email/display name)
jira serverinfo                       # instance info
jira open PROJ-1                      # open in browser
```

## Destructive / impactful operations

- **Destructive (irreversible)**: `jira issue delete`, `jira issue worklog
  delete` (if applicable), bulk deletes. Always show the affected issue keys
  (via a `list` with the same query) and get explicit user confirmation first.
- **Impactful (reversible)**: `jira issue move` (transitions), `jira epic
  remove`, `jira issue assign` changes, `jira sprint add` — confirm before
  mutating when the user did not explicitly ask.

**Agent safety rules:**
1. Never run destructive commands without explicit user confirmation.
2. When bulk-targeting via `-q/--jql`, first run a `list` with the same query
   and show the user what will be affected (use `--plain --columns key,summary`).
3. Prefer `--raw`/`--csv` output to verify targets before destructive changes.
4. Use `--no-input` only when all required params are provided on the command
   line; never assume defaults for untested transitions.
5. `--force` on `jira init` overwrites an existing config — use it only when
   deliberately re-configuring.

## Notes & pitfalls

- `jira issue list -q` runs **raw JQL within the configured project context**;
  filter by project inside the JQL too (`-q 'project = X AND ...'`) when the
  query must not depend on the config default.
- `--paginate <from>:<limit>` — the `from` part is ignored on Jira Cloud's new
  search API (v1.7.0); use `--paginate <limit>` to page with `maxResults`.
- `--order-by rank --reverse` matches the UI/board order (rank ASC top-down).
- `jira issue view` uses a pager (`less`) by default — in a non-TTY agent
  context set `--plain`/pipe, or configure a pager (see project discussion
  #569). Prefer `--raw`/`--csv`/`--plain` for machine consumption.
- `JIRA_CONFIG_FILE` (v1.7.0+) lets you switch configs per invocation:
  `JIRA_CONFIG_FILE=./other.yml jira issue list`.
- Exit codes are non-zero on failure; combine with `--debug` for request
  details. There are no structured/semantic exit codes (unlike glab/gh); parse
  `--raw` JSON for the error body when needed.