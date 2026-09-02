---
name: skills-sync
description: Sync the project's declaratively-configured skills (seed/skills.json) — clone/pull the git source skill repos, install the enabled skills (git + local) for every agent (pi, dsh, cmdc). Use when the user says "sync skills", "update skills", "pull skills", "install skills", "refresh skills", after editing skills.json, or when newly added skills aren't showing up.
---

# skills-sync

Synchronises the skills declared in `seed/skills.json` into the locations each
agent scans for skills. The caged containers run three agents that all speak
the Agent Skills standard (a directory per skill, each with a `SKILL.md`
carrying YAML frontmatter), and every agent home is a **live bind mount** of
the host `seed` dir (set up by `scripts/start-container.sh`):

* pi scans `~/.pi/agent/skills/` → `seed/.pi/agent/skills/`
* dsh scans `$DSH_HOME/skills` → `seed/.dsh/skills/`
* cmdc scans `~/.commandcode/skills/` → `seed/.commandcode/skills/`

So skills are installed **into the seed**, one directory per agent — not into
a user's project working tree.

Skills come from two kinds of source, resolved serially in declaration order
(later sources override earlier ones on basename collision):

* **`type: "git"`** — clonable repos (e.g. gitlab-ai-skills,
  mattpocock-skills).
* **`type: "local"`** — skills maintained directly in this repo, in
  `seed/skills-src/` (git-tracked — the source of truth, shared by all
  agents).

## Where skills live

Inside each agent's seed skills dir, each enabled skill is a **real directory
copy** (not a symlink) carrying a hidden `.caged-skill-managed` marker file.
The marker lets the tool tell its own copies apart from unmanaged skills, so
it can remove stale ones without ever touching skills it doesn't own.

### Sources

* **Git sources** are cloned **on the host at build time**
  (`scripts/build-caged-base.sh`, which any `cg <agent> build` runs) into
  `seed/skills-sync/vendor/skills/`. They are **not** baked into any image —
  the seed is bind-mounted into every container, so the vendor is reachable at
  `/agent-home/skills-sync/vendor/skills/` inside one. At **container start**
  each agent's entrypoint only copies the enabled skills from that vendor into
  the seed — no network, no git at start.
* **Local sources** live directly in the seed at `seed/skills-src/`
  (git-tracked — the source of truth). They do **not** go through the
  image/vendor; at container start the entrypoint copies enabled local skills
  straight from `skills-src/` into each agent's `skills/` dir, alongside the
  git ones.

Both types install identically into every `linkTargets` dir as marked copies;
git and local share the same `enabled`/conflict semantics.

## How to run

```bash
node scripts/skills-sync.mjs              # local dev: clone/pull git sources + install into all seed skills dirs
node scripts/skills-sync.mjs --dry-run    # preview without changing anything
node scripts/skills-sync.mjs --link-only  # install only, from an existing vendor + local sources (no git/network)
node scripts/skills-sync.mjs --link-only --target pi    # one agent's dir only (what container start does)
node scripts/skills-sync.mjs --clone-only # clone/pull git sources only (what the build script runs)
node scripts/skills-sync.mjs --seed /agent-home   # explicit seed dir (default: <project>/seed)
```

At container start each agent's entrypoint passes `--target <agent>`, so it
only refreshes its own skills dir (pi starts do not touch dsh's or cmdc's
skills, and vice versa). Run without `--target` to sync every agent at once.

Exit codes: `0` ok, `1` fatal, `2` warnings only (missing skill / collision) — installs still applied.

## When the user edits `skills.json`

- Adding a skill to an existing git source's `enabled` → re-run the script.
- Adding a skill to the **local** source's `enabled` → just re-run the script;
  local skills live in the seed and need no clone at all.
- Adding a whole new **git repo** source → it must be cloned, so run the script
  (default mode, or `--clone-only`) before the next container start. **No image
  rebuild is needed** — the repos live in the seed, not in the image.
- Adding a **local directory** source → point `dir` at a git-tracked folder in
  the seed and re-run.
- Removing a skill → the script removes its managed copies on the next run.

## Notes / gotchas

- **The generated skill copies in each agent's `skills/` dir are gitignored**
  and regenerated; don't commit them, don't edit them by hand. The **source of
  truth for your own skills is `seed/skills-src/`** — edit there, then re-run
  the sync to install.
- **Collisions resolve serially, last wins**: later sources override earlier
  ones on basename collision. By default the local source is declared last, so
  your own skill with the same name as an upstream one wins.
- **New git repo sources need a clone, not a rebuild.** Only skills whose repos
  are already in `seed/skills-sync/vendor/` can be enabled at container start
  (the start is offline by design), so run the sync once after adding a source.
  Local sources never need even that.
- Git repos are plain clones (not submodules) and gitignored — `seed/skills.json`
  is the source of truth, and a missing vendor self-heals on the next
  `--clone-only` run.
