#!/usr/bin/env node

/**
 * Fetch the <title> of a web page and emit a Markdown link `[Title](url)`.
 *
 * Usage:
 *   node ~/.pi/agent/skills/markdown-link/fetch-title.js <url>
 */

const { JSDOM } = require("jsdom");

function cleanTitle(s) {
  if (!s) return s;
  return s.replace(/\s+/g, " ").trim();
}

function escapeMarkdownTitle(s) {
  return s.replace(/\\/g, "\\\\").replace(/\[/g, "\\[").replace(/\]/g, "\\]");
}

function normalizeUrl(url) {
  const trimmed = url.trim();
  const withScheme = /^https?:\/\//i.test(trimmed)
    ? trimmed
    : `https://${trimmed}`;
  try {
    return new URL(withScheme).href;
  } catch {
    return null;
  }
}

async function main() {
  const args = process.argv.slice(2);
  const url = args.find((a) => !a.startsWith("--"));

  if (!url) {
    console.error("Usage: node fetch-title.js <url>");
    process.exit(1);
  }

  const pageUrl = normalizeUrl(url);
  if (!pageUrl) {
    console.error(`Invalid URL: ${url}`);
    process.exit(1);
  }

  console.error(`Fetching ${pageUrl} ...`);

  const resp = await fetch(pageUrl, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    },
    redirect: "follow",
  });

  if (!resp.ok) {
    throw new Error(`HTTP ${resp.status}: ${resp.statusText} for ${pageUrl}`);
  }

  const html = await resp.text();
  const dom = new JSDOM(html);
  const doc = dom.window.document;

  const ogTitle = doc
    .querySelector('meta[property="og:title"]')
    ?.getAttribute("content");
  const titleTag = doc.querySelector("title")?.textContent;
  const h1 = doc.querySelector("h1")?.textContent;

  const raw = ogTitle || titleTag || h1 || "";
  const title = cleanTitle(raw);

  if (!title) {
    console.error(`No title found at ${pageUrl}`);
    process.exit(1);
  }

  console.log(`[${escapeMarkdownTitle(title)}](${pageUrl})`);
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
