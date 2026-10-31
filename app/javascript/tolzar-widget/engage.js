/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- t() here is our own widget i18n, not vue-i18n */
// Tolzar widget: ongoing campaigns (the inbox's triggered messages), the satisfaction rating (CSAT) and the
// e-mail transcript. Campaign rules: { url, time_on_page } -- the page URL must match (a "*" wildcard is
// allowed) and the visitor must stay time_on_page seconds; one campaign per page, never in a running chat,
// and only during office hours when the campaign asks for it.
import { t } from './i18n';

const el = (doc, tag, cls, text) => {
  const node = doc.createElement(tag);
  if (cls) node.className = cls;
  if (text != null) node.textContent = text;
  return node;
};

export function urlMatches(rule, pageUrl) {
  if (!rule) return false;
  const esc = String(rule)
    .replace(/[.+?^${}()|[\]\\]/g, '\\$&')
    .replace(/\*/g, '.*');
  try {
    return new RegExp(`^${esc}$`, 'i').test(
      String(pageUrl || '').split('#')[0]
    );
  } catch {
    return false;
  }
}

export function pickCampaign(
  campaigns,
  { pageUrl, inOfficeHours, hasMessages }
) {
  if (hasMessages) return null;
  return (
    (campaigns || []).find(
      c =>
        urlMatches(c.trigger_rules?.url, pageUrl) &&
        (!c.trigger_only_during_business_hours || inOfficeHours)
    ) || null
  );
}

// Arms one campaign for this page; returns a cancel function.
export function armCampaign(
  campaign,
  onFire,
  timers = { set: setTimeout, clear: clearTimeout }
) {
  if (!campaign) return () => {};
  const wait =
    Math.max(0, Number(campaign.trigger_rules?.time_on_page || 0)) * 1000;
  const id = timers.set(() => onFire(campaign), wait);
  return () => timers.clear(id);
}

// --- CSAT ---------------------------------------------------------------------------------------------------
export function csatNode(app, message) {
  const { doc, locale } = app;
  const box = el(doc, 'div', 'tz-csat');
  const done =
    message.content_attributes?.submitted_values?.csat_survey_response;
  if (done?.rating) {
    box.append(el(doc, 'div', 'tz-csat-thanks', t(locale, 'CSAT_THANKS')));
    return box;
  }
  box.append(el(doc, 'div', 'tz-csat-q', t(locale, 'CSAT_QUESTION')));
  const row = el(doc, 'div', 'tz-csat-row');
  row.setAttribute('role', 'group');
  row.setAttribute('aria-label', t(locale, 'CSAT_QUESTION'));
  [1, 2, 3, 4, 5].forEach(rating => {
    const b = el(doc, 'button', 'tz-csat-btn', String(rating));
    b.type = 'button';
    b.setAttribute('aria-label', t(locale, `CSAT_${rating}`));
    b.addEventListener('click', () => app.rate(message, rating));
    row.append(b);
  });
  box.append(row);
  return box;
}

// --- transcript ---------------------------------------------------------------------------------------------
export function transcriptNode(app) {
  const { doc, locale } = app;
  const b = el(doc, 'button', 'tz-link', t(locale, 'TRANSCRIPT'));
  b.type = 'button';
  b.addEventListener('click', async () => {
    b.disabled = true;
    try {
      await app.api.transcript();
      b.textContent = t(locale, 'TRANSCRIPT_SENT');
    } catch {
      b.textContent = t(locale, 'TRANSCRIPT_FAILED');
      b.disabled = false;
    }
  });
  return b;
}
