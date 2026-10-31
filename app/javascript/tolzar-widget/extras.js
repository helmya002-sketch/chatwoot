/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- t() here is our own widget i18n, not vue-i18n */
// Tolzar widget: the pre-chat form, the away notice and attachments (sent and received), as DOM built here.
import { fields, needed, validate, toRequest } from './prechat';
import { isOpen } from './hours';
import { safeHref } from './format';
import { t } from './i18n';

const el = (doc, tag, cls, text) => {
  const node = doc.createElement(tag);
  if (cls) node.className = cls;
  if (text != null) node.textContent = text;
  return node;
};

export const MAX_FILE_MB_DEFAULT = 40;
const IMAGE_TYPES = ['image'];

// --- away notice ------------------------------------------------------------------------------------------
export function awayNode(app, now = new Date()) {
  const ch = app.channel;
  const open = isOpen(
    {
      enabled: ch.workingHoursEnabled,
      hours: ch.workingHours,
      timeZone: ch.timezone,
    },
    now
  );
  if (open) return null;
  const node = el(
    app.doc,
    'div',
    'tz-away',
    ch.outOfOfficeMessage || t(app.locale, 'AWAY')
  );
  node.setAttribute('role', 'status');
  return node;
}

// --- attachments --------------------------------------------------------------------------------------------
export function attachmentNodes(doc, attachments, locale) {
  return (attachments || []).flatMap(a => {
    const href = safeHref(a.data_url || '');
    if (!href) return [];
    if (IMAGE_TYPES.includes(a.file_type)) {
      const link = el(doc, 'a', 'tz-image');
      link.href = href;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      const img = el(doc, 'img');
      img.src = safeHref(a.thumb_url || '') || href;
      img.alt = t(locale, 'IMAGE');
      img.loading = 'lazy';
      link.append(img);
      return [link];
    }
    const link = el(
      doc,
      'a',
      'tz-file',
      decodeURIComponent(href.split('/').pop().split('?')[0]) ||
        t(locale, 'FILE')
    );
    link.href = href;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    return [link];
  });
}

export function attachButton(app) {
  const { doc } = app;
  const wrap = el(doc, 'label', 'tz-attach');
  wrap.title = t(app.locale, 'ATTACH');
  const input = el(doc, 'input');
  input.type = 'file';
  input.className = 'tz-file-input';
  input.setAttribute('aria-label', t(app.locale, 'ATTACH'));
  input.addEventListener('change', () => {
    const file = input.files && input.files[0];
    input.value = '';
    if (file) app.sendFile(file);
  });
  wrap.append(el(doc, 'span', 'tz-attach-icon', '+'), input);
  return wrap;
}

export function fileTooBig(file, maxMb) {
  return file.size > (Number(maxMb) || MAX_FILE_MB_DEFAULT) * 1024 * 1024;
}

// --- pre-chat form ------------------------------------------------------------------------------------------
export function prechatNeeded(app) {
  return needed({
    enabled: app.channel.preChatFormEnabled,
    options: app.channel.preChatFormOptions,
    hasMessages: app.store.messages.some(m => m.type === 0),
  });
}

export function renderPrechat(app) {
  const { doc } = app;
  const list = fields(app.channel.preChatFormOptions);
  const form = el(doc, 'form', 'tz-prechat');
  form.noValidate = true;
  const intro = app.channel.preChatFormOptions?.pre_chat_message;
  if (intro) form.append(el(doc, 'p', 'tz-prechat-intro', intro));
  const inputs = {};
  const errs = {};
  const add = (name, labelText, type, required) => {
    const id = `tz-pc-${name}`;
    const label = el(
      doc,
      'label',
      'tz-label',
      `${labelText}${required ? ' *' : ''}`
    );
    label.htmlFor = id;
    const input =
      type === 'textarea'
        ? el(doc, 'textarea', 'tz-input')
        : el(doc, 'input', 'tz-input');
    input.id = id;
    if (type !== 'textarea')
      input.type = type === 'checkbox' ? 'checkbox' : type || 'text';
    if (required) input.required = true;
    const err = el(doc, 'div', 'tz-field-error');
    err.id = `${id}-err`;
    input.setAttribute('aria-describedby', err.id);
    inputs[name] = input;
    errs[name] = err;
    form.append(label, input, err);
  };
  list.forEach(f => add(f.name, f.label || f.name, f.type, f.required));
  add('message', t(app.locale, 'MESSAGE'), 'textarea', true);
  const submit = el(doc, 'button', 'tz-send', t(app.locale, 'START'));
  submit.type = 'submit';
  form.append(submit);
  form.addEventListener('submit', async e => {
    e.preventDefault();
    const values = Object.fromEntries(
      list.map(f => [
        f.name,
        inputs[f.name].type === 'checkbox'
          ? inputs[f.name].checked
          : inputs[f.name].value,
      ])
    );
    const message = inputs.message.value;
    const errors = validate(list, values, message);
    Object.entries(errs).forEach(([name, node]) => {
      node.textContent = errors[name]
        ? t(app.locale, `ERR_${errors[name]}`)
        : '';
      inputs[name].setAttribute(
        'aria-invalid',
        errors[name] ? 'true' : 'false'
      );
    });
    const first = Object.keys(errors)[0];
    if (first) {
      inputs[first].focus();
      return;
    }
    submit.disabled = true;
    try {
      await app.api.startConversation(toRequest(list, values, message));
      app.prechatDone = true;
      form.remove();
      app.composer.hidden = false;
      await app.load();
    } catch {
      app.showError(t(app.locale, 'FAILED'));
      submit.disabled = false;
    }
  });
  return form;
}
