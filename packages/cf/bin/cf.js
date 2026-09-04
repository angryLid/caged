#!/usr/bin/env node
/**
 * cf — Confluence page reader for coding agents.
 *
 * Usage:  cf <confluence-page-url> [options]
 *
 * Given a Confluence Cloud page URL such as
 *   https://<site>.atlassian.net/wiki/spaces/EMFE/pages/5415665912
 * it prints the page's full content as Markdown (never truncated), with a
 * compact metadata header, ready to feed to a coding agent.
 *
 * Auth is deliberately boring: the SITE is parsed from the URL itself and the
 * credentials come straight from the environment (same values caged already
 * passes for cfl / jira-cli):
 *
 *   email:  CFL_EMAIL        -> ATLASSIAN_EMAIL
 *   token:  CFL_API_TOKEN    -> ATLASSIAN_API_TOKEN -> JIRA_API_TOKEN
 *
 * Basic auth (email + Atlassian API token) is used against the Confluence
 * Cloud v2 REST API. No config file, no init, no keyring.
 *
 * Options:
 *   --no-meta        omit the metadata header (title is still printed)
 *   --children       append a "Child pages" section (links to sub-pages)
 *   --show-macros    keep Confluence macros as [TOC] / [INFO]..[/INFO] etc.
 *   --raw <fmt>      print the raw body instead of Markdown: storage | adf
 *   -h, --help       this help
 *   --version        print version
 *
 * Exit codes: 0 ok; 1 usage/parse error; 2 auth/credentials; 3 API/network;
 *             4 not found (404); 5 rate-limited (429).
 */
'use strict';

const { parseTarget } = require('../lib/url');
const { getCredentials } = require('../lib/auth');
const api = require('../lib/api');
const { storageToMarkdown } = require('../lib/storage-md');
const { adfToMarkdown } = require('../lib/adf-md');
const { UsageError } = require('../lib/errors');

const VERSION = require('../package.json').version;

const HELP = `cf — Confluence page reader for coding agents.

Usage:  cf <confluence-page-url> [options]

Reads a Confluence Cloud page and prints its full content as Markdown.
The site is taken from the URL; credentials come from the environment:
  email:  CFL_EMAIL | ATLASSIAN_EMAIL
  token:  CFL_API_TOKEN | ATLASSIAN_API_TOKEN | JIRA_API_TOKEN
(in caged these are set by start-container.sh; no config or keyring needed)

Options:
  --no-meta        omit the metadata header (title is still printed)
  --children       append a "Child pages" section with links
  --show-macros    keep Confluence macros as [TOC] / [INFO]..[/INFO]
  --raw storage|adf   print the raw body instead of converted Markdown
  -h, --help       show this help
  --version        print version

Exit codes: 0 ok | 1 usage | 2 auth | 3 API/network | 4 not found | 5 rate-limited
`;

function parseArgs(argv) {
  const opts = { noMeta: false, children: false, showMacros: false, raw: null };
  const positional = [];
  for (const a of argv) {
    if (a === '--no-meta') opts.noMeta = true;
    else if (a === '--children') opts.children = true;
    else if (a === '--show-macros') opts.showMacros = true;
    else if (a === '--raw') {
      const v = argv[argv.indexOf(a) + 1];
      if (v !== 'storage' && v !== 'adf') {
        throw new UsageError('--raw needs one of: storage | adf');
      }
      opts.raw = v;
    } else if (a.startsWith('--raw=')) {
      const v = a.slice(6);
      if (v !== 'storage' && v !== 'adf') throw new UsageError('--raw needs one of: storage | adf');
      opts.raw = v;
    } else if (a === '-h' || a === '--help') opts.help = true;
    else if (a === '--version') opts.version = true;
    else if (a.startsWith('-')) throw new UsageError('unknown option: ' + a);
    else positional.push(a);
  }
  opts.url = positional[0];
  if (positional.length > 1) throw new UsageError('too many arguments: ' + positional.slice(1).join(' '));
  return opts;
}

/** ISO timestamp in a readable form, or '' when absent/invalid. */
function fmtIso(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  return Number.isNaN(d.getTime()) ? String(ts) : d.toISOString().replace('T', ' ').replace(/\.\d+Z$/, ' UTC');
}

/** Append a "Child pages" section (alphabetical links). Failures are non-fatal. */
async function printChildren(site, creds, pageId, spaceKeyHint) {
  let children;
  try {
    children = await api.fetchChildren(site, creds, pageId);
  } catch (err) {
    console.error('cf: could not fetch children (continuing without them)');
    return;
  }
  if (!children.length) return;
  console.log('\n## Child pages\n');
  for (const c of children.sort((a, b) => String(a.title || '').localeCompare(String(b.title || '')))) {
    const key = (await api.getSpaceKey(site, creds, c.spaceId)) || spaceKeyHint || '';
    const href = 'https://' + site + '/wiki/spaces/' + encodeURIComponent(key) + '/pages/' + c.id;
    console.log('- [' + (c.title || c.id) + '](' + href + ')');
  }
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error('cf: ' + err.message);
    console.error(HELP);
    process.exit(1);
  }
  if (opts.help) {
    console.log(HELP);
    return;
  }
  if (opts.version) {
    console.log('cf ' + VERSION);
    return;
  }

  let target;
  try {
    target = parseTarget(opts.url);
  } catch (err) {
    console.error('cf: ' + err.message);
    process.exit(1);
  }

  const creds = getCredentials();
  const { site, pageId } = target;

  const { page, bodyFormat, body } = await api.fetchPageWithFallback(site, creds, pageId);

  const title = page.title || 'Page ' + pageId;
  console.log('# ' + title + '\n');

  if (!opts.noMeta) {
    const spaceId = page.spaceId;
    const spaceKey = await api.getSpaceKey(site, creds, spaceId);
    const ver = page.version || {};
    const parts = [];
    parts.push('Page: https://' + site + '/wiki/spaces/' + encodeURIComponent(spaceKey || '') + '/pages/' + pageId);
    parts.push('Space: ' + (spaceKey || spaceId || '-'));
    parts.push('Version: ' + (ver.number != null ? ver.number : '-'));
    const updated = fmtIso(ver.createdAt || page.createdAt);
    if (updated) parts.push('Updated: ' + updated);
    if (ver.authorId) parts.push('By: ' + ver.authorId);
    parts.push('Body: ' + (bodyFormat === 'adf' ? 'atlas_doc_format (storage empty)' : 'storage'));
    console.log(parts.join(' · '));
    console.log();
  }

  if (opts.raw) {
    if (bodyFormat === opts.raw) {
      console.log(body);
    } else {
      console.error(
        'cf: requested --raw ' + opts.raw + ' but this page only provides a ' +
          bodyFormat + ' body (empty ' + opts.raw + ' is why the fallback fired)'
      );
      process.exit(3);
    }
    return;
  }

  const markdown =
    body.trim() === ''
      ? '_(empty page)_'
      : bodyFormat === 'adf'
        ? adfToMarkdown(body)
        : storageToMarkdown(body, { site, pageId, showMacros: opts.showMacros });

  console.log(markdown);

  if (opts.children) {
    const spaceKey = await api.getSpaceKey(site, creds, page.spaceId);
    await printChildren(site, creds, pageId, spaceKey);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('cf: unexpected error: ' + (err && err.stack ? err.stack : err));
    process.exit(3);
  });
}

module.exports = { parseArgs, main, printChildren, fmtIso };