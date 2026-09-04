'use strict';

const { fail } = require('./errors');

/**
 * ADF (Atlassian Document Format) -> Markdown.
 * Used for the fallback path: cloud-editor pages whose storage body is empty.
 * A deliberately small recursive renderer covering the node types commonly
 * found in Confluence pages; unknown nodes are descended into or skipped.
 */

/** Inline text with marks. */
function adfText(node) {
  if (node == null) return '';
  if (typeof node === 'string') return node;
  if (Array.isArray(node)) return node.map(adfText).join('');
  if (typeof node === 'object' && node.type) {
    if (node.type === 'text') {
      const t = node.text == null ? '' : String(node.text);
      let out = t;
      const marks = node.marks || [];
      for (const m of marks) {
        if (m.type === 'strong') out = '**' + out + '**';
        else if (m.type === 'em') out = '*' + out + '*';
        else if (m.type === 'strike') out = '~~' + out + '~~';
        else if (m.type === 'code') out = '`' + out + '`';
        else if (m.type === 'link') {
          const href = m.attrs && m.attrs.href ? m.attrs.href : '';
          out = '[' + out + '](' + href + ')';
        }
      }
      return out;
    }
    if (node.type === 'hardBreak') return '\n';
    if (node.type === 'mention') {
      const id =
        node.attrs && (node.attrs.id || node.attrs.text) ? node.attrs.id || node.attrs.text : '';
      return '@' + id;
    }
    if (node.type === 'emoji') {
      const nm = node.attrs && node.attrs.shortName ? node.attrs.shortName : '';
      return ':' + nm + ':';
    }
    if (node.type === 'inlineCard') {
      const href = node.attrs && node.attrs.url ? node.attrs.url : '';
      const title = (node.attrs && node.attrs.title) || href || 'link';
      return href ? '[' + title + '](' + href + ')' : title;
    }
    return adfText(node.content);
  }
  return '';
}

/** Block-level node. */
function adfBlock(node, indent) {
  if (node == null) return '';
  const i = indent || 0;

  switch (node.type) {
    case 'heading': {
      const level = Math.min(6, Math.max(1, (node.attrs && node.attrs.level) || 1));
      return '\n\n' + '#'.repeat(level) + ' ' + adfText(node.content).trim() + '\n\n';
    }
    case 'paragraph':
      return '\n\n' + adfText(node.content).trim() + '\n\n';
    case 'bulletList':
      return (node.content || []).map((li) => adfBlock(li, i + 1)).join('');
    case 'orderedList': {
      const start = (node.attrs && node.attrs.order) || 1;
      return (node.content || [])
        .map((li, idx) => adfListItem(li, i + 1, String(start + idx) + '.'))
        .join('');
    }
    case 'listItem':
      return adfListItem(node, i, '-');
    case 'codeBlock': {
      const lang = node.attrs && node.attrs.language ? node.attrs.language : '';
      const code = adfText(node.content);
      return '\n\n```' + lang + '\n' + code + '\n```\n\n';
    }
    case 'blockquote':
      return (
        '\n\n' +
        (node.content || [])
          .map((c) =>
            String(adfBlock(c, i + 1).trim())
              .split('\n')
              .map((l) => '> ' + l)
              .join('\n')
          )
          .join('\n\n') +
        '\n\n'
      );
    case 'table': {
      const rows = node.content || [];
      const mdRows = rows
        .filter((r) => r.type === 'tableRow')
        .map((r) => {
          const cells = (r.content || [])
            .filter((c) => c.type === 'tableHeader' || c.type === 'tableCell')
            .map((c) => adfText(c.content).trim().replace(/\|/g, '\\|'));
          return cells;
        })
        .filter((r) => r.length > 0);
      if (mdRows.length === 0) return '\n\n';
      const width = Math.max(...mdRows.map((r) => r.length));
      const pad = (r) => {
        const row = r.slice();
        while (row.length < width) row.push('');
        return row;
      };
      const header = pad(mdRows[0]);
      let out = '\n\n| ' + header.join(' | ') + ' |\n';
      out += '| ' + Array(width).fill('---').join(' | ') + ' |\n';
      for (const row of mdRows.slice(1)) {
        out += '| ' + pad(row).join(' | ') + ' |\n';
      }
      return out + '\n\n';
    }
    case 'rule':
      return '\n\n---\n\n';
    case 'hardBreak':
      return '\n';
    case 'mediaSingle':
    case 'mediaGroup':
      return (node.content || []).map((c) => adfBlock(c, i)).join('\n');
    case 'media': {
      const href = node.attrs && (node.attrs.url || node.attrs.href);
      const alt = node.attrs && node.attrs.altName ? node.attrs.altName : 'image';
      if (href) return '\n\n![image](' + href + ')\n\n';
      return '\n\n_' + alt + '_\n\n';
    }
    case 'panel': {
      const panelType = node.attrs && node.attrs.panelType ? node.attrs.panelType : '';
      const label = (panelType || 'PANEL').toUpperCase();
      const body = (node.content || []).map((c) => adfBlock(c, i + 1).trim()).join('\n\n');
      return '\n\n[' + label + ']\n' + body + '\n[/' + label + ']\n\n';
    }
    case 'expand': {
      const title = node.attrs && node.attrs.title ? node.attrs.title : 'expand';
      const body = (node.content || []).map((c) => adfBlock(c, i + 1).trim()).join('\n\n');
      return '\n\n[EXPAND title="' + title + '"]\n' + body + '\n[/EXPAND]\n\n';
    }
    case 'tableRow':
    case 'tableHeader':
    case 'tableCell':
    case 'listItemText':
      return adfText(node.content);
    default: {
      // unknown node with content: descend
      if (node.content && node.content.length > 0) {
        return (node.content || []).map((c) => adfBlock(c, i)).join('');
      }
      return '';
    }
  }
}

function adfListItem(node, indent, marker) {
  const content = node.content || [];
  const text = content
    .filter((c) => c.type !== 'bulletList' && c.type !== 'orderedList')
    .map((c) => adfBlock(c, indent).trim())
    .join(' ');
  const nested = content
    .filter((c) => c.type === 'bulletList' || c.type === 'orderedList')
    .map((c) =>
      adfBlock(c, indent + 1)
        .trim()
        .split('\n')
        .map((l) => '  ' + l)
        .join('\n')
    )
    .join('\n\n');
  return '  '.repeat(indent - 1) + marker + ' ' + text + (nested ? '\n' + nested : '') + '\n';
}

/** Convert an ADF document (object or JSON string) to Markdown. */
function adfToMarkdown(adfJson) {
  let doc;
  try {
    doc = typeof adfJson === 'string' ? JSON.parse(adfJson) : adfJson;
  } catch (err) {
    fail(3, 'invalid ADF JSON from API');
  }
  if (!doc || !Array.isArray(doc.content)) return '';
  return doc.content.map((c) => adfBlock(c, 0)).join('').replace(/\n{4,}/g, '\n\n\n').trim();
}

module.exports = { adfToMarkdown, adfText, adfBlock };