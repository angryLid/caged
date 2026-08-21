#!/usr/bin/env node
/**
 * skills-sync.mjs
 *
 * Declarative SKILLS sync for the caged seed — shared by every agent image
 * (pi, dsh, cmdc). Config: <project>/seed/skills.json.
 *
 * The caged containers run three agents that all speak the Agent Skills open
 * standard (a directory per skill, each with a SKILL.md carrying YAML
 * frontmatter). Each scans its own home dir, and every home dir is a live
 * bind mount of the host `seed` dir (scripts/start-container.sh):
 *
 *   pi    scans ~/.pi/agent/skills/            -> seed/.pi/agent/skills
 *   dsh   scans $DSH_HOME/skills (rank "user") -> seed/.dsh/skills
 *   cmdc  scans ~/.commandcode/skills/         -> seed/.commandcode/skills
 *
 * So skills must be installed INTO the seed — NOT into a user's project
 * working tree. The script installs each enabled skill into every directory
 * listed in the config's `linkTargets`, so one declaration set feeds all
 * agents.
 *
 * Skills come from two kinds of source, resolved serially in declaration
 * order (later sources override earlier ones on basename collision):
 *   * type "git"   — clonable repos (e.g. gitlab-ai-skills, mattpocock-skills).
 *     Cloned at **image build time** (network) into a vendor dir baked into
 *     the image; the container start only copies the enabled skills from that
 *     vendored set — no network, no git, at start.
 *   * type "local" — skills maintained directly in the repo, in a directory
 *     inside the seed (default `skills-src/`, resolved relative to the seed
 *     root — NOT inside any one agent's home, since the skills are shared).
 *     These are git-tracked sources of truth; the installed copies in the
 *     linkTargets are generated artifacts. Local sources are copied at
 *     container start like any other.
 *
 * Network vs. link is deliberately split:
 *   * Git skill repos are cloned at **image build time** (network) into a
 *     vendor dir baked into the image. The container start only copies the
 *     enabled skills from that vendored set into the seed's skills dirs — no
 *     network, no git, at start.
 *   * Running the script by hand (local dev) clones + installs in one step.
 *
 * Modes:
 *   default / no mode flag   clone/pull git sources, then install enabled skills
 *   --clone-only             only clone/pull git sources into the vendor dir (build)
 *   --link-only              only install enabled skills from an existing
 *                            vendor dir + local seed sources into the seed
 *                            skills dirs (container start) — no network / git
 *
 * Installation copies each enabled skill dir into each target dir and marks
 * it with a dotfile so stale managed copies can be detected and removed
 * without ever touching unmanaged skills.
 *
 * Idempotent and self-healing: on a fresh clone it re-creates everything.
 *
 * Usage:
 *   node scripts/skills-sync.mjs [--dry-run] [--config seed/skills.json]
 *                                [--seed <seed-root>] [--vendor <dir>]
 *                                [--target <name>] [--clone-only] [--link-only]
 *
 *   --config   path to skills.json. Default <project>/seed/skills.json.
 *   --seed     the seed root dir; every linkTargets.dir is resolved relative
 *              to it, and local sources default to <seed>/skills-src.
 *              Defaults to <project>/seed.
 *   --vendor   where the git skill source repos live. Defaults to
 *              <seed>/skills-sync/vendor/skills (used by local-dev mode). At
 *              container start the entrypoint passes the image-baked dir,
 *              e.g. /opt/caged/skills/vendor.
 *   --target   install only into the named linkTarget (container start — each
 *              agent's entrypoint syncs just its own skills dir). Without it
 *              (local dev) every target is synced.
 *
 * Exit codes:
 *   0  ok
 *   1  fatal (bad config / clone / install failure)
 *   2  warnings only (e.g. skill missing, collision) — links still applied
 */
