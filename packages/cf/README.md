# cf — Confluence page reader (manual for agents)

`cf` turns a Confluence Cloud page URL into the page's **full content as
Markdown** on stdout — exactly what you need when a requirement doc, an ADR,
API spec, meeting note, or onboarding guide lives on the wiki. It does the
boring work for you: extracting the page ID from the URL, authenticating,
fetching the right body representation, and converting XHTML/ADF to clean
Markdown.

Do **not** reach for `cfl` (the old Confluence CLI — still present in the
image but unsupported here) and do **not** hand-roll Confluence REST calls
with curl. When a page is the target, `cf` is the tool.

## Authentication — nothing for you to do

Credentials are injected as env vars by `start-container.sh` and resolved
automatically. The site comes from the URL itself:

| Need | Resolution (first match wins) |
|---|---|
| site | parsed from the URL — no `CFL_URL` needed |
| email | `CFL_EMAIL` → `ATLASSIAN_EMAIL` |
| token | `CFL_API_TOKEN` → `ATLASSIAN_API_TOKEN` → `JIRA_API_TOKEN` |

Never pass credentials yourself, never write them into files, never put them
in commands. If the tool reports missing credentials, the operator must set
the env vars — see Troubleshooting.

## Usage

```
cf <page-url> [options]
```

The only positional argument is the page URL (see Accepted URL forms).

| Flag | Effect |
|---|---|
| `--no-meta` | omit the metadata line (the `# title` line stays) |
| `--children` | append a `## Child pages` index with links |
| `--show-macros` | keep Confluence macro markers (`[TOC]`, `[INFO]…[/INFO]`) instead of stripping wrappers |
| `--raw storage\|adf` | print the raw body (storage XHTML or ADF JSON) instead of converted Markdown |
| `-h`, `--help` | help text |
| `--version` | version |

## Output contract

What `cf` prints to **stdout** for a successful read:

1. `# <page title>` (an H1).
2. One metadata line, e.g.:

   ```
   Page: https://eachvector.atlassian.net/wiki/spaces/EMFE/pages/5415665912 · Space: EMFE · Version: 7 · Updated: 2026-09-01 10:00:00 UTC · By: 6012abc… · Body: storage
   ```

   `Body:` tells you which representation the content came from —
   `storage`, or `atlas_doc_format (storage empty)` for ADF-native pages.
   Omit this line with `--no-meta`.
3. A blank line, then the **complete** page body as Markdown.

The body is **never truncated**. An empty page renders as `_(empty page)_`.
Diagnostics (warnings such as "stripped empty macro", errors) go to
**stderr**, never stdout — you can pipe stdout straight into a file.

## Accepted URL forms

```
https://<site>.atlassian.net/wiki/spaces/<KEY>/pages/<ID>
https://<site>.atlassian.net/wiki/pages/viewpage.action?pageId=<ID>
https://<site>.atlassian.net/wiki/pages/<ID>
```

A bare numeric page ID is rejected (the site must come from the URL).

## Exit codes

| Code | Meaning | What to do |
|---|---|---|
| 0 | success | — |
| 1 | usage / bad URL | check the URL and flags |
| 2 | auth / missing credentials | credentials are wrong or not injected — ask the user |
| 3 | API / network error | retry; mention the error text |
| 4 | not found (404) | page missing **or hidden by permissions** — ask the user to confirm access |
| 5 | rate-limited (429) | wait and retry later |

## What the conversion preserves (and what it drops)

Default mode (no `--show-macros`):

- `code` / `noformat` macros → fenced code blocks with the language tag.
- Tables → GFM tables. Headings, lists, quotes, emphasis → regular Markdown.
- Internal page links → real Markdown links when the target ID is known,
  `[[SPACE:Title]]` wiki syntax otherwise.
- Attachments and images → download URLs of the form
  `https://<site>/wiki/download/attachments/<pageId>/<file>` — you can fetch
  them yourself if the content matters.
- `info` / `note` / `warning` / `tip` / `expand` macros → their **content is
  kept**, the wrapper is dropped. Empty macros are removed (a warning goes to
  stderr naming the macro).
- Mentions → `@<userkey>`; emoji are dropped.

With `--show-macros`, macro content is wrapped in readable markers:
`[INFO]…[/INFO]`, `[WARNING]…[/WARNING]`, `[TOC]`, `[EXPAND title="…"]…[/EXPAND]`.

For ADF-native pages the metadata line says the body came from
`atlas_doc_format`; the built-in ADF renderer covers headings, paragraphs,
lists, tables, code, quotes, panels, expand, and media.

If you need the exact unconverted body, use `--raw storage` or `--raw adf`.

## Examples

```sh
cf https://eachvector.atlassian.net/wiki/spaces/EMFE/pages/5415665912
cf https://…/pages/5415665912 --no-meta          # content only
cf https://…/pages/5415665912 --children         # + child-page index
cf https://…/pages/5415665912 --show-macros      # keep macro markers
cf https://…/pages/5415665912 --raw storage      # raw storage XHTML
```

## Troubleshooting

- **`cf: command not found`** — the package is not installed; the base image
  needs rebuilding. Tell the user.
- **`cf: no credentials found in the environment`** — the operator did not
  inject `ATLASSIAN_EMAIL` + `ATLASSIAN_API_TOKEN` (or the `CFL_*` /
  `JIRA_API_TOKEN` spellings). Ask the user to set them and restart.
- **401/403** — credentials are wrong or lack access. Ask the user.
- **404** — Confluence hides unauthorized pages as 404: the page may not
  exist, or the credentials cannot see it. Ask the user to confirm access.
- **429** — rate limited; back off and retry.
- Never guess, generate, or brute-force credentials. Stopping and asking the
  user is always the right move.

---

## Maintenance (for humans)

- Tests: `cd packages/cf && npm test` (offline, no credentials).
- Host-side packaging for the caged image: `scripts/package-cf.sh` creates
  `packages/cf/dist/caged-cf-<version>.tgz` with the runtime deps bundled;
  `Containerfile.base` `COPY`s it in and runs `npm install -g`, which is why
  this manual lands at `$(npm root -g)/@caged/cf/README.md` inside the image.