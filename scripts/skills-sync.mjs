#!/usr/bin/env node
/**
 * skills-sync.mjs
 *
 * Declarative SKILLS sync for ./seed/.pi/agent/skills.json
 *
 * The caged container runs @earendil-works/pi-coding-agent. pi scans
 * ~/.pi/agent/skills/ for skills, and ~/.pi is a live bind mount of the host
 * `seed/.pi` dir (compose.yaml). So skills must be installed INTO the seed —
 * `seed/.pi/agent/skills/` — NOT into a user's project working tree.
 *
 * Network vs. link is deliberately split:
 *   * The skill repos are cloned at **image build time** (network) into a
 *     vendor dir baked into the image. The container start only copies the
 *     enabled skills from that vendored set into the seed's skills dir — no
 *     network, no git, at start.
 *   * Running the script by hand (local dev) clones + installs in one step.
 *
 * Modes:
 *   default / no mode flag   clone/pull repos, then install enabled skills
 *   --clone-only             only clone/pull repos into the vendor dir (build)
 *   --link-only              only install enabled skills from an existing
 *                            vendor dir into the seed skills dir (container
 *                            start) — no network / git
 *
 * Installation copies each enabled skill dir into the seed skills dir and
 * marks it with a dotfile so stale managed copies can be detected and removed
 * without ever touching hand-written / committed skills.
 *
 * Idempotent and self-healing: on a fresh clone it re-creates everything.
 *
 * Usage:
 *   node scripts/skills-sync.mjs [--dry-run] [--config seed/.pi/agent/skills.json]
 *                                [--seed <pi-agent-dir>] [--vendor <dir>]
 *                                [--clone-only] [--link-only]
 *
 *   --config   path to skills.json. Default <project>/seed/.pi/agent/skills.json.
 *   --seed     the pi agent config dir that owns the skills; the install
 *              destination. Defaults to <project>/seed/.pi/agent.
 *   --vendor   where the skill source repos live. Defaults to
 *              <seed>/skills-sync/vendor/skills (used by local-dev mode). At
 *              container start the entrypoint passes the image-baked dir,
 *              e.g. /opt/caged/skills/vendor.
 *
 * Exit codes:
 *   0  ok
 *   1  fatal (bad config / clone / install failure)
 *   2  warnings only (e.g. skill missing, collision) — links still applied
 */
import {
  readFileSync, mkdirSync, readdirSync, rmSync, cpSync, writeFileSync,
  lstatSync, existsSync, readlinkSync,
} from "node:fs";
import { dirname, resolve, join, basename, sep } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const cloneOnly = args.includes("--clone-only");
const linkOnly = args.includes("--link-only");
const configIdx = args.indexOf("--config");
const configPath = configIdx >= 0
  ? resolve(PROJECT_ROOT, args[configIdx + 1])
  : join(PROJECT_ROOT, "seed", ".pi", "agent", "skills.json");
const seedIdx = args.indexOf("--seed");
const SEED_DIR = seedIdx >= 0
  ? resolve(args[seedIdx + 1])
  : join(PROJECT_ROOT, "seed", ".pi", "agent");
const vendorIdx = args.indexOf("--vendor");
const VENDOR_DIR = vendorIdx >= 0
  ? resolve(args[vendorIdx + 1])
  : join(SEED_DIR, "skills-sync", "vendor", "skills");

// Marker dropped into each installed skill dir so we can tell managed copies
// apart from hand-written / committed skills when cleaning up.
const MARKER = ".caged-skill-managed";

let exitCode = 0;
const warn = (msg) => { console.warn(`[warn] ${msg}`); exitCode = Math.max(exitCode, 2); };
const err = (msg) => { console.error(`[error] ${msg}`); exitCode = Math.max(exitCode, 1); };

function run(cmd, argsArr, opts = {}) {
  if (dryRun) { console.log(`[dry-run] $ ${cmd} ${argsArr.join(" ")}`); return; }
  execFileSync(cmd, argsArr, { stdio: "inherit", ...opts });
}