import {
  readFileSync, mkdirSync, readdirSync, rmSync, writeFileSync,
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
  : join(PROJECT_ROOT, "seed", "skills.json");
const seedIdx = args.indexOf("--seed");
const SEED_DIR = seedIdx >= 0
  ? resolve(args[seedIdx + 1])
  : join(PROJECT_ROOT, "seed");
const vendorIdx = args.indexOf("--vendor");
const VENDOR_DIR = vendorIdx >= 0
  ? resolve(args[vendorIdx + 1])
  : join(SEED_DIR, "skills-sync", "vendor", "skills");
const targetIdx = args.indexOf("--target");
// Install only into the named linkTarget (used by container start — each
// agent's entrypoint syncs just its own skills dir). Without it (local dev)
// every target is synced.
const TARGET_NAME = targetIdx >= 0 ? args[targetIdx + 1] : null;

// Marker dropped into each installed skill dir so we can tell managed copies
// apart from hand-written / committed skills when cleaning up.
const MARKER = ".caged-skill-managed";

let exitCode = 0;
const warn = (msg) => { console.warn(`[warn] ${msg}`); exitCode = Math.max(exitCode, 2); };
const err = (msg) => { console.error(`[error] ${msg}`); exitCode = Math.max(exitCode, 1); };

function run(cmd, argsArr, opts = {}) {
  if (dryRun) { console.log(`[dry-run] $ ${cmd} ${argsArr.join(" ")}`); return; }
  // Inherit stderr (git clone/pull progress), but capture stdout: git prints
  // clone/pull summaries to stdout that would otherwise pollute every
  // container start log. `inherit` for stdout was fine when the sync ran
  // during an image build, but at runtime it is noise.
  execFileSync(cmd, argsArr, { stdio: ["inherit", "pipe", "inherit"], ...opts });
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

// --- 1. clone / pull git sources (build time / local dev only). ------------
// Local sources are not cloned — they live directly in the seed (SEED_DIR).
function syncRepos(cfg) {
  mkdirSync(VENDOR_DIR, { recursive: true });
  for (const src of cfg.sources) {
    if (src.type === "local") continue;
    const dest = join(VENDOR_DIR, src.name);
    if (existsSync(join(dest, ".git"))) {
      console.log(`[pull] ${src.name}`);
      run("git", ["-C", dest, "pull", "--ff-only", "--quiet"]);
    } else {
      console.log(`[clone] ${src.name} <- ${src.url}`);
      run("git", ["clone", "--quiet", src.url, dest]);
    }
  }
}

// --- 2. resolve enabled skills into absolute source dirs -------------------
// Sources are processed serially in declaration order; later sources override
// earlier ones on basename collision (last wins).
function resolveSkills(cfg) {
  const manifest = [];
  const seenBasename = new Map();
  for (const source of cfg.sources) {
    // git sources live in the (build-time cloned) vendor dir; local sources
    // live in the shared seed, resolved relative to SEED_DIR (the seed root,
    // not any one agent's home).
    const sourceRoot = source.type === "local"
      ? join(SEED_DIR, source.dir ?? "skills-src")
      : join(VENDOR_DIR, source.name, source.skillsDir);
    for (const rel of source.enabled) {
      const src = join(sourceRoot, rel);
      const skillFile = join(src, "SKILL.md");
      if (!existsSync(skillFile)) {
        warn(`skill not found: ${source.name}/${rel} (expected ${skillFile})`);
        continue;
      }
      const base = basename(src);
      if (seenBasename.has(base)) {
        console.log(`[override] ${source.name}/${rel} overrides ${seenBasename.get(base)} (same basename "${base}")`);
      } else {
        seenBasename.set(base, `${source.name}/${rel}`);
      }
      manifest.push({ base, src, source: source.name, rel });
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
  // Target dirs are relative to the seed ROOT, not to any one agent's home.
  // --target <name> installs into that one linkTarget only (container start);
  // by default every target is synced (local dev).
  let targets = cfg.linkTargets?.length ? cfg.linkTargets : [{ name: "default", dir: "skills" }];
  if (TARGET_NAME) {
    targets = targets.filter((t) => t.name === TARGET_NAME);
    if (!targets.length) throw new Error(`unknown linkTarget name '${TARGET_NAME}' (known: ${cfg.linkTargets?.map((t) => t.name).join(", ") || "none"})`);
  }
  for (const t of targets) {
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
        rmSync(p, { recursive: true, force: true });
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
      installSkill(m.src, dest, st);
    }
  }
}

// --- main ------------------------------------------------------------------
try {
  const cfg = loadConfig();
  if (!linkOnly) syncRepos(cfg);
  if (!cloneOnly) {
    const manifest = resolveSkills(cfg);
    linkTargets(cfg, manifest);
    // One line naming every synced skill; the target(s) are obvious from the
    // caller (entrypoint passes --target, local dev syncs all).
    console.log(`[skills] ${manifest.map((m) => m.base).join(" ")}`);
  }
  console.log(dryRun ? "[dry-run] done" : "[done]");
} catch (e) {
  err(e.message);
  if (e.stack) console.error(e.stack);
}

process.exit(exitCode);