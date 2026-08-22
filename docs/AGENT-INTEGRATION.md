# Agent Integration — Requirements

This document is the contract for integrating a new coding agent into caged.
Any agent added beyond the existing ones (`pi`, `dsh`, `cmdc` / Command Code)
must satisfy the three hard requirements below. They are non-negotiable and
must all be met.

## Requirement 1 — Run with the highest privilege / no permission guard

Caged's isolation boundary is the container itself. An agent that runs its own
permission dialogs, approval prompts, or deny/ask rules adds friction it cannot
need:

- blocked runs — an unanswered prompt hangs the whole task during unattended or
  background operation;
- pointless friction and an untrustworthy "permission judgment" that prompt
  injection can defeat.

The stance is deliberate: **no guard outside the sandbox, and no guard inside
it either.** The agent must run in its native "allow everything" mode with no
permission prompts or guards of its own. Any trust or consent setting must be
turned on, and no deny/ask rules may be configured.

## Requirement 2 — Sessions live under `/workspace`

Containers are disposable, but `/workspace` is a live bind-mount of the host
workspace, so it survives container teardown. Session data must live under
`/workspace` so that:

- sessions persist after the container is destroyed;
- every agent runs on the same workspace and can read one another's session
  records;
- per-agent session directories are isolated under their own names and never
  conflict.

Sessions written inside the container or in the seed would either vanish with
the container or accumulate in the repo to be tracked and polluted. They must
not do that.

## Requirement 3 — Sync the global prompt

Every agent carries the same always-loaded environment primer — the baseline
rules for working inside caged. Alongside it, agents share a common skills set.
Both are delivered through one declarative mechanism, so the rules and
capabilities an agent runs with are the same regardless of which agent is
running.

**How the shared mechanism works.** caged keeps a single source of truth for
each of the two, maintained in the seed alongside the rest of the config:

- **Global prompt** — one authoritative environment primer, with no per-agent
  variants. Each agent's runtime loads it as its user-level always-on
  instructions, and the delivered copy is byte-identical everywhere.
- **Skills** — one shared, declaratively-enabled set of Agent Skills (the open
  standard: a directory per skill with a `SKILL.md`). Each agent scans its own
  skills directory at runtime.

At every container start, each agent's home gets the global prompt and its
enabled skills installed from those shared sources. Hand-maintained per-agent
copies do not exist: an edit to the source takes effect on the next start, and
nothing that is generated is ever committed or hand-edited.

**What integrating a new agent requires.** The new agent must participate in
this same mechanism — not receive the content once and be done:

- it must load the shared global prompt, verbatim and identical to every other
  agent, through whatever mechanism its runtime exposes for user-level
  always-on instructions, present on first run without manual setup;
- it must consume the shared skills through the Agent Skills standard, scanning
  the skills directory its home provides, so the same declarations that feed
  the existing agents feed it too;
- its startup must install its copies from the shared sources exactly like the
  existing agents, so the prompt and skills stay in sync automatically and
  cannot drift.