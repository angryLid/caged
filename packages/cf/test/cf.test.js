// Offline self-tests for @caged/cf — no network, no credentials required.
// Run: npm test   (or: node test/cf.test.js)
'use strict';
const assert = require('assert');
const { parseTarget } = require('../lib/url');
const { storageToMarkdown } = require('../lib/storage-md');
const { adfToMarkdown } = require('../lib/adf-md');
const { parseArgs } = require('../bin/cf');

let passed = 0;
function t(name, fn) {
  fn();
  passed++;
  console.log('ok - ' + name);
}

/* ---- URL parsing ---- */
t('parses /wiki/spaces/KEY/pages/ID', () => {
  assert.deepStrictEqual(
    parseTarget('https://eachvector.atlassian.net/wiki/spaces/EMFE/pages/5415665912'),
    { site: 'eachvector.atlassian.net', pageId: '5415665912' }
  );
});
t('parses viewpage.action with query', () => {
  assert.deepStrictEqual(
    parseTarget('https://site.atlassian.net/wiki/pages/viewpage.action?pageId=12345&x=1'),
    { site: 'site.atlassian.net', pageId: '12345' }
  );
});
t('parses /wiki/pages/ID', () => {
  assert.deepStrictEqual(parseTarget('https://site.atlassian.net/wiki/pages/999'), {
    site: 'site.atlassian.net',
    pageId: '999',
  });
});
t('accepts trailing slash / fragment', () => {
  assert.deepStrictEqual(parseTarget('https://site.atlassian.net/wiki/spaces/DEV/pages/42/#title'), {
    site: 'site.atlassian.net',
    pageId: '42',
  });
});
t('rejects bare page id', () => {
  assert.throws(() => parseTarget('5415665912'), /site must come from a full URL/);
});
t('rejects garbage', () => {
  assert.throws(() => parseTarget('https://example.com/not-confluence'), /unrecognized/);
});

/* ---- storage XHTML -> markdown ---- */
const SITE = 'eachvector.atlassian.net';
const PID = '5415665912';
const opts = { site: SITE, pageId: PID, showMacros: false };

t('converts headings/paragraphs/emphasis', () => {
  const md = storageToMarkdown('<h1>Big</h1><p>Hello <strong>bold</strong> and <em>it</em>.</p>', opts);
  assert.ok(md.includes('# Big'));
  assert.ok(md.includes('**bold**') && md.includes('*it*'));
});

t('converts code macro to fenced code block', () => {
  const html =
    '<ac:structured-macro ac:name="code"><ac:parameter ac:name="language">python</ac:parameter>' +
    '<ac:plain-text-body><![CDATA[def f(x):\n    return x < 3 & 5]]></ac:plain-text-body></ac:structured-macro>';
  const md = storageToMarkdown(html, opts);
  assert.ok(md.includes('```python'));
  assert.ok(md.includes('def f(x):'));
  assert.ok(md.includes('< 3 & 5')); // CDATA must not be double-escaped
});

t('keeps info-macro body, drops wrapper (default)', () => {
  const html = '<ac:structured-macro ac:name="info"><ac:rich-text-body><p>Remember this.</p></ac:rich-text-body></ac:structured-macro>';
  const md = storageToMarkdown(html, opts);
  assert.ok(md.includes('Remember this.'));
  assert.ok(!md.includes('[INFO]'));
});

t('show-macros emits bracket syntax', () => {
  const html = '<p>Start</p><ac:structured-macro ac:name="info"><ac:rich-text-body><p>Box text</p></ac:rich-text-body></ac:structured-macro>';
  const md = storageToMarkdown(html, { ...opts, showMacros: true });
  assert.ok(md.includes('[INFO]'));
  assert.ok(md.includes('[/INFO]'));
  assert.ok(md.includes('Box text'));
});

t('converts internal page link with known id', () => {
  const html = '<p>See <ac:link><ri:page ri:content-title="Setup" ri:space-key="EMFE" ri:content-id="777"/></ac:link>.</p>';
  const md = storageToMarkdown(html, opts);
  assert.ok(md.includes('[Setup](https://eachvector.atlassian.net/wiki/spaces/EMFE/pages/777)'));
});

t('keeps wiki-link syntax when id unknown', () => {
  const html = '<p>See <ac:link><ri:page ri:content-title="Other Page" ri:space-key="EMFE"/></ac:link>.</p>';
  const md = storageToMarkdown(html, opts);
  assert.ok(md.includes('[EMFE:Other Page]'));
});

