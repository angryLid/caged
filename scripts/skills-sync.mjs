#!/usr/bin/env node
/**
 * skills-sync.mjs
 *
 * Declarative SKILLS sync for ./skills.json
 *
 * What it does:
 *   1. For each repo in skills.json, clone it into vendor/skills/<name> if missing,
 *      otherwise `git pull` it (fast-forward to latest).
 *   2. For each enabled skill, create a RELATIVE symlink inside each link
 *      target dir (default .pi/skills) pointing back into vendor/skills/<name>.
 *   3. Remove stale symlinks that this tool previously created (i.e. links
 *      whose target resolves into vendor/skills/), so removed skills stop loading.
 *
 * Idempotent and self-healing: on a fresh clone it re-creates everything.
 * Relative symlinks mean nothing is hardcoded to an absolute path.
 *
 * Usage:
 *   node scripts/skills-sync.mjs [--dry-run] [--config skills.json]
 *
 * Exit codes:
 *   0  ok
 *   1  fatal (bad config / clone / link failure)
 *   2  warnings only (e.g. skill missing, collision) — links still applied
 */
import { readFileSync, mkdirSync, readdirSync, rmSync, symlinkSync, lstatSync, existsSync, realpathSync, readlinkSync } from "node:fs";
import { dirname, resolve, join, relative, basename, sep } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const configIdx = args.indexOf("--config");
const configPath = configIdx >= 0 ? resolve(PROJECT_ROOT, args[configIdx + 1]) : join(PROJECT_ROOT, "skills.json");

let exitCode = 0;
const warn = (msg) => { console.warn(`[warn] ${msg}`); exitCode = Math.max(exitCode, 2); };
const err = (msg) => { console.error(`[error] ${msg}`); exitCode = Math.max(exitCode, 1); };

function run(cmd, argsArr, opts = {}) {
  if (dryRun) { console.log(`[dry-run] $ ${cmd} ${argsArr.join(" ")}`); return; }
  execFileSync(cmd, argsArr, { stdio: "inherit", ...opts });
}

function loadConfig() {
  if (!existsSync(configPath)) throw new Error(`config not found: ${configPath}`);
  return JSON.parse(readFileSync(configPath, "utf8"));
}

// --- 1. clone / pull repos ------------------------------------------------
function syncRepos(cfg) {
  const root = join(PROJECT_ROOT, "vendor", "skills");
  mkdirSync(root, { recursive: true });
  for (const repo of cfg.repos) {
    const dest = join(root, repo.name);
    if (existsSync(join(dest, ".git"))) {
      console.log(`[pull] ${repo.name}`);
      run("git", ["-C", dest, "pull", "--ff-only", "--quiet"]);
    } else {
      console.log(`[clone] ${repo.name} <- ${repo.url}`);
      run("git", ["clone", "--quiet", repo.url, dest]);
    }
  }
}

// --- 2. resolve enabled skills into absolute source dirs ------------------
function resolveSkills(cfg) {
  const manifest = [];
  const seenBasename = new Map();
  for (const repo of cfg.repos) {
    const repoSrc = join(PROJECT_ROOT, "vendor", "skills", repo.name, repo.skillsDir);
    for (const rel of repo.enabled) {
      const src = join(repoSrc, rel);
      const skillFile = join(src, "SKILL.md");
      if (!existsSync(skillFile)) {
        warn(`skill not found: ${repo.name}/${rel} (expected ${skillFile})`);
        continue;
      }
      const base = basename(src);
      if (seenBasename.has(base)) {
        warn(`basename collision "${base}": enabled in both ${seenBasename.get(base)} and ${repo.name}/${rel} — pi will load only one`);
      } else {
        seenBasename.set(base, `${repo.name}/${rel}`);
      }
      manifest.push({ base, src, repo: repo.name, rel });
    }
  }
  return manifest;
}

// --- 3. (re)link into each target dir -------------------------------------
function linkTargets(cfg, manifest) {
  for (const t of cfg.linkTargets) {
    const linkDir = join(PROJECT_ROOT, t.dir);
    mkdirSync(linkDir, { recursive: true });

    // Managed links are those pointing into vendor/skills/. Remove any that
    // are NOT in the current manifest (skill removed from config) — whether
    // healthy or broken. readlink works on broken links; realpathSync would not.
    const wanted = new Set(manifest.map((m) => m.base));
    const managedTarget = (rawTarget) => rawTarget.includes("vendor" + sep + "skills");
    for (const entry of readdirSync(linkDir)) {
      const p = join(linkDir, entry);
      let st;
      try { st = lstatSync(p); } catch { continue; }
      if (!st.isSymbolicLink()) continue;
      let rawTarget;
      try { rawTarget = readlinkSync(p); } catch { continue; }
      if (managedTarget(rawTarget) && !wanted.has(entry) && !dryRun) {
        console.log(`[unlink] ${t.name}: ${entry} (removed from config)`);
        rmSync(p);
      }
    }

    for (const m of manifest) {
      const linkPath = join(linkDir, m.base);
      // relative from linkDir to source, so it's portable across mounts/hosts
      const rel = relative(linkDir, m.src);
      const expected = realpathSync(m.src);
      // If the entry exists and is a symlink that already resolves to the
      // expected source, keep it. Otherwise (broken / wrong target / real dir)
      // replace it so the link stays correct.
      const existing = (() => {
        try {
          const st = lstatSync(linkPath);
          if (!st.isSymbolicLink()) return "realdir";
          const t = realpathSync(linkPath);
          return t === expected ? "ok" : "stale";
        } catch { return "stale"; }
      })();
      if (existing === "ok") {
        console.log(`[exists] ${t.name}: ${m.base} (skip)`);
        continue;
      }
      if (existing === "realdir") {
        warn(`refusing to replace real directory ${linkPath} — remove it manually`);
        continue;
      }
      if (existsSync(linkPath) || lstatExists(linkPath)) {
        console.log(`[relink] ${t.name}: ${m.base} (stale target)`);
        if (!dryRun) rmSync(linkPath);
      }
      console.log(`[link]  ${t.name}: ${m.base} -> ${rel}`);
      if (!dryRun) symlinkSync(rel, linkPath, "dir");
    }

    console.log(`[ok] linked ${manifest.length} skills into ${t.dir}`);
  }
}

function lstatExists(p) { try { lstatSync(p); return true; } catch { return false; } }

// --- main ------------------------------------------------------------------
try {
  const cfg = loadConfig();
  syncRepos(cfg);
  const manifest = resolveSkills(cfg);
  linkTargets(cfg, manifest);
  console.log(dryRun ? "[dry-run] done" : "[done] skills synced");
} catch (e) {
  err(e.message);
  if (e.stack) console.error(e.stack);
}

process.exit(exitCode);