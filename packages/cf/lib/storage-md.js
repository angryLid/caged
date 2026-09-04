'use strict';

const { fail } = require('./errors');

/** Load turndown, with a clear hint when the dependency is missing. */
function loadTurndown() {
  try {
    // eslint-disable-next-line global-require
    const TurndownService = require('turndown');
    return TurndownService;
  } catch (err) {
    if (err && err.code === 'MODULE_NOT_FOUND') {
      fail(
        3,
        'dependency "turndown" not found.\n' +
          '  Install with:  (cd packages/cf && npm install)\n' +
          '  (declared in packages/cf/package.json)'
      );
    }
    throw err;
  }
}

const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };
const escapeHtml = (s) => String(s).replace(/[&<>"]/g, (c) => ESC[c]);
const unescapeHtml = (s) =>
  String(s)
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&amp;/g, '&');

/** <ac:plain-text-body><![CDATA[...]]></ac:plain-text-body> -> text */
function extractCDATA(html) {
  const m = html.match(/<ac:plain-text-body>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*<\/ac:plain-text-body>/);
  return m ? m[1] : '';
}

/** Value of an <ac:parameter ac:name="<name>"> inside a macro body. */
function param(html, name) {
  const m = html.match(
    new RegExp('<ac:parameter\\b[^>]*ac:name="' + name + '"[^>]*>([\\s\\S]*?)</ac:parameter>')
  );
  return m ? unescapeHtml(m[1]).trim() : '';
}

/**
 * Preprocess Confluence storage XHTML into plain HTML that turndown can
 * convert faithfully:
 *  - code/noformat macros -> <pre><code>
 *  - other macros: default keeps the body content (drops the wrapper);
 *    --show-macros emits [TOC] / [INFO]...[/INFO] style brackets via a
 *    data-cf-macro div
 *  - <ac:link> -> real <a href> where the target id is known, [[Title]]
 *    wiki-syntax otherwise; attachments -> download URLs; users -> @key
 *  - <ac:image> -> <img> pointing at the attachment download URL
 *  - <ac:emoji> -> :name: (--show-macros) or dropped
 */
function preprocessStorage(html, site, pageId, opts) {
  let out = String(html);

  // 1. code / noformat macros -> <pre><code>
  out = out.replace(
    /<ac:structured-macro\b([^>]*)ac:name="(code|noformat)"([^>]*)>([\s\S]*?)<\/ac:structured-macro>/g,
    (_whole, _a, _macroName, _b, inner) => {
      const lang = param(inner, 'language');
      const code = extractCDATA(inner);
      const cls = lang ? ' class="language-' + escapeHtml(lang) + '"' : '';
      return '<pre><code' + cls + '>' + escapeHtml(code) + '</code></pre>';
    }
  );

  // 2. other structured macros
  out = out.replace(
    /<ac:structured-macro\b([^>]*)ac:name="([^"]+)"([^>]*)>([\s\S]*?)<\/ac:structured-macro>/g,
    (_whole, _a, name, _b, inner) => {
      // strip the body's own parameter/plain-text nodes — those are macro data, not content
      const body = inner
        .replace(/<ac:parameter\b[\s\S]*?<\/ac:parameter>/g, '')
        .replace(/<ac:plain-text-body\b[\s\S]*?<\/ac:plain-text-body>/g, '')
        .trim();
      if (opts.showMacros) {
        const label = name.toUpperCase();
        if (body) {
          // div wrapper + turndown rule turns this into [LABEL]...[/LABEL]
          return (
            '<div data-cf-macro="' +
            escapeHtml(label) +
            '">' +
            body +
            '</div>'
          );
        }
        return '<div data-cf-macro="' + escapeHtml(label) + '" data-cf-empty="1"></div>';
      }
      if (body) return '<div>' + body + '</div>'; // keep macro content for reading
      console.error(
        'cf: stripped empty macro "' + name + '" (run with --show-macros to keep it)'
      );
      return '';
    }
  );

  // 3. <ac:link> internal links / attachments / users
  out = out.replace(
    /<ac:link\b[^>]*>([\s\S]*?)<\/ac:link>/g,
    (_whole, inner) => {
      const page = inner.match(/<ri:page\b([^>]*)\/>/);
      if (page) {
        const attrs = page[1];
        const id = (attrs.match(/ri:content-id="([^"]+)"/) || [])[1];
        const title = (attrs.match(/ri:content-title="([^"]+)"/) || [])[1];
        const space = (attrs.match(/ri:space-key="([^"]+)"/) || [])[1];
        const label = title || 'page ' + id;
        if (id && space) {
          return (
            '<a href="' + 'https://' + site + '/wiki/spaces/' +
            encodeURIComponent(space) + '/pages/' + id + '">' +
            escapeHtml(label) + '</a>'
          );
        }
        // title/space known but no id: keep the classic wiki-link syntax;
        // use letter-only placeholders so turndown leaves them untouched
        return 'CFWIKILINKOPEN' + (space ? space + ':' : '') + label + 'CFWIKILINKCLOSE';
      }
      const att = inner.match(/<ri:attachment\b([^>]*)\/>/);
      if (att) {
        const filename = (att[1].match(/ri:filename="([^"]+)"/) || [])[1] || 'attachment';
        const href =
          'https://' + site + '/wiki/download/attachments/' + pageId + '/' + encodeURIComponent(filename);
        return '<a href="' + href + '">' + escapeHtml(filename) + '</a>';
      }
      const user = inner.match(/<ri:user\b([^>]*)\/>/);
      if (user) {
        const key = (user[1].match(/ri:userkey="([^"]+)"/) || [])[1] || 'user';
        return '@' + key;
      }
      return '';
    }
  );

  // 4. <ac:image> -> <img> attachment URL
  out = out.replace(
    /<ac:image\b[^>]*>([\s\S]*?)<\/ac:image>/g,
    (_whole, inner) => {
      const att = inner.match(/<ri:attachment\b([^>]*)\/>/);
      if (att) {
        const filename = (att[1].match(/ri:filename="([^"]+)"/) || [])[1] || 'image';
        const src =
          'https://' + site + '/wiki/download/attachments/' + pageId + '/' + encodeURIComponent(filename);
        return '<img src="' + src + '" alt="' + escapeHtml(filename) + '" />';
      }
      const srcParam = param(inner, 'src') || param(inner, 'url');
      if (srcParam) return '<img src="' + escapeHtml(srcParam) + '" />';
      return '';
    }
  );

  // 5. emoji
  out = out.replace(/<ac:emoji\b[^>]*ac:name="([^"]+)"[^>]*\/>/g, (_w, name) =>
    opts.showMacros ? ':' + name + ':' : ''
  );

  return out;
}

