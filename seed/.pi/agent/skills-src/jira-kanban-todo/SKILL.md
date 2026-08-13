---
name: jira-kanban-todo
description: Read the top N "To Do" tasks of a Jira kanban board from a board link (e.g. https://.../projects/UXM/boards/9752). Use when the user pastes a Jira board link or asks to list the first/前几条 To Do tasks of a kanban board — do not fall back to a plain `project = X AND status = "To Do"` query, which is scoped wrong (the board is scoped by its saved filter, not the project).
---

# jira-kanban-todo

acl i has **no board-column listing command** (only `board view` / `list-projects` /
`list-sprints`, and its token is stored encrypted, so curl bypass of the Agile API
is impossible). Replicate the board's To Do column via its **saved filter + JQL**.

## Key facts

- Kanban board ≈ a saved filter. Find the filter, query through it.
- Board column top = `ORDER BY rank DESC`. `rank ASC` is the mirror — the page
  order is reversed (verified on board 9752: rank DESC == created DESC == key DESC
  for tickets queued by creation).
- `--filter` and `--jql` can't combine, but JQL `filter = <id>` works.

## Steps

1. **Parse board id** from the URL: `.../boards/9752` → `9752`.

2. **Confirm kanban + name keywords**:
   `acli jira board view --id <id> --json` → fields `name`, `type`, `location`.
   Done when `type` is `kanban` (scrum → see Alternative below) and you have the
   brand words from `name`.

3. **Locate the board's saved filter**:
   `acli jira filter search --name "<brand word from board name>" --json`
   Pick the filter whose `name` best matches the board name (e.g. board
   "Bettomax, Gbets (Betnova), Winypto- WO: Mind" → filter 68050 "Bettomax,
   Winypto- Mind's filter"). Done when exactly one filter matches the board
   theme; if several, compare their issue summaries against the board name.

4. **Verify scope + enumerate statuses** (also tells you which statuses the
   To Do column holds):
   `acli jira workitem search --jql 'filter = <id>' --fields key,status --paginate --csv | tail -n +2 | cut -d, -f2 | sort | uniq -c | sort -rn`
   Default assumption: To Do column = status `"To Do"`. If search results look
   off-theme or the user's column differs, adjust the status set.

5. **Top N To Do, board order**:
   `acli jira workitem search --jql 'filter = <id> AND status = "To Do" ORDER BY rank DESC' --fields "key,summary,priority" --limit <N> --csv`

6. **Cross-check direction before reporting**: rerun step 5 with
   `ORDER BY created DESC` and `ORDER BY key DESC`. All three coinciding = trust
   the order. If they diverge, ask the user which direction matches their board
   and calibrate the ORDER BY for this board.

## Caveats

- Column↔status mapping is an **assumption** (`"To Do"`); the true mapping lives
  in the Agile API `columnConfig`, which acli cannot reach (no raw REST, token
  encrypted). A column may hold several statuses (Backlog, Ready for Dev, …).
- Filter match by name is heuristic — not an official board→filter link.
- Board-scoped means **not** `project = X`; the filter may span several projects.

## Alternative: scrum boards

Kanban has no sprints. For a scrum board,
`acli jira board list-sprints --id <id>` → then
`acli jira sprint list-workitems --sprint <sid> --board <id>`; add
`--jql 'status = "To Do"'` for the column filter.
