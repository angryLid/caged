---
name: skills-sync
description: Sync the project's declaratively-configured skills (seed/.pi/agent/skills.json) — clone/pull the git source skill repos, install the enabled skills (git + local) for pi. Use when the user says "sync skills", "update skills", "pull skills", "install skills", "refresh skills", after editing skills.json, or when newly added skills aren't showing up.
---

# skills-sync

Synchronises the skills declared in `seed/.pi/agent/skills.json` into the
location pi scans for skills. Skills come from two kinds of source, resolved
serially in declaration order:

* **`type: "git"`** — clonable repos (e.g. gitlab-ai-skills, mattpocock-skills).
* **`type: "local"`** — skills maintained directly in this repo, in a directory
  inside the seed (default `skills-src/`).

## Where skills live

This project is a container image ("caged") that runs pi. pi scans
`~/.pi/agent/skills/`, and `~/.pi` is a **live bind mount** of the host
`seed/.pi` dir (set up by `scripts/start-container.sh`). So skills are
installed **into the seed** — `seed/.pi/agent/skills/` — not into a user's
project working tree.

Inside the seed, each enabled skill is a **real directory copy** (not a
symlink) carrying a hidden `.caged-skill-managed` marker file. The marker lets
the tool tell its own copies apart from unmanaged skills, so it can remove
stale ones without ever touching skills it doesn't own.

### Sources

* **Git sources** are cloned at **image build time** (see `Containerfile`)
  into `/opt/caged/skills/vendor`, baked into the image. At **container
  start** the entrypoint only copies the enabled skills from that baked set
  into the seed — no network, no git at start.
* **Local sources** live directly in the seed at
  `seed/.pi/agent/skills-src/` (git-tracked — the source of truth). They do
  **not** go through the image/vendor; at container start the entrypoint
  copies enabled local skills straight from `skills-src/` into `skills/`,
  alongside the git ones.

Both types install identically into `skills/` as marked copies; git and local
share the same `enabled`/conflict semantics.

## How to run

```bash
node scripts/skills-sync.mjs              # local dev: clone/pull git sources + install into seed/.pi/agent/skills
node scripts/skills-sync.mjs --dry-run    # preview without changing anything
node scripts/skills-sync.mjs --link-only  # install only, from an existing vendor + local sources (no git/network) — what container start does
node scripts/skills-sync.mjs --clone-only # clone/pull git sources only (image build step)
node scripts/skills-sync.mjs --seed /agent-home/.pi/agent   # explicit seed dir
```

Exit codes: `0` ok, `1` fatal, `2` warnings only (missing skill / collision) — installs still applied.

## When the user edits `skills.json`

- Adding a skill to an existing git source's `enabled` → re-run the script (or
  rebuild + restart if the repo isn't already in the image vendor).
- Adding a skill to the **local** source's `enabled` → just re-run the script;
  local skills live in the seed and need no rebuild.
- Adding a whole new **git repo** source → it must be cloned, so **rebuild the
  image** (the build-time `--clone-only` step pulls it); then restart.
- Adding a **local directory** source → point `dir` at a git-tracked folder in
  the seed and re-run; no rebuild needed.
- Removing a skill → the script removes its managed copy on the next run.

## Notes / gotchas

- **The generated skill copies in `skills/` are gitignored** and regenerated;
  don't commit them, don't edit them by hand. The **source of truth for your
  own skills is `seed/.pi/agent/skills-src/`** — edit there, then re-run the
  sync to install.
- **Collisions resolve serially, last wins**: later sources override earlier
  ones on basename collision. By default the local source is declared last, so
  your own skill with the same name as an upstream one wins.
- **New git repo sources require a rebuild.** Only skills whose repos are
  already baked into the image can be enabled at container start; adding a new
  repo means a `scripts/build-container.sh` rebuild (the build-time
  `--clone-only` step pulls it). Local sources never require a rebuild.
- Git repos are plain clones (not submodules) — `seed/.pi/agent/skills.json`
  is the source of truth, and a fresh image self-heals by re-cloning at build
  time.