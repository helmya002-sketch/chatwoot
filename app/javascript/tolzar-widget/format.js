// Tolzar widget: message text -> DOM nodes, never HTML. Text from the network is only ever placed with
// textContent; the few formats we support are built as elements here: links (http/https/mailto only), *bold*,
// _italics_ and line breaks. Bidi override characters are dropped so a message cannot reorder the page.

const BIDI_OVERRIDES = /[‪-‮⁦-⁩]/g;
const URL_RE = /\b(https?:\/\/[^\s<>"']+|mailto:[^\s<>"']+)/gi;
const TRAILING = /[).,!?;:'"]+$/;

export function cleanText(text) {
  return String(text ?? '').replace(BIDI_OVERRIDES, '');
}

export function safeHref(raw) {
  try {
    const url = new URL(raw);
    return ['http:', 'https:', 'mailto:'].includes(url.protocol)
      ? url.href
      : null;
  } catch {
    return null;
  }
}

// *bold* and _italics_ inside one line, as nodes.
function inline(doc, text) {
  const out = [];
  const re = /(\*[^*\n]{1,200}\*|_[^_\n]{1,200}_)/g;
  let last = 0;
  let m = re.exec(text);
  while (m) {
    if (m.index > last) out.push(doc.createTextNode(text.slice(last, m.index)));
    const el = doc.createElement(m[0][0] === '*' ? 'strong' : 'em');
    el.textContent = m[0].slice(1, -1);
    out.push(el);
    last = m.index + m[0].length;
    m = re.exec(text);
  }
  if (last < text.length) out.push(doc.createTextNode(text.slice(last)));
  return out;
}

function linkify(doc, line) {
  const out = [];
  let last = 0;
  line.replace(URL_RE, (match, _g, offset) => {
    const trail = (match.match(TRAILING) || [''])[0];
    const raw = trail ? match.slice(0, -trail.length) : match;
    const href = safeHref(raw);
    if (!href) return match;
    out.push(...inline(doc, line.slice(last, offset)));
    const a = doc.createElement('a');
    a.href = href;
    a.textContent = raw;
    a.target = '_blank';
    a.rel = 'noopener noreferrer nofollow';
    out.push(a);
    last = offset + raw.length;
    return match;
  });
  out.push(...inline(doc, line.slice(last)));
  return out;
}

// A DocumentFragment for the message text.
export function formatMessage(text, doc = document) {
  const frag = doc.createDocumentFragment();
  cleanText(text)
    .split('\n')
    .forEach((line, i) => {
      if (i > 0) frag.appendChild(doc.createElement('br'));
      linkify(doc, line).forEach(node => frag.appendChild(node));
    });
  return frag;
}
