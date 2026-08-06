---
name: bgm-metadata
description: Fetch anime metadata from bgm.tv (Bangumi) by scraping the SSR HTML page, outputting structured info and a CSV snippet for the anime table
---

Scrape metadata from a bgm.tv (Bangumi / 番组计划) subject page using jsdom.

The extraction logic mirrors the `bookmark.user.js` userscript config.ts exactly — it parses the SSR HTML with the same DOM queries.

Fields extracted: **Name** (Chinese name, falls back to title), **原名** (original Japanese title), **分类** (tags), **开播时间** (air date), **制作公司** (animation studio), **rating**, **URL**.

## Usage

Run: `node ~/.pi/agent/skills/bgm-metadata/fetch.js "<bgm-url>"`

For raw JSON: `node ~/.pi/agent/skills/bgm-metadata/fetch.js "<bgm-url>" --json`

### Supported input formats

- `https://bgm.tv/subject/12345`
- `https://bangumi.tv/subject/12345`
- `https://chii.in/subject/12345`
- A raw numeric subject ID

### Output columns (matching anime-from-notion.csv)

| Column   | Source                                                          |
| -------- | --------------------------------------------------------------- |
| Name     | `中文名` from `ul#infobox`, falls back to `#headerSubject h1 a` |
| 原名     | title (if different from Chinese name)                          |
| 分类     | `.subject_tag_section .l.meta span`                             |
| 开播时间 | `开始` date from `ul#infobox`, formatted yyyy-MM-dd             |
| 制作公司 | `.tip` text starting with `动画制作` → `a.l`                    |
| rating   | `.global_rating .number`                                        |
