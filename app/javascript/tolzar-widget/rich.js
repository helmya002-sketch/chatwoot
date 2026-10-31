/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- t() here is our own widget i18n, not vue-i18n */
// Tolzar widget: rich replies from the team or a bot, on the app's message types.
//   input_select  content_attributes.items [{title, value}]: option buttons (also booking slots: one per time)
//   cards         items [{title, description, media_url, actions: [{type: link|postback, text, uri|payload}]}]
//   form          items [{name, label, type, placeholder, required}]
// An answered message (submitted_values) shows the answer instead of the controls. Everything is built as DOM;
// links are http/https only; images come only from http/https URLs.
import { safeHref } from './format';
import { t } from './i18n';

const el = (doc, tag, cls, text) => {
  const node = doc.createElement(tag);
  if (cls) node.className = cls;
  if (text != null) node.textContent = text;
  return node;
};

export const RICH_TYPES = ['input_select', 'cards', 'form'];

const items = m =>
  Array.isArray(m.content_attributes?.items)
    ? m.content_attributes.items.slice(0, 20)
    : [];
const answered = m => {
  const v = m.content_attributes?.submitted_values;
  return Array.isArray(v) ? v : null;
};

function options(app, m) {
  const { doc } = app;
  const done = answered(m);
  if (done)
    return el(
      doc,
      'div',
      'tz-answer',
      done.map(v => v.title || v.value).join(', ')
    );
  const row = el(doc, 'div', 'tz-options');
  row.setAttribute('role', 'group');
  items(m).forEach(item => {
    const b = el(
      doc,
      'button',
      'tz-option',
      String(item.title || item.value || '').slice(0, 80)
    );
    b.type = 'button';
    b.addEventListener('click', () =>
      app.choose(m, {
        title: String(item.title || ''),
        value: String(item.value ?? item.title ?? ''),
      })
    );
    row.append(b);
  });
  return row;
}

function cards(app, m) {
  const { doc } = app;
  const list = el(doc, 'div', 'tz-cards');
  items(m).forEach(card => {
    const box = el(doc, 'article', 'tz-card');
    const img = safeHref(String(card.media_url || ''));
    if (img && /^https?:/.test(img)) {
      const i = el(doc, 'img');
      i.src = img;
      i.alt = String(card.title || '');
      i.loading = 'lazy';
      box.append(i);
    }
    if (card.title)
      box.append(
        el(doc, 'h3', 'tz-card-title', String(card.title).slice(0, 120))
      );
    if (card.description)
      box.append(
        el(doc, 'p', 'tz-card-text', String(card.description).slice(0, 400))
      );
    (Array.isArray(card.actions) ? card.actions.slice(0, 3) : []).forEach(a => {
      if (a.type === 'link') {
        const href = safeHref(String(a.uri || ''));
        if (!href) return;
        const link = el(
          doc,
          'a',
          'tz-card-action',
          String(a.text || href).slice(0, 60)
        );
        link.href = href;
        link.target = '_blank';
        link.rel = 'noopener noreferrer nofollow';
        box.append(link);
      } else {
        const b = el(
          doc,
          'button',
          'tz-card-action',
          String(a.text || '').slice(0, 60)
        );
        b.type = 'button';
        b.addEventListener('click', () =>
          app.choose(m, {
            title: String(a.text || ''),
            value: String(a.payload ?? a.text ?? ''),
          })
        );
        box.append(b);
      }
    });
    list.append(box);
  });
  return list;
}

function form(app, m) {
  const { doc, locale } = app;
  const done = answered(m);
  if (done) return el(doc, 'div', 'tz-answer', t(locale, 'FORM_SENT'));
  const f = el(doc, 'form', 'tz-form');
  f.noValidate = true;
  const inputs = {};
  items(m).forEach((field, i) => {
    const id = `tz-f-${m.id}-${i}`;
    const label = el(
      doc,
      'label',
      'tz-label',
      `${field.label || field.name}${field.required ? ' *' : ''}`
    );
    label.htmlFor = id;
    const input =
      field.type === 'text_area'
        ? el(doc, 'textarea', 'tz-input')
        : el(doc, 'input', 'tz-input');
    input.id = id;
    if (input.tagName === 'INPUT')
      input.type = ['email', 'number', 'tel'].includes(field.type)
        ? field.type
        : 'text';
    input.placeholder = String(field.placeholder || '');
    input.required = !!field.required;
    inputs[field.name] = { input, field };
    f.append(label, input);
  });
  const err = el(doc, 'div', 'tz-field-error');
  err.setAttribute('role', 'alert');
  const submit = el(doc, 'button', 'tz-send', t(locale, 'FORM_SEND'));
  submit.type = 'submit';
  f.append(err, submit);
  f.addEventListener('submit', e => {
    e.preventDefault();
    const missing = Object.values(inputs).find(
      ({ input, field }) => field.required && !input.value.trim()
    );
    if (missing) {
      err.textContent = t(locale, 'ERR_REQUIRED');
      missing.input.focus();
      return;
    }
    const values = Object.values(inputs).map(({ input, field }) => ({
      name: String(field.name),
      value: input.value.trim().slice(0, 1000),
    }));
    app.submitForm(m, values);
  });
  return f;
}

export function richNode(app, m) {
  if (m.contentType === 'input_select') return options(app, m);
  if (m.contentType === 'cards') return cards(app, m);
  if (m.contentType === 'form') return form(app, m);
  return null;
}