// Install a skill by copying its source dir into the target location.
//
// Uses the shell `cp -r` (not node's fs.cpSync) because node's cpSync relies
// on copy_file_range(2), which fails with EACCES on the virtiofs bind mount
// that the live seed sits on (observed on podman/macOS). The external `cp`
// walks the tree with plain reads/writes and works fine.
function installSkill(src, dest, st) {
  // Unlink a pre-existing symlink (legacy managed link / broken link) so the
  // recursive `cp -r` never follows it into the vendor dir; real managed dirs
  // are removed recursively.
  if (st && st.isSymbolicLink()) rmSync(dest);
  else rmSync(dest, { recursive: true, force: true });
  run("cp", ["-r", "--", src + "/", dest]);
  writeFileSync(join(dest, MARKER), "managed by caged skills-sync\n");
}

function loadConfig() {
  if (!existsSync(configPath)) throw new Error(`config not found: ${configPath}`);
  return JSON.parse(readFileSync(configPath, "utf8"));
}

// --- 1. clone / pull repos (build time / local dev only) -------------------
function syncRepos(cfg) {
  mkdirSync(VENDOR_DIR, { recursive: true });
  for (const repo of cfg.repos) {
    const dest = join(VENDOR_DIR, repo.name);
    if (existsSync(join(dest, ".git"))) {
      console.log(`[pull] ${repo.name}`);
      run("git", ["-C", dest, "pull", "--ff-only", "--quiet"]);
    } else {
      console.log(`[clone] ${repo.name} <- ${repo.url}`);
      run("git", ["clone", "--quiet", repo.url, dest]);
    }
  }
}

// --- 2. resolve enabled skills into absolute source dirs -------------------
function resolveSkills(cfg) {
  const manifest = [];
  const seenBasename = new Map();
  for (const repo of cfg.repos) {
    const repoSrc = join(VENDOR_DIR, repo.name, repo.skillsDir);
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

// Is a path a managed entry? Either a marker-backed copy (current design) or a
// legacy symlink pointing back into a skills-sync/vendor dir (old design).
function isManagedAt(p, st) {
  if (st.isDirectory()) return existsSync(join(p, MARKER));
  if (st.isSymbolicLink()) {
    try { return readlinkSync(p).includes(sep + "skills-sync" + sep + "vendor"); } catch { return false; }
  }
  return false;
}

// --- 3. install enabled skills into each target dir ------------------------
function linkTargets(cfg, manifest) {
  for (const t of cfg.linkTargets) {
    // linkTargets.dir is relative to SEED_DIR (e.g. "skills" -> <seed>/skills)
    const linkDir = join(SEED_DIR, t.dir);
    mkdirSync(linkDir, { recursive: true });

    const wanted = new Set(manifest.map((m) => m.base));

    // Remove entries that are NOT in the manifest but ARE managed (stale copy,
    // or a legacy vendor symlink after a skill was removed from config). Hand-
    // written / committed skills (no marker, not a vendor symlink) are left
    // alone — but if a wanted skill collides with such a hand-written one, we
    // warn below rather than clobber it.
    for (const entry of readdirSync(linkDir)) {
      if (wanted.has(entry)) continue;
      const p = join(linkDir, entry);
      let st;
      try { st = lstatSync(p); } catch { continue; }
      if (isManagedAt(p, st)) {
        console.log(`[remove] ${t.name}: ${entry} (removed from config)`);
        if (!dryRun) rmSync(p, { recursive: true, force: true });
      }
    }

    for (const m of manifest) {
      const dest = join(linkDir, m.base);
      // A present but non-managed entry is a hand-written skill — never clobber
      // it; warn instead.
      let st;
      let isManaged = false;
      try { st = lstatSync(dest); isManaged = isManagedAt(dest, st); } catch { /* absent */ }
      if (st && !isManaged) {
        warn(`refusing to overwrite non-managed ${dest} — remove or rename it, or pick a different skill name`);
        continue;
      }
      console.log(`[install] ${t.name}: ${m.base} <- ${m.src}`);
      if (!dryRun) {
        installSkill(m.src, dest, st);
      }
    }

    console.log(`[ok] installed ${manifest.length} skills into ${t.dir} (${linkDir})`);
  }
}

// --- main ------------------------------------------------------------------
try {
  const cfg = loadConfig();
  console.log(`[seed] ${SEED_DIR}`);
  console.log(`[vendor] ${VENDOR_DIR}`);
  if (!linkOnly) syncRepos(cfg);
  if (!cloneOnly) {
    const manifest = resolveSkills(cfg);
    linkTargets(cfg, manifest);
  }
  console.log(dryRun ? "[dry-run] done" : "[done] skills synced");
} catch (e) {
  err(e.message);
  if (e.stack) console.error(e.stack);
}

process.exit(exitCode);