t('converts attachment to download url', () => {
  const html = '<p>File: <ac:link><ri:attachment ri:filename="arch.pdf"/></ac:link></p>';
  const md = storageToMarkdown(html, opts);
  assert.ok(md.includes('https://eachvector.atlassian.net/wiki/download/attachments/5415665912/arch.pdf'));
});

t('converts image macro to img url', () => {
  const html = '<ac:image><ri:attachment ri:filename="diagram.png"/></ac:image>';
  const md = storageToMarkdown(html, opts);
  assert.ok(
    md.includes('![diagram.png](https://eachvector.atlassian.net/wiki/download/attachments/5415665912/diagram.png)')
  );
});

t('converts GFM tables', () => {
  const html = '<table><tr><th>K</th><th>V</th></tr><tr><td>a</td><td>1</td></tr></table>';
  const md = storageToMarkdown(html, opts);
  assert.ok(md.includes('| K | V |'));
  assert.ok(md.includes('| a | 1 |'));
});

t('never truncates long content', () => {
  const long = '<p>' + Array.from({ length: 3000 }, (_, i) => 'word' + i).join(' ') + '</p>';
  const md = storageToMarkdown(long, opts);
  assert.ok(md.length > 10000, 'content length ' + md.length);
});

/* ---- ADF -> markdown ---- */
t('ADF headings/paragraphs/lists', () => {
  const adf = {
    type: 'doc',
    version: 1,
    content: [
      { type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'Section' }] },
      {
        type: 'bulletList',
        content: [
          {
            type: 'listItem',
            content: [
              { type: 'paragraph', content: [{ type: 'text', text: 'one' }] },
              {
                type: 'bulletList',
                content: [
                  {
                    type: 'listItem',
                    content: [{ type: 'paragraph', content: [{ type: 'text', text: 'nested' }] }],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  };
  const md = adfToMarkdown(JSON.stringify(adf));
  assert.ok(md.includes('## Section'));
  assert.ok(md.includes('- one'));
  assert.ok(md.includes('nested'));
});

t('ADF marks and links', () => {
  const adf = {
    type: 'doc',
    content: [
      {
        type: 'paragraph',
        content: [
          { type: 'text', text: 'go ' },
          { type: 'text', text: 'here', marks: [{ type: 'link', attrs: { href: 'https://x.dev' } }] },
          { type: 'text', text: ' and ', marks: [{ type: 'strong' }] },
        ],
      },
    ],
  };
  const md = adfToMarkdown(adf);
  assert.ok(md.includes('[here](https://x.dev)'));
  assert.ok(md.includes('** and **'));
});

t('ADF code block and table', () => {
  const adf = {
    type: 'doc',
    content: [
      { type: 'codeBlock', attrs: { language: 'js' }, content: [{ type: 'text', text: 'let x = 1;' }] },
      {
        type: 'table',
        content: [
          {
            type: 'tableRow',
            content: [
              { type: 'tableHeader', content: [{ type: 'text', text: 'A' }] },
              { type: 'tableHeader', content: [{ type: 'text', text: 'B' }] },
            ],
          },
          {
            type: 'tableRow',
            content: [
              { type: 'tableCell', content: [{ type: 'text', text: '1' }] },
              { type: 'tableCell', content: [{ type: 'text', text: '2' }] },
            ],
          },
        ],
      },
    ],
  };
  const md = adfToMarkdown(adf);
  assert.ok(md.includes('```js'));
  assert.ok(md.includes('| A | B |'));
  assert.ok(md.includes('| 1 | 2 |'));
});

/* ---- CLI arg parsing ---- */
t('parses flags and positional url', () => {
  const o = parseArgs(['--children', '--no-meta', 'https://site.atlassian.net/wiki/spaces/DEV/pages/1']);
  assert.ok(o.children && o.noMeta);
  assert.strictEqual(o.url, 'https://site.atlassian.net/wiki/spaces/DEV/pages/1');
});
t('rejects unknown option', () => {
  assert.throws(() => parseArgs(['--bogus']), /unknown option/);
});
t('rejects bad --raw value', () => {
  assert.throws(() => parseArgs(['--raw', 'json', 'https://site.atlassian.net/wiki/spaces/DEV/pages/1']), /--raw needs one of/);
});

console.log('\nAll ' + passed + ' tests passed.');