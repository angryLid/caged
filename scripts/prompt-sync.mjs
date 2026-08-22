#!/usr/bin/env node
/**
 * prompt-sync.mjs
 *
 * Declarative GLOBAL PROMPT sync for the caged seed — the companion to
 * skills-sync.mjs. Whereas skills install many SKILL dirs, this installs ONE
 * always-loaded environment primer into each agent's home so every agent
 * carries the exact same caged rules.
 *
 * Config: <project>/seed/prompts.json. The prompt is a single source of truth,
 * shared verbatim by every agent — no per-agent variants, because the global
 * prompt must be identical everywhere.
 *
 *   seed/prompt-src/global.md   authoritative global prompt (git-tracked)
 *
 * Each linkTarget is a single file in one agent's home:
 *
 *   pi    reads ~/.pi/agent/AGENTS.md        -> seed/.pi/agent/AGENTS.md
 *   cmdc  reads ~/.commandcode/AGENTS.md     -> seed/.commandcode/AGENTS.md
 *
 * Every agent home is a live bind mount of the host `seed` dir
 * (scripts/start-container.sh), so a prompt must be installed INTO the seed —
 * not into a user's project working tree.
 *
 * The installed file is paired with a dotfile marker (default
 * .caged-prompt-managed) so stale managed copies can be detected and removed
 * without ever clobbering a hand-written prompt.
 *
 * Modes:
 *   default            sync every target (local dev)
 *   --target <name>    sync only the named linkTarget (container start — each
 *                      agent's entrypoint syncs just its own prompt)
 *
 * Idempotent and self-healing: on a fresh clone it re-creates everything.
 *
 * Usage:
 *   node scripts/prompt-sync.mjs [--dry-run] [--config seed/prompts.json]
 *                                [--seed <seed-root>] [--target <name>]
 *
 *   --config   path to prompts.json. Default <project>/seed/prompts.json.
 *   --seed     the seed root dir; linkTargets.file are resolved relative to it,
 *              and the source dir defaults to <seed>/prompt-src.
 *              Defaults to <project>/seed.
 *   --target   install only into the named linkTarget. Without it every target
 *              is synced.
 *
 * Exit codes:
 *   0  ok
 *   1  fatal (bad config / install failure)
 *   2  warnings only (e.g. missing source) — links still applied
 */
import { readFileSync, mkdirSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const configIdx = args.indexOf("--config");
const configPath = configIdx >= 0
  ? resolve(PROJECT_ROOT, args[configIdx + 1])
  : join(PROJECT_ROOT, "seed", "prompts.json");
const seedIdx = args.indexOf("--seed");
const SEED_DIR = seedIdx >= 0 ? resolve(args[seedIdx + 1]) : join(PROJECT_ROOT, "seed");
const targetIdx = args.indexOf("--target");
const TARGET_NAME = targetIdx >= 0 ? args[targetIdx + 1] : null;

const MARKER = ".caged-prompt-managed";

let exitCode = 0;
const warn = (msg) => { console.warn(`[warn] ${msg}`); exitCode = Math.max(exitCode, 2); };
const err = (msg) => { console.error(`[error] ${msg}`); exitCode = Math.max(exitCode, 1); };

function loadConfig() {
  if (!existsSync(configPath)) throw new Error(`config not found: ${configPath}`);
  return JSON.parse(readFileSync(configPath, "utf8"));
}

// Read the global prompt source. It is identical for every target — the
// per-agent content differs only in WHERE it is installed, never in WHAT.
function loadGlobal(cfg) {
  const src = cfg.source;
  const globalFile = join(SEED_DIR, src.dir, src.global);
  if (!existsSync(globalFile)) throw new Error(`global prompt not found: ${globalFile}`);
  return readFileSync(globalFile, "utf8");
}

function readMarked(p) {
  if (!existsSync(p)) return null;
  try { return readFileSync(p, "utf8"); } catch { return null; }
}

// Was this target produced by a previous prompt-sync run?
function isManaged(targetFile, markerFile) {
  return existsSync(targetFile) && readMarked(markerFile) !== null;
}

function installPrompt(targetFile, markerFile, content) {
  mkdirSync(dirname(targetFile), { recursive: true });
  writeFileSync(targetFile, content);
  writeFileSync(markerFile, "managed by caged prompt-sync\n");
}

function linkTargets(cfg) {
  let targets = cfg.linkTargets?.length ? cfg.linkTargets : [];
  if (TARGET_NAME) {
    targets = targets.filter((t) => t.name === TARGET_NAME);
    if (!targets.length) throw new Error(`unknown linkTarget name '${TARGET_NAME}' (known: ${cfg.linkTargets?.map((t) => t.name).join(", ") || "none"})`);
  }

  for (const t of targets) {
    const targetFile = join(SEED_DIR, t.file);
    const markerFile = join(dirname(targetFile), "." + MARKER.replace(/^\./, "") + "." + t.name);

    const content = loadGlobal(cfg);

    if (existsSync(targetFile) && !isManaged(targetFile, markerFile)) {
      // A present but non-managed file is a hand-written prompt — never clobber
      // it; warn so the operator can migrate it into prompt-src explicitly.
      warn(`refusing to overwrite non-managed ${targetFile} — move hand-written content into ${join(SEED_DIR, cfg.source.dir, cfg.source.global)} first, then remove it`);
      continue;
    }

    if (dryRun) {
      console.log(`[dry-run] ${t.name}: would write ${targetFile} (${content.length} bytes)`);
      continue;
    }
    installPrompt(targetFile, markerFile, content);
    console.log(`[prompt] ${t.name} -> ${targetFile}`);
  }
}

try {
  const cfg = loadConfig();
  linkTargets(cfg);
  console.log(dryRun ? "[dry-run] done" : "[done]");
} catch (e) {
  err(e.message);
  if (e.stack) console.error(e.stack);
}

process.exit(exitCode);