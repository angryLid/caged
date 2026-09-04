---
name: atlassian
description: "Atlassian is in play — activate this skill when any of these shows up: (1) a *.atlassian.net URL or domain, issue links (https://<site>.atlassian.net/browse/ABC-1234) or wiki links (https://<site>.atlassian.net/wiki/...) — handle the linked object with the CLI, not curl; (2) a read/view intent on an issue key such as ABC-1234 (e.g. 阅读 / 查看 / 了解 X-123, 'view X-123'); (3) any Jira operation (create/edit/search/transition work items, comment, link, assign, clone) or managing projects, boards, sprints, epics, releases; (4) any Confluence operation (create/edit/search pages, comment, link, spaces, attachments) or wiki workflows. Dispatch by product: Jira objects → `jira` (jira-cli), Confluence objects → `cfl` (atlassian-cli) — the dispatch table is at the top of this skill."
---
# atlassian — Jira + Confluence CLI

Two sibling CLIs for Atlassian Cloud, both preinstalled in caged and
authenticated by the same Atlassian API token:

- **`jira` (jira-cli)** — Jira work: issues, epics, sprints, boards, projects, releases.
- **`cfl` (atlassian-cli)** — Confluence wiki: spaces, pages, attachments, search.

## Dispatch: which CLI?

Pick the CLI by the **product the target object lives in** — decide before
reaching for a command:

| The target is… | CLI | Typical commands |
|---|---|---|
| A **Jira object** — an issue key (`ABC-1234`), issue search, project, board, sprint, epic, release, backlog, worklog, or any `/browse/` URL | `jira` | `jira issue view/list/create/edit/move/comment/link/assign/clone`, `jira epic …`, `jira sprint …`, `jira board list`, `jira project list`, `jira release list` |
| A **Confluence object** — a wiki page, space, attachment, any `/wiki/…` URL, CQL search, macro or wiki-link content | `cfl` | `cfl page view/create/edit/copy/delete`, `cfl space list`, `cfl search`, `cfl attachment …` |
| **Both at once** (e.g. a Jira ticket citing a Confluence page) | one of each | Jira side → `jira`, wiki side → `cfl` |

**One-token test:** `/browse/` → `jira`; `/wiki/` → `cfl`. An issue key like
`ABC-1234` is always Jira; a space key (`DEV`, `~USERSPACE`) or a numeric page
ID is always Confluence.

Then read **only** the reference for the CLI you dispatched to:

- Jira → [`jira.md`](references/jira-cli.md)
- Confluence → [`cfl.md`](references/cfl.md)

## Shared auth

Both CLIs use the same Atlassian API token, passed in as container env vars —
neither stores a secret in this container:

| CLI | Env vars | Config prerequisite |
|---|---|---|
| `jira` | `JIRA_API_TOKEN` | one-time `jira init` (site URL, login, default project/board) |
| `cfl` | `CFL_URL` + `CFL_EMAIL` + `CFL_API_TOKEN` (shared `ATLASSIAN_*` fallbacks) | none — env-only works |

**ATTENTIONS** You may encounter errors like "need initialization" or "invalid token". Stop immediately and ask the user provide credentials for you to grant access. Do not attempt to guess or brute-force credentials.