'use strict';

const { fail } = require('./errors');

const VERSION = require('../package.json').version;
const FETCH_TIMEOUT_MS = 30000;

/**
 * Core GET against the Confluence Cloud v2 REST API.
 * path is relative to the site root, e.g. "/api/v2/pages/123?body-format=storage";
 * the "/wiki" prefix and site host are added here.
 *
 * With { safe: true } failures return null instead of exiting (used for
 * optional lookups such as space keys and child pages, which must not kill
 * the whole run).
 */
async function apiGet(site, creds, path, opts) {
  const safe = !!(opts && opts.safe);
  const url = 'https://' + site + '/wiki' + path;
  let res;
  try {
    res = await fetch(url, {
      headers: {
        Authorization: creds.authHeader,
        Accept: 'application/json',
        'User-Agent': 'cf/' + VERSION,
      },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (err) {
    if (safe) return null;
    if (err && err.name === 'TimeoutError') {
      fail(3, 'request timed out after ' + FETCH_TIMEOUT_MS + 'ms: ' + url);
    }
    fail(3, 'network error for ' + url + ': ' + (err && err.message ? err.message : err));
  }

  if (res.status === 401 || res.status === 403) {
    if (safe) return null;
    fail(
      2,
      (res.status === 401 ? 'authentication failed (401)' : 'forbidden (403)') +
        ' for ' + url + '\n' +
        '  check that email/token are correct and have read access to this page.'
    );
  }
  if (res.status === 404) {
    if (safe) return null;
    fail(
      4,
      'not found (404): ' + url + '\n' +
        '  Confluence hides unauthorized pages as 404 — if the page exists,' +
        ' the email/token may lack access to it.'
    );
  }
  if (res.status === 429) {
    if (safe) return null;
    fail(5, 'rate limited (429) by Confluence; retry after backoff: ' + url);
  }
  if (!res.ok) {
    if (safe) return null;
    fail(3, 'HTTP ' + res.status + ' from ' + url);
  }

  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch (err) {
    if (safe) return null;
    fail(3, 'non-JSON response from ' + url + ' (HTTP ' + res.status + ')');
  }
}

async function fetchPage(site, creds, pageId, bodyFormat) {
  const q = bodyFormat ? '?body-format=' + encodeURIComponent(bodyFormat) : '';
  return apiGet(site, creds, '/api/v2/pages/' + pageId + q);
}

/**
 * Mirrors cfl's getPageWithBodyFallback: storage first; ADF-native pages
 * (cloud editor) often return an empty storage body, so fall back to
 * atlas_doc_format.
 *
 * Returns { page, bodyFormat: 'storage'|'adf', body }.
 */
async function fetchPageWithFallback(site, creds, pageId) {
  const storagePage = await fetchPage(site, creds, pageId, 'storage');
  const storageBody =
    storagePage.body && storagePage.body.storage ? storagePage.body.storage.value : '';
  if (storageBody && storageBody.trim() !== '') {
    return { page: storagePage, bodyFormat: 'storage', body: storageBody };
  }
  const adfPage = await fetchPage(site, creds, pageId, 'atlas_doc_format');
  const adfBody =
    adfPage.body && adfPage.body.atlas_doc_format ? adfPage.body.atlas_doc_format.value : '';
  return { page: adfPage, bodyFormat: 'adf', body: adfBody };
}

/** Child pages of a page (optional lookup; failures return []). */
async function fetchChildren(site, creds, pageId) {
  const data = await apiGet(site, creds, '/api/v2/pages/' + pageId + '/children?limit=200', {
    safe: true,
  });
  return (data && data.results) || [];
}

const spaceKeyCache = new Map();

/** Space key for a spaceId (optional lookup; failures return null). */
async function getSpaceKey(site, creds, spaceId) {
  if (!spaceId) return null;
  if (spaceKeyCache.has(spaceId)) return spaceKeyCache.get(spaceId);
  const space = await apiGet(site, creds, '/api/v2/spaces/' + spaceId, { safe: true });
  const key = (space && space.key) || null;
  spaceKeyCache.set(spaceId, key);
  return key;
}

module.exports = {
  apiGet,
  fetchPage,
  fetchPageWithFallback,
  fetchChildren,
  getSpaceKey,
  FETCH_TIMEOUT_MS,
};