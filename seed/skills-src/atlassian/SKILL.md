---
name: atlassian
description: "Atlassian is in play — activate this skill when any of these shows up: (1) a *.atlassian.net URL or domain, issue links (https://<site>.atlassian.net/browse/ABC-1234) or wiki links (https://<site>.atlassian.net/wiki/...) — handle the linked object with the CLI, not curl; (2) a read/view intent on an issue key such as ABC-1234 (e.g. 阅读 / 查看 / 了解 X-123, 'view X-123'); (3) any Jira operation (create/edit/search/transition work items, comment, link, assign, clone) or managing projects, boards, sprints, epics, releases; (4) any Confluence READ intent — a wiki page URL, a page ID, 'read this page' — handled with `cf`. Dispatch by product: Jira objects → `jira` (jira-cli), Confluence page reads → `cf` — the dispatch table is at the top of this skill."
---
# atlassian — Jira (jira-cli) + Confluence reading (cf)

Two tools for Atlassian Cloud, installed in caged and authenticated
transparently via env vars injected at container start — the agent never
handles credentials:

- **`jira` (jira-cli)** — Jira work: issues, epics, sprints, boards, projects, releases.
- **`cf`** — Confluence page reading: paste a wiki URL, get the full page as Markdown.

Confluence is **read-only** in this setup: `cf` reads pages. (The older `cfl`
binary is still installed in the image but is neither used nor documented
here — prefer `cf` for everything you used `cfl` to read.)

## Dispatch: which tool?

Pick the tool by the **product the target object lives in** — decide before
reaching for a command:

| The target is… | Tool | Typical commands |
|---|---|---|
| A **Jira object** — an issue key (`ABC-1234`), issue search, project, board, sprint, epic, release, backlog, worklog, or any `/browse/` URL | `jira` | `jira issue view/list/create/edit/move/comment/link/assign/clone`, `jira epic …`, `jira sprint …`, `jira board list`, `jira project list`, `jira release list` |
| A **Confluence page to read** — any `/wiki/…` URL (spaces/pages, viewpage.action), a page ID to view, "read this wiki page" | `cf` | read the tool's manual first (below) |

**One-token test:** `/browse/` → `jira`; `/wiki/` → `cf`. An issue key like
`ABC-1234` is always Jira; a space key (`DEV`, `~USERSPACE`) or a numeric page
ID is always Confluence.

## Documentation

Read a tool's documentation **before** using it:

- Jira → [`jira.md`](references/jira-cli.md)
- Confluence (`cf`) → `cf` ships its own agent-facing manual with the
  installed package. Read it from the global npm modules:

  ```sh
  cat "$(npm root -g)/@caged/cf/README.md"
  ```

  The manual covers everything: usage and options, the exact stdout format,
  accepted URL shapes, exit codes, what the conversion preserves or drops,
  and what to do when something fails. If `cf` is not on PATH, the package
  is not installed — ask the user to rebuild the base image
  (`scripts/build-caged-base.sh`).

## Auth is invisible

Both tools authenticate through env vars the operator injects at container
start — the agent just runs the tool:

- `start-container.sh` maps the shared `ATLASSIAN_HOST` / `ATLASSIAN_EMAIL` /
  `ATLASSIAN_API_TOKEN` trio (or `JIRA_API_TOKEN`) onto the CLI vars.
- `cf` resolves its own credentials from `CFL_EMAIL` + `CFL_API_TOKEN`
  (falling back to `ATLASSIAN_EMAIL` / `ATLASSIAN_API_TOKEN` /
  `JIRA_API_TOKEN`) and derives the site from the URL itself.

No secret ever touches disk: no login, no keyring, no config step for `cf`.

**ATTENTIONS** You may encounter errors like "need initialization", "invalid
token", "no credentials found in the environment", 401/403/404, or a missing
`cf` command. Stop immediately and ask the user to provide or fix the
credentials — do not attempt to guess or brute-force credentials. `cf`'s
manual (above) explains every error class and the right response.