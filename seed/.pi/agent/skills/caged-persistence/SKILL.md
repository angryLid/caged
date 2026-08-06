---
name: caged-persistence
description: Persist pi skills and packages (extensions) by writing them into the caged seed. `$HOME` is a LIVE bind mount of `caged/seed`, so `~/.pi/agent` is exactly `seed/.pi/agent` — anything pi writes there (new skills under seed/.pi/agent/skills/, package entries in seed/.pi/agent/settings.json packages[], even auth.json) lands in the host repo immediately — no rebuild or volume-copy step needed. Use when creating a new skill or installing a pi extension and wanting it in every future caged run.
---

# caged persistence

In caged, `$HOME` (`/pi-agent`) is a **live bind mount** of the host directory
`caged/seed`, so `~/.pi/agent` (`/pi-agent/.pi/agent`) is the host dir
`caged/seed/.pi/agent`. Everything pi writes there is synced back to the host
repo at the same moment — config edits, new skills, extension packages, even
`auth.json` (which is gitignored). There is no named volume to wipe and
nothing to re-seed: the seed *is* the source of truth on the host.

What is durable automatically:

1. **New pi skills** — `SKILL.md` files (and their script helpers) written
   under `seed/.pi/agent/skills/` exist in the repo on the next `git diff`.
2. **Pi packages / extensions** — entries in `seed/.pi/agent/settings.json`
   → `packages[]`.

Runtime state that must **not** be committed to git:

- `seed/.pi/agent/auth.json` — pi api keys / tokens (see `.gitignore`)
- `$CAGED_WORKSPACE/sessions/` — pi session data, mounted at
  `/pi-agent/.pi/agent/sessions` per project, lives next to the code
- API keys / scratch files — never put them in `/workspace`

## When to use

- You are about to create a new skill and want it in every future caged run.
- You are about to `pi install` an extension (npm / git / local path) and
  want it to persist across container restarts.

Because the seed is live, persistence is the default: just create or edit the
file under `caged/seed/.pi/agent/`. If the user says "don't touch the seed",
write to a non-seed location (e.g. `/workspace`) instead and skip this skill.
