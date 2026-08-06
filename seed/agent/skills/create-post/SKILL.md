---
name: create-post
description: Scaffold a new blog post in the content/ directory with the correct filename and required frontmatter. Use when the user asks to create, start, or write a new post about a topic. Places a numbered NN-slug.lang.md file with title/slug/created-time metadata and stops, leaving the body for the user to fill.
---

# Create Post

Scaffold a new post in `content/` that follows this repo's conventions. This
skill produces the file with correct naming and frontmatter only — it does not
draft the body.

## When to use

- The user asks to create / start / write a new post on a given topic.
- Do NOT use for editing existing posts or the `thoughts` route.

## Steps

### 1. Gather inputs

Determine from the user's request:

- **topic** — what the post is about.
- **language** — `.zh` (Chinese) or `.en` (English). Ask if unclear. Omit the
  suffix if the post is language-neutral.
- **slug** — short kebab-case, ASCII, lowercase, no spaces. For Chinese
  topics, transliterate to a short English slug.
- **format** — use `.mdx` only if the post needs imported components;
  otherwise `.md`.

### 2. Pick the sequence number

Glob `content/*.{md,mdx}` and find the highest two-digit leading number `NN`.
Use `NN + 1`, zero-padded to 2 digits. The number is an ordering hint — do not
reuse or fill gaps.

### 3. Filename

`{NN}-{slug}.{lang}.md` (or `.mdx`), placed directly in `content/`. Use a
sibling subdirectory only if the post needs bundled assets (see
`content/18-sayonara-underlines/`).

### 4. Frontmatter

YAML, delimited by `---`.

Required:

| field          | value                                                                                                          |
| -------------- | -------------------------------------------------------------------------------------------------------------- |
| `title`        | Post title. Quote it if it contains `:`, `?`, `"`, `#`, or leading/trailing spaces.                            |
| `slug`         | The filename **without** the extension (e.g. `34-my-topic.zh`). Becomes the URL — must be URL-safe and unique. |
| `created-time` | Today's date, `YYYY-MM-DD`, unquoted (e.g. `2026-07-04`).                                                      |

Optional:

| field          | value                                                                                                     |
| -------------- | --------------------------------------------------------------------------------------------------------- |
| `updated-time` | `YYYY-MM-DD`. Add only when revising an existing post.                                                    |
| `tags`         | Inline array, e.g. `["dev"]` or `["体验", "Notion"]`. Omit entirely if none.                              |
| `status`       | `["WIP"]` for work-in-progress drafts. Auto-prefixes `[WIP]` in the listing and pins the post to the top. |

### 5. Body

Write only the H1, then stop:

```
# {Title}
```

Leave a blank line after. Do not draft body content. Optionally add a GitHub
admonition (`> [!NOTE]`) if the user indicates AI-assisted content — a pattern
used in several existing posts.

## Template

```markdown
---
title: "{Title}"
slug: {NN}-{slug}.{lang}
created-time: {YYYY-MM-DD}
tags: ["{tag}"]
---

# {Title}
```

Drop the `tags` line when there are no tags. Use `slug: wip` only for
placeholder WIP posts that don't have a real slug yet.

## Why these fields

- `src/content.config.ts` loads `content/**/*.{md,mdx}` into the `blog`
  collection with **no schema** — frontmatter is enforced by usage, not
  validation.
- `src/pages/posts/[...slug].astro` routes by `slug` and renders `title`,
  `created-time`, `updated-time`, `tags`.
- `src/components/BlogList.astro` renders `title`, `tags`, and prefixes
  `[WIP]` when `status` includes `WIP`.
- `src/utils/freshness.ts` sorts by `status` (WIP first), then recency from
  `created-time` / `updated-time`, then `slug`.

## Verify (optional)

Run `npm run build` to confirm the new file parses and routes correctly.
