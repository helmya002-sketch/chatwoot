/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- t() here is our own widget i18n, not vue-i18n */
// Tolzar widget: "continue on WhatsApp / Instagram / Telegram" (channel.handoff: [{channel, url}] from
// Tolzar::WidgetHandoff). Deep links to wa.me / ig.me / t.me only; anything else is dropped.
import { t } from './i18n';

const HOSTS = { whatsapp: 'wa.me', instagram: 'ig.me', telegram: 't.me' };

export function handoffLinks(list) {
  return (Array.isArray(list) ? list : []).filter(l => {
    try {
      const u = new URL(String(l?.url || ''));
      return u.protocol === 'https:' && HOSTS[l.channel] === u.hostname;
    } catch {
      return false;
    }
  });
}

export function handoffNode(doc, list, locale) {
  const links = handoffLinks(list);
  if (!links.length) return null;
  const box = doc.createElement('nav');
  box.className = 'tz-handoff';
  box.setAttribute('aria-label', t(locale, 'CONTINUE_ON'));
  box.append(doc.createTextNode(`${t(locale, 'CONTINUE_ON')} `));
  links.forEach(l => {
    const a = doc.createElement('a');
    a.href = l.url;
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    a.className = `tz-handoff-${l.channel}`;
    a.textContent = t(locale, `CH_${l.channel.toUpperCase()}`);
    box.append(a);
  });
  return box;
}
