---
name: caged-persistence
description: 'Persist pi skills and packages (extensions) by writing them into the caged seed. `$HOME` is a LIVE bind mount of `caged/seed`, so `~/.pi/agent` is exactly `seed/.pi/agent` — anything pi writes there (new skills, package entries in seed/.pi/agent/settings.json packages[], even auth.json) lands in the host repo immediately — no rebuild or volume-copy step needed. CAVEAT: for skills declared in `skills.json` (managed), the durable location is the SOURCE (`skills-src/<name>/` for local, the git repo for git) — edit there and re-run skills-sync, because `skills/` is a generated, overwritten install dir. Use when creating or editing a pi skill or installing a pi extension and wanting it in every future caged run.'
---

# caged persistence

In caged, `~/.pi` (`/agent-home/.pi`) is a **live bind mount** of the host
directory `caged/seed/.pi`, so `~/.pi/agent` (`/agent-home/.pi/agent`) is the
host dir `caged/seed/.pi/agent`. Everything pi writes there is synced back to the host
repo at the same moment — config edits, new skills, extension packages, even
`auth.json` (which is gitignored). There is no named volume to wipe and
nothing to re-seed: the seed *is* the source of truth on the host.

What is durable automatically:

1. **New pi skills** — `SKILL.md` files (and their script helpers) written
   under `seed/.pi/agent/skills/` exist in the repo on the next `git diff`.
2. **Pi packages / extensions** — entries in `seed/.pi/agent/settings.json`
   → `packages[]`.

## Two kinds of skills: managed vs. free-standing

`caged/seed/.pi/agent/skills/` is **not a plain directory** — it is the
**install destination** of the skills-sync tool (`skills-sync.mjs`), which
regenerates it from sources. This matters a lot for where you edit a skill:

* **Managed skills** — declared in `seed/.pi/agent/skills.json` under
  `sources[].enabled`, coming from either a **git** repo (cloned at build
  time) or the **local** source (`skills-src/`, git-tracked). Their installed
  copies in `skills/` carry a hidden `.caged-skill-managed` marker and are
  **gitignored + overwritten** on every sync / container start. The source of
  truth is the *source* (git repo or `skills-src/`), NOT `skills/`.

  > **Edit the source, then re-run sync.**
  > For a local skill: edit `seed/.pi/agent/skills-src/<name>/SKILL.md`, then
  > run `node /opt/caged/skills-sync.mjs --config ... --seed ... --vendor ...
  > --link-only` (or let the container restart re-sync). Editing `skills/`
  > directly is pointless — it will be overwritten.

* **Free-standing skills** — hand-created skills you drop straight into
  `seed/.pi/agent/skills/<name>/` and do **not** declare in `skills.json`.
  They are unmanaged (no `.caged-skill-managed` marker) and persist as-is.

**How to tell them apart:** if a skill is listed in
`seed/.pi/agent/skills.json` → `enabled`, it is managed — edit the source, not
`skills/`. If it is not in the config, it is free-standing and `skills/` is
fine. The `skills-sync` skill has the full picture.

Runtime state that must **not** be committed to git:

- `seed/.pi/agent/auth.json` — pi api keys / tokens (see `.gitignore`)
- `$CAGED_WORKSPACE/sessions/` — pi session data, mounted at
  `/agent-home/.pi/agent/sessions` per project, lives next to the code
- API keys / scratch files — never put them in `/workspace`

## When to use

- You are about to create a new skill and want it in every future caged run.
- You are about to `pi install` an extension (npm / git / local path) and
  want it to persist across container restarts.

Because the seed is live, persistence is the default: just create or edit the
file under `caged/seed/.pi/agent/`. **For managed skills, that means editing
the source (`skills-src/<name>/SKILL.md` for local skills) and re-running the
sync — not editing `skills/` directly.** If the user says "don't touch the
seed", write to a non-seed location (e.g. `/workspace`) instead and skip this
skill.
