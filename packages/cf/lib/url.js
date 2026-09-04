'use strict';

const { UsageError } = require('./errors');

/**
 * Parse a Confluence Cloud page URL into { site, pageId }.
 * The site (host) is derived from the URL itself, so no CFL_URL is needed.
 *
 * Accepted shapes:
 *   https://<site>.atlassian.net/wiki/spaces/<KEY>/pages/<ID>
 *   https://<site>.atlassian.net/wiki/pages/viewpage.action?pageId=<ID>
 *   https://<site>.atlassian.net/wiki/pages/<ID>
 */
function parseTarget(input) {
  if (typeof input !== 'string' || input.trim() === '') {
    throw new UsageError('missing URL; usage: cf <confluence-page-url> [options]');
  }
  const url = input.trim();

  let m = url.match(/^https?:\/\/([^/?#]+)(?:\/wiki)?\/spaces\/[^/?#]+\/pages\/(\d+)/);
  if (m) return { site: m[1], pageId: m[2] };

  m = url.match(/^https?:\/\/([^/?#]+)(?:\/wiki)?\/pages\/viewpage\.action\?[^ ]*pageId=(\d+)/);
  if (m) return { site: m[1], pageId: m[2] };

  m = url.match(/^https?:\/\/([^/?#]+)\/wiki\/pages\/(\d+)/);
  if (m) return { site: m[1], pageId: m[2] };

  if (/^\d+$/.test(url)) {
    throw new UsageError(
      'a bare page ID is not enough: the site must come from a full URL,\n' +
        '  e.g. https://<site>.atlassian.net/wiki/spaces/EMFE/pages/' + url
    );
  }

  throw new UsageError(
    'unrecognized Confluence page URL: ' + url + '\n' +
      '  expected forms:\n' +
      '    https://<site>.atlassian.net/wiki/spaces/<KEY>/pages/<ID>\n' +
      '    https://<site>.atlassian.net/wiki/pages/viewpage.action?pageId=<ID>\n' +
      '    https://<site>.atlassian.net/wiki/pages/<ID>'
  );
}

module.exports = { parseTarget };