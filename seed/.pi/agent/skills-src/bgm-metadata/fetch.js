#!/usr/bin/env node

/**
 * Fetch anime metadata from bgm.tv (Bangumi) by scraping the SSR HTML page.
 * Uses jsdom so extraction logic mirrors the bookmark.user.js config.ts exactly.
 *
 * Usage:
 *   node ~/.pi/agent/skills/bgm-metadata/fetch.js <bgm-url>
 *   node ~/.pi/agent/skills/bgm-metadata/fetch.js <bgm-url> --json   (raw JSON)
 */

const { JSDOM } = require("jsdom");

// --- URL parsing ---
function parseSubjectId(url) {
  const patterns = [
    /bgm\.tv\/subject\/(\d+)/,
    /bangumi\.tv\/subject\/(\d+)/,
    /chii\.in\/subject\/(\d+)/,
  ];
  if (/^\d+$/.test(url.trim())) return url.trim();
  for (const p of patterns) {
    const m = url.match(p);
    if (m) return m[1];
  }
  return null;
}

function cleanUrl(url) {
  try {
    const u = new URL(url);
    return u.origin + u.pathname;
  } catch {
    return url;
  }
}

// --- Extraction helpers (mirrors config.ts DOM queries) ---

/** Extract title from #headerSubject h1 a (mirrors config.ts) */
function extractTitle(doc) {
  const a = doc.querySelector("#headerSubject h1 a");
  return a ? a.textContent.trim() : null;
}

/**
 * Extract Chinese name by iterating ul#infobox <li> elements.
 * Mirrors config.ts: /^中文名[:：]\s*(.+)$/m applied to infobox.textContent.
 * Using per-<li> iteration instead of whole-textContent regex for robustness in jsdom.
 */
function extractCnName(doc) {
  const lis = doc.querySelectorAll("ul#infobox li");
  for (const li of lis) {
    const text = li.textContent.trim();
    const m = text.match(/^中文名[：:]\s*(.+)$/);
    if (m) return m[1].trim();
  }
  return null;
}

/**
 * Extract air date from ul#infobox <li> elements.
 * Mirrors config.ts: /开始[:：]\s(\d{4}年\d{1,2}月\d{1,2}日)$/m
 * Reformatted to yyyy-MM-dd with zero-padded month/day.
 * "放送开始" matches the pattern "开始" as a substring (same as config.ts).
 */
function extractAirDate(doc) {
  const lis = doc.querySelectorAll("ul#infobox li");
  for (const li of lis) {
    const text = li.textContent.trim();
    const m = text.match(/开始[：:]\s*(\d{4})年(\d{1,2})月(\d{1,2})日/);
    if (m) {
      return `${m[1]}-${m[2].padStart(2, "0")}-${m[3].padStart(2, "0")}`;
    }
  }
  return null;
}

/**
 * Extract tags from .subject_tag_section .l.meta span (mirrors config.ts exactly)
 */
function extractTags(doc) {
  const spans = doc.querySelectorAll(".subject_tag_section .l.meta span");
  return Array.from(spans)
    .map((s) => s.textContent.trim())
    .filter(Boolean);
}

/**
 * Extract animation studio: find ul#infobox li where .tip starts with "动画制作",
 * then collect all a.l names. (mirrors config.ts)
 */
function extractStudios(doc) {
  const lis = doc.querySelectorAll("ul#infobox li");
  for (const li of lis) {
    const tip = li.querySelector(".tip");
    if (tip && tip.textContent.trim().startsWith("动画制作")) {
      const anchors = li.querySelectorAll("a.l");
      return Array.from(anchors)
        .map((a) => a.textContent.trim())
        .filter(Boolean);
    }
  }
  return [];
}

/** Extract rating from .global_rating .number */
function extractRating(doc) {
  const el = doc.querySelector(".global_rating .number");
  if (el) {
    const v = parseFloat(el.textContent.trim());
    return isNaN(v) ? null : v;
  }
  return null;
}

// --- Main ---
async function main() {
  const args = process.argv.slice(2);
  const rawJson = args.includes("--json");
  const url = args.find((a) => !a.startsWith("--"));

  if (!url) {
    console.error("Usage: node fetch.js <bgm.tv/subject/ID> [--json]");
    process.exit(1);
  }

  const subjectId = parseSubjectId(url);
  if (!subjectId) {
    console.error(`Could not parse subject ID from: ${url}`);
    console.error(
      "Expected a URL like: https://bgm.tv/subject/12345 or a numeric ID",
    );
    process.exit(1);
  }

  const pageUrl = `https://bgm.tv/subject/${subjectId}`;
  console.error(`Fetching ${pageUrl} ...`);

  const resp = await fetch(pageUrl, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    },
  });

  if (!resp.ok) {
    throw new Error(`HTTP ${resp.status}: ${resp.statusText} for ${pageUrl}`);
  }

  const html = await resp.text();
  const dom = new JSDOM(html);
  const doc = dom.window.document;

  // --- Extract fields (same logic as config.ts) ---
  const title = extractTitle(doc);
  const cnName = extractCnName(doc);
  const name = cnName || title;
  const originalName = cnName ? title : null;
  const airDate = extractAirDate(doc);
  const tags = extractTags(doc);
  const studios = extractStudios(doc);
  const rating = extractRating(doc);

  const meta = {
    Name: name || "",
    原名: originalName || "",
    分类: tags.join(", "),
    开播时间: airDate || "",
    制作公司: studios.join(", "),
    URL: cleanUrl(pageUrl),
    rating: rating,
  };

  if (rawJson) {
    const raw = {
      ...meta,
      _raw: { title, cnName, tags, studios, airDate, rating },
    };
    console.log(JSON.stringify(raw, null, 2));
    process.exit(0);
  }

  // --- Pretty-print ---
  console.log("═══════════════════════════════════════════");
  console.log(`  Bangumi Metadata  —  bgm.tv/subject/${subjectId}`);
  console.log("═══════════════════════════════════════════");
  console.log();
  console.log(`  Name      : ${meta.Name}`);
  if (meta.原名) console.log(`  原名       : ${meta.原名}`);
  console.log(`  Category  : ${meta.分类}`);
  console.log(`  Air Date  : ${meta.开播时间 || "N/A"}`);
  console.log(`  Studio    : ${meta.制作公司 || "N/A"}`);
  if (rating !== null) console.log(`  Rating    : ${rating} / 10`);
  console.log(`  URL       : ${meta.URL}`);
  console.log();
  console.log("--- CSV snippet ---");
  console.log(
    [
      `"${meta.Name}"`,
      "", // rating/观感 — user fills in
      meta.原名 ? `"${meta.原名}"` : "",
      `"${meta.分类}"`,
      `"${meta.开播时间}"`,
      `"${meta.制作公司}"`,
      '""', // comment — user fills in
    ].join(","),
  );
  console.log();
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
