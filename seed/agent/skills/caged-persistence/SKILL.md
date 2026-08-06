---
name: caged-persistence
description: Persist new pi skills and pi packages (extensions) across caged volume resets by baking them into the caged seed. Use when creating a new skill (write it to caged/seed/agent/skills/) or installing a pi extension (add it to caged/seed/agent/settings.json packages[]). The named volume /pi-agent survives container restarts, but a completely fresh volume is seeded only from what the image ships, so baked content is the durable source of truth.
---

# caged persistence

In caged, everything under `~/.pi` (`/pi-agent/.pi`) lives on the named
volume `caged-pi-agent`. It **persists across container restarts/recreates**
— but only until the volume is wiped (`podman volume rm caged-pi-agent`). A
brand-new empty volume is seeded from the image's contents at
`/pi-agent/.pi` (`COPY seed` in the `Containerfile`).

Two kinds of assets should therefore be added to the **caged repo's `seed/`
directory**, not merely to the live volume, if they must survive a fresh
volume:

1. **New pi skills** — `SKILL.md` files (and their script helpers) under
   `caged/seed/agent/skills/`
2. **Pi packages / extensions** — entries in `caged/seed/agent/settings.json`
   → `packages[]`

Anything else (API keys, auth tokens, session data, scratch files) is
runtime state and belongs in the live volume only.

## When to use

- You are about to create a new skill and want it in every future caged run.
- You are about to `pi install` an extension (npm / git / local path) and
  want it baked in.
- The user asks to "make this persistent" / "survive a volume reset".

If the user says "just for this run" or "don't touch the seed", operate on
the live volume only and skip this skill.
