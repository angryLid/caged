---
name: jira-kanban-todo
description: Read the top N "To Do" tasks of a Jira kanban board from a board link (e.g. https://.../projects/UXM/boards/9752). Use when the user pastes a Jira board link or asks to list the first/前几条 To Do tasks of a kanban board — do not fall back to a plain `project = X AND status = "To Do"` query, which is scoped wrong (the board is scoped by its saved filter, not the project).
---

# jira-kanban-todo

jira-cli has a native `board` command group and raw-JQL `issue list`, so we can
resolve a kanban board's To Do column without the acli-era hacks (acli had no
board→column listing and no env token, forcing a saved-filter + JQL
workaround). A board's column set still lives in the Agile API `columnConfig`,
which the CLI does not expose directly — but its **saved filter + JQL** give a
faithful, reproducible reading with standard tooling.

## Key facts

- Kanban board ≈ a saved filter. Find the filter (from the board or via
  search), query through it.
- Board column top = `ORDER BY rank DESC` in jira-cli is the board's custom
  ordering  (`rank` ascending when read top-down). For tickets queued purely by
  creation, rank order coincides with created/key order (verified on board
  9752); `--order-by rank --reverse` matches the UI.
- `issue list -q 'filter = <id> ...'` runs raw JQL; scope the query inside the
  JQL so the configured default project does not narrow the board filter.

## Steps

1. **Parse board id** from the URL: `.../boards/9752` → `9752`.

2. **Confirm the board + find its project.** Board id 9752 is Uitvoering/UXM;
   resolve against the configured instance:

   ```bash
   jira board list --plain                  # name + id of every board you can see
   jira serverinfo                          # confirms instance / site name keywords
   ```

   If the board is not in the default config, query its issues directly with a
   key-based JQL that the board's saved filter would scope to (or set the board
   via `jira init --board "<name>"` / `-c` for a project config).

3. **Locate the board's saved filter.** The board's To Do column scope is its
   saved filter. Search filters by a distinctive board name word:

   ```bash
   jira issue list --raw -q 'filter = 68050'   # or whichever filter id
   ```

   Filter ids are not directly enumerable via `jira` (no `filter search`
   subcommand); if no filter id is known, use the board name keywords from the
   URL/project to search issues, or ask the user for the filter name. Prefer a
   filter whose issue set (summaries) matches the board's theme.

4. **Verify scope + enumerate statuses.** Confirm which statuses the To Do
   column holds before assuming `"To Do"`:

   ```bash
   jira issue list --csv -q 'filter = <id>' --plain --columns key,status \
     | tail -n +2 | cut -f2 | sort | uniq -c | sort -rn
   ```

   (`--csv`/`--plain --delimiter ,` also works; the above uses tab). Default
   assumption: To Do column = status `"To Do"`.

5. **Top N To Do, board order:**

   ```bash
   jira issue list --plain --columns key,summary,priority \
     -q 'filter = <id> AND status = "To Do" ORDER BY rank DESC' \
     --paginate <N>
   ```

   For a clean machine-readable list use `--raw` and read `.issues[].key/.fields.summary`.

6. **Cross-check direction before reporting.** Rerun step 5 with
   `ORDER BY created DESC` and `ORDER BY key DESC`. All three coinciding = trust
   the order. If they diverge, ask the user which direction matches their board
   and calibrate the ORDER BY for this board.

## Caveats

- Column↔status mapping is an **assumption** (`"To Do"`); the true mapping
  lives in the Agile API `columnConfig`, which jira-cli does not expose (no raw
  `/rest/agile/1.0/board/{id}/configuration` command). A column may hold several
  statuses (Backlog, Ready for Dev, …).
- Filter match by name is heuristic — not an official board→filter link.
- Board-scoped means **not** `project = X`; the filter may span several projects,
  so keep the filter id in the JQL rather than leaning on the config project.
- `jira` is env-token driven (`JIRA_API_TOKEN`); if it errors with a token hint,
  the operator must set the env var — do not attempt `curl` against the Agile
  API, the same invocation norms as acli apply for secrets.

## Alternative: scrum boards

Kanban has no sprints. For a scrum board,
`jira sprint list` → pick a sprint id → `jira sprint list <sid> -a$(jira me)`;
add `-s"To Do"` for the column filter, e.g.

```bash
jira sprint list --plain --columns id,name,state
jira sprint list <sid> --plain --columns key,status,assignee -s"To Do"
```