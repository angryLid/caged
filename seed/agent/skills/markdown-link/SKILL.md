---
name: markdown-link
description: Read the <title> of a given URL and emit a Markdown link `[Title](url)`. Use when the user wants to turn a bare URL into a titled Markdown link for a post or notes file.
---

# Markdown Link

Fetch the page `<title>` for a given URL and produce a Markdown inline link.

## When to use

- The user provides a URL and wants it turned into a Markdown link.
- The user is writing a post / notes and asks to "link this", "title this
  URL", or "fetch the title" of a page.

## Steps

1. Run `node ~/.pi/agent/skills/markdown-link/fetch-title.js "<url>"`.
2. The script prints a single Markdown link to stdout:
   `[Page Title](https://example.com/path)`.
3. Insert that link into the target Markdown file at the desired location.
   If the user did not name a file, return the link and let them place it.

## Fallback order

The script resolves the title in this order, so it works on pages where
`<title>` is absent or empty:

1. `<title>` element
2. `<meta property="og:title">` content
3. First `<h1>` text

## Notes

- Whitespace and newlines in the title are collapsed to single spaces.
- `[`, `]`, and `\` in the title are backslash-escaped so the link renders
  correctly.
- The URL is normalized via `new URL().href` (adds a default scheme if
  missing, resolves relative paths). Pass a full URL for best results.
- Errors (non-2xx, no title found) go to stderr with a non-zero exit code;
  stdout only ever contains the finished link.
