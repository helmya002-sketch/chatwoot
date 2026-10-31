/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- t() here is our own widget i18n, not vue-i18n */
// Tolzar widget: an AI or bot reply's sources (content_attributes.tolzar_sources: [{title, url}]) as safe links
// under the reply, and the page the visitor writes from as conversation attributes (tolzar_page, without query
// string or fragment, so no tracking parameter or personal data in a URL is kept).
import { safeHref } from './format';
import { t } from './i18n';

export const MAX_SOURCES = 3;

export function sourcesNode(doc, attrs, locale) {
  const list = Array.isArray(attrs?.tolzar_sources) ? attrs.tolzar_sources : [];
  const items = list
    .map(s => ({
      title: String(s?.title || '')
        .trim()
        .slice(0, 80),
      href: safeHref(String(s?.url || '')),
    }))
    .filter(s => s.title)
    .slice(0, MAX_SOURCES);
  if (!items.length) return null;
  const box = doc.createElement('div');
  box.className = 'tz-sources';
  box.append(doc.createTextNode(`${t(locale, 'SOURCES')} `));
  items.forEach((s, i) => {
    if (i) box.append(doc.createTextNode(' · '));
    if (s.href) {
      const a = doc.createElement('a');
      a.href = s.href;
      a.textContent = s.title;
      a.target = '_blank';
      a.rel = 'noopener noreferrer nofollow';
      box.append(a);
    } else {
      box.append(doc.createTextNode(s.title));
    }
  });
  return box;
}

export function pageContext(pageUrl) {
  if (!pageUrl) return null;
  try {
    const url = new URL(pageUrl);
    if (!['http:', 'https:'].includes(url.protocol)) return null;
    return { tolzar_page: `${url.origin}${url.pathname}`.slice(0, 300) };
  } catch {
    return null;
  }
}