function makeTurndown(showMacros) {
  const TurndownService = loadTurndown();
  // eslint-disable-next-line global-require
  const gfmPlugin = require('turndown-plugin-gfm');
  const td = new TurndownService({
    headingStyle: 'atx',
    codeBlockStyle: 'fenced',
    bulletListMarker: '-',
    emDelimiter: '*',
    strongDelimiter: '**',
  });
  // GFM tables + strikethrough + task lists (the constructor has no gfm option)
  td.use(gfmPlugin.gfm);

  if (showMacros) {
    td.addRule('cfmacro', {
      filter: (node) =>
        node.nodeName === 'DIV' && node.getAttribute && node.getAttribute('data-cf-macro'),
      replacement: (content, node) => {
        const name = node.getAttribute('data-cf-macro');
        const empty = node.getAttribute('data-cf-empty') === '1';
        const open = '[' + name + ']';
        if (empty) return '\n\n' + open + '\n\n';
        const body = content.trim();
        return '\n\n' + open + '\n' + body + '\n[/' + name + ']\n\n';
      },
    });
  }

  return td;
}

/**
 * Convert Confluence storage XHTML to Markdown.
 * opts: { site, pageId, showMacros }.
 */
function storageToMarkdown(html, opts) {
  const pre = preprocessStorage(html, opts.site, opts.pageId, opts);
  const td = makeTurndown(opts.showMacros);
  const md = td.turndown(pre);
  return md
    .replace(/CFWIKILINKOPEN([\s\S]*?)CFWIKILINKCLOSE/g, '[[$1]]') // restore wiki-link syntax
    .replace(/\n{4,}/g, '\n\n\n') // collapse excessive blank runs
    .trim();
}

module.exports = { preprocessStorage, storageToMarkdown };