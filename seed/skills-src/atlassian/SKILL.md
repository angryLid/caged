---
name: atlassian
description: "Use for Atlassian work: any *.atlassian.net URL, Jira issue key or Jira operation, or a request to read a Confluence page. Dispatch Jira targets to jira (jira-cli) and Confluence targets to cf; read the relevant manual before running a command."
---
# Atlassian

Use the installed CLI for the target product:

- `jira` (`jira-cli`) for Jira objects and operations.
- `cf` for reading Confluence Cloud pages as Markdown.

## Procedure

1. **Classify the target.** Apply the dispatch table before choosing a command.
2. **Read the tool manual.** For Jira, read [`references/jira-cli.md`](references/jira-cli.md). For Confluence, read `$(npm root -g)/@caged/cf/README.md`.
3. **Check write intent.** Before any command that changes remote state, tell the user exactly what will change and wait for explicit confirmation. Read-only commands need no confirmation.
4. **Run the narrowest documented command** that answers the request.
5. **Report the result or actionable failure.** Preserve relevant command output and follow the selected manual's troubleshooting guidance.

Completion means the correct CLI was selected, its manual was consulted, the request completed or its actionable failure was reported, and every remote write had explicit confirmation first.

## Dispatch

| Target or intent | CLI |
|---|---|
| Jira issue key such as `ABC-1234` | `jira` |
| Jira `/browse/` URL, issue search, project, board, sprint, epic, release, backlog, or worklog | `jira` |
| Confluence `/wiki/` URL or request to read a wiki page | `cf` |
| Bare Confluence page ID | Ask for a full page URL; `cf` needs the site from the URL |

The URL test is deterministic: `/browse/` means Jira and `/wiki/` means Confluence. A Jira issue key always means Jira. Do not send a Confluence page to `jira`, or a Jira issue to `cf`.

## Safety and failures

Before Jira creates, edits, transitions, comments on, links, assigns, clones, or otherwise changes a remote object, obtain explicit user confirmation immediately before execution.

Credentials are injected into the environment and consumed by the CLIs. Never pass credentials as arguments, write them to files, print them, or guess them. If a command reports missing credentials, authentication, authorization, initialization, configuration, or access errors, stop and ask the user to fix the environment or permissions. Follow the selected manual for missing-command, not-found, and rate-limit errors.

Use `cf` rather than the unsupported `cfl` binary for Confluence reads. Use the CLIs rather than hand-written Atlassian HTTP requests.
