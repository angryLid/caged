# cf — Confluence page reader

`cf` reads one Confluence Cloud page and writes its complete content as Markdown to stdout. It is intended for agents that need to inspect a wiki page without manually calling the Confluence API.

## Quick start

```sh
cf https://<site>.atlassian.net/wiki/spaces/EMFE/pages/5415665912
```

The output contains the page title, a metadata line, and the full converted body. The body is never truncated.

## Command reference

```text
cf <confluence-page-url> [options]
```

| Option | Result |
|---|---|
| `--no-meta` | Omit the metadata line; keep the title. |
| `--children` | Append a sorted `Child pages` section with links. Ignored for raw output. |
| `--show-macros` | Preserve readable markers for supported Confluence macros, such as `[TOC]` and `[INFO]...[/INFO]`. Applies to storage-format pages. |
| `--raw storage` | Print the unconverted storage XHTML body. |
| `--raw adf` | Print the unconverted Atlas Document Format body. |
| `-h`, `--help` | Print help. |
| `--version` | Print the installed version. |

`--raw` accepts exactly `storage` or `adf`. A page normally provides one body representation; requesting a different representation exits with an API/network error.

## Accepted URLs

```text
https://<site>.atlassian.net/wiki/spaces/<KEY>/pages/<ID>
https://<site>.atlassian.net/wiki/pages/viewpage.action?pageId=<ID>
https://<site>.atlassian.net/wiki/pages/<ID>
```

The site is always derived from the URL. A numeric page ID alone is therefore insufficient.

## Output

A successful normal read has this shape:

```text
# <page title>

Page: https://<site>.atlassian.net/wiki/spaces/<KEY>/pages/<ID> · Space: <KEY> · Version: <N> · Updated: <timestamp> · By: <account ID> · Body: storage

<complete page body as Markdown>
```

The metadata line is omitted by `--no-meta`. `Body: storage` means the page was read from Confluence storage XHTML. `Body: atlas_doc_format (storage empty)` means the page had no storage body and was read from ADF instead. Empty pages render as `_(empty page)_`.

Diagnostics and warnings go to stderr, so stdout can be redirected directly to a Markdown file. For example:

```sh
cf https://<site>.atlassian.net/wiki/spaces/EMFE/pages/5415665912 --no-meta > page.md
```

## Conversion

The default conversion produces Markdown and preserves the following content:

- `code` and `noformat` macros as fenced code blocks, including language tags when available.
- Tables as GFM tables; headings, lists, quotes, and emphasis as Markdown.
- Known internal page links as Markdown links; unresolved links as `[[SPACE:Title]]`.
- Attachments and images as Confluence download URLs, for example `https://<site>.atlassian.net/wiki/download/attachments/<pageId>/<file>`.
- The content of `info`, `note`, `warning`, `tip`, and `expand` macros. Their wrappers are removed by default; empty macros are removed with a stderr warning.
- Mentions as `@<userkey>`.

Emoji are omitted. With `--show-macros`, supported macro wrappers become readable markers such as `[INFO]...[/INFO]`, `[WARNING]...[/WARNING]`, and `[EXPAND title="..."]...[/EXPAND]`. ADF pages use the built-in ADF renderer for headings, paragraphs, lists, tables, code, quotes, panels, expands, and media.

Use `--raw storage` or `--raw adf` when the exact source representation is required.

## Exit codes and recovery

| Code | Meaning | Action |
|---:|---|---|
| `0` | Read succeeded. | — |
| `1` | Invalid arguments or URL. | Check the command and use one of the accepted URL forms. |
| `2` | Authentication failed. | Stop immediately and notify the user; the agent cannot resolve authentication problems. |
| `3` | API or network failure. | Retry and inspect the stderr diagnostic. |
| `4` | Page not found or inaccessible. | Confirm that the page exists and that the credentials can view it; Confluence may hide unauthorized pages as 404. |
| `5` | Rate limited by Confluence. | Wait before retrying. |

`cf: command not found` means the package is not installed in the image; rebuild the caged base image. Never place credentials in commands or files, and never guess credentials.
