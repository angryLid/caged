---
name: skills-sync
description: Sync the project's declaratively-configured skills (seed/.pi/agent/skills.json) — clone/pull the source skill repos and (re)install the enabled skills for pi. Use when the user says "sync skills", "update skills", "pull skills", "install skills", "refresh skills", after editing skills.json, or when newly added skills aren't showing up.
---

# skills-sync

Synchronises the skills declared in `seed/.pi/agent/skills.json` into the
location pi scans for skills.

## Where skills live

This project is a container image ("caged") that runs pi. pi scans
`~/.pi/agent/skills/`, and `~/.pi` is a **live bind mount** of the host
`seed/.pi` dir (set up by compose.yaml). So skills are installed **into the
seed** — `seed/.pi/agent/skills/` — not into a user's project working tree.

Inside the seed, each enabled skill is a **real directory copy** (not a
symlink) carrying a hidden `.caged-skill-managed` marker file. The marker lets
the tool tell its own copies apart from hand-written / committed skills, so it
can remove stale ones without ever touching your own.

The skill **source repos** are cloned at **image build time** (see
`Containerfile`) into `/opt/caged/skills/vendor`, baked into the image. At
**container start** the entrypoint only copies the enabled skills from that
baked set into the seed — no network, no git at start.

## How to run

```bash
node scripts/skills-sync.mjs              # local dev: clone/pull repos + install into seed/.pi/agent/skills
node scripts/skills-sync.mjs --dry-run    # preview without changing anything
node scripts/skills-sync.mjs --link-only  # install only, from an existing vendor (no git/network) — what container start does
node scripts/skills-sync.mjs --clone-only # clone/pull repos only (image build step)
node scripts/skills-sync.mjs --seed /agent-home/.pi/agent   # explicit seed dir
```

Exit codes: `0` ok, `1` fatal, `2` warnings only (missing skill / collision) — installs still applied.

## When the user edits `skills.json`

- Adding a skill to an existing repo's `enabled` → re-run the script (or
  rebuild + restart if the repo isn't already in the image vendor).
- Adding a whole new repo → it must be cloned, so **rebuild the image** (the
  build-time clone pulls it in); then restart.
- Removing a skill → the script removes its managed copy on the next run.

## Notes / gotchas

- **The generated skill copies are gitignored** and regenerated; don't commit
  them, don't edit them by hand. Hand-written skills committed in
  `seed/.pi/agent/skills/` (bgm-metadata, caged-persistence, create-post,
  markdown-link, mdx-notes, skills-sync) carry no marker and are never
  clobbered.
- **Collisions**: two repos can ship a skill with the same name (e.g. `handoff`
  exists in both gitlab-ai-skills and mattpocock-skills). pi keeps the first
  one loaded and warns. Enable only one of a colliding pair.
- **New repos require a rebuild.** Only skills whose repos are already baked
  into the image can be enabled at container start; adding a new repo means a
  `podman compose build` (the build-time `--clone-only` step pulls it).
- Repos are plain clones (not submodules) — `seed/.pi/agent/skills.json` is the
  source of truth, and a fresh image self-heals by re-cloning at build time.