#!/usr/bin/env node
// dsh/scripts/ensure-workspace.mjs — make /workspace a registered dsh workspace.
//
// Why this exists: dsh's Web UI has NO environment variable for a default
// workspace. The "which workspace did the user pick" state lives in the
// durable domain store at $DSH_HOME/storages/workspace.json (the workspace
// registry), and dsh derives its default/active selection from that registry
// (recently-active workspace). caged always mounts the user's code at
// /workspace, so on a fresh seed we want the Web UI to open on /workspace
// instead of asking the user to "Choose workspace" on first use.
//
// This helper is idempotent and best-effort:
//   * $DSH_HOME/storages/workspace.json absent  -> write a minimal, valid
//     registry with a single /workspace workspace.
//   * present and already lists /workspace       -> no-op.
//   * present but no /workspace                  -> add /workspace (additive;
//     never deletes existing workspaces/sessions).
//   * anything else (bad JSON, foreign schema)   -> warn and skip. It must
//     NEVER block dsh's boot or clobber the user's own registrations.
//
// The file is an internal dsh domain-store format (unit `workspace`, version
// 2 as of dsh 0.1.0-rc.x). If dsh bumps that version the shape below stops
// matching and this helper simply backs off (the log+last-good warning in
// the entrypoint covers it); it is not a contract we control.

import { strict as assert } from 'node:assert'
import { randomUUID } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

const DSH_HOME = process.env.DSH_HOME || resolve(process.env.HOME || '/agent-home', '.dsh')
const WS_ROOT = '/workspace' // the container's fixed code mount (see compose.yaml / start-container.sh)
const TITLE = 'workspace' // basename(WS_ROOT); matches dsh's workspaceTitleOf()

const workspaceJson = resolve(DSH_HOME, 'storages', 'workspace.json')

function canonical(record) {
  // dsh stamps the fs.realpath canon; compare against the same spelling we seed.
  return record?.path
}

try {
  mkdirSync(dirname(workspaceJson), { recursive: true })

  let document
  try {
    document = JSON.parse(readFileSync(workspaceJson, 'utf8'))
  } catch {
    document = null // absent or unparsable -> treat as fresh
  }

  const hasWorkspacePath = (doc) =>
    Boolean(doc?.unit?.name === 'workspace' &&
      doc?.tables?.workspaces &&
      Object.values(doc.tables.workspaces).some((r) => canonical(r) === WS_ROOT))

  if (document && hasWorkspacePath(document)) {
    // Already registered: nothing to do.
    process.exit(0)
  }

  if (!document) {
    // Fresh registry: write an initialized store with one /workspace entry.
    const id = randomUUID()
    const now = new Date().toISOString()
    document = {
      unit: { name: 'workspace', version: 2 },
      global: { initialized: true, workspaceIds: [id], archivedSessionIds: [] },
      tables: {
        workspaces: {
          [id]: { path: WS_ROOT, title: TITLE, sessionIds: [], createdAt: now, updatedAt: now },
        },
      },
    }
  } else {
    // Existing registry missing /workspace: add one, prepend to display order.
    assert.equal(document.unit.name, 'workspace', 'not the workspace unit')
    assert.ok(document.global && Array.isArray(document.global.workspaceIds), 'registry order missing')
    assert.ok(document.tables && typeof document.tables.workspaces === 'object', 'workspaces table missing')
    assert.equal(typeof document.unit.version, 'number', 'workspace unit version missing')
    const id = randomUUID()
    const now = new Date().toISOString()
    document.tables.workspaces[id] = {
      path: WS_ROOT, title: TITLE, sessionIds: [], createdAt: now, updatedAt: now,
    }
    if (!Array.isArray(document.global.archivedSessionIds)) document.global.archivedSessionIds = []
    document.global.workspaceIds.unshift(id)
  }

  writeFileSync(workspaceJson, JSON.stringify(document, null, 2) + '\n', { mode: 0o600 })
  console.log(`dsh: seeded workspace registry with ${WS_ROOT} (${workspaceJson})`)
} catch (err) {
  // Best-effort only: log and let dsh boot regardless.
  console.warn(`dsh: warn: could not seed default workspace ${WS_ROOT}: ${err.message}`)
}