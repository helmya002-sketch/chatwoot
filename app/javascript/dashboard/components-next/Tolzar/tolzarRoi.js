// Tolzar "Results" (ROI) report: what Tolzar is worth, from the brain's /roi (plugins/roi.py).
// In Shadow, Tolzar's reply times and AI share are what customers WOULD have seen: "would-be".
import { brainGet } from './tolzarBrainApi';

export const getRoi = (accountId, days = 30) =>
  brainGet(accountId, 'roi', { days });

// The brain sends working hours as "09:00:00-19:00:00": show "09:00–19:00" in the member's
// locale (24-hour clock, the locale's own digits). Anything unexpected is shown as sent.
export const workingHoursLabel = (hours, locale = 'en') => {
  const m =
    /^\s*(\d{1,2}):(\d{2})(?::\d{2})?\s*-\s*(\d{1,2}):(\d{2})(?::\d{2})?\s*$/.exec(
      String(hours ?? '')
    );
  if (!m) return String(hours ?? '');
  const opts = {
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: 'UTC',
  };
  let fmt;
  try {
    // Chatwoot locales are like "pt_BR"; Intl wants "pt-BR".
    fmt = new Intl.DateTimeFormat(String(locale).replace('_', '-'), opts);
  } catch (e) {
    fmt = new Intl.DateTimeFormat('en', opts);
  }
  const at = (h, min) => fmt.format(new Date(Date.UTC(2000, 0, 1, +h, +min)));
  return `${at(m[1], m[2])}–${at(m[3], m[4])}`;
};

// Stat tiles: key, raw value, kind (seconds | share | count), and whether it is a would-be value.
export const roiTiles = r => {
  if (!r || !r.first_reply) return [];
  const fr = r.first_reply;
  const ai = r.ai_handled || {};
  const oh = r.off_hours || {};
  const wouldBe = !!fr.would_be;
  return [
    {
      key: 'staff_first_reply',
      value: fr.staff_median_s,
      kind: 'seconds',
      wouldBe: false,
      sub: { p90: fr.staff_p90_s, n: fr.compared || 0 },
    },
    {
      key: 'tolzar_first_reply',
      value: fr.tolzar_median_s,
      kind: 'seconds',
      wouldBe,
      sub: { p90: fr.tolzar_p90_s, n: fr.compared || 0 },
    },
    {
      key: 'ai_share',
      value: ai.share,
      kind: 'share',
      wouldBe,
      sub: { n: ai.decisions || 0 },
    },
    {
      key: 'guard_replaced',
      value: ai.guard_replaced || 0,
      kind: 'count',
      wouldBe: false,
      sub: { n: ai.decisions || 0 },
    },
    {
      key: 'off_hours',
      value: oh.share,
      kind: 'share',
      wouldBe: false,
      sub: { n: oh.off_hours || 0, of: oh.leads || 0 },
    },
    {
      key: 'won',
      value: r.won_contacts,
      kind: 'count',
      wouldBe: false,
      sub: {},
    },
  ];
};

// The plain-language summary as i18n facts { key, params }, so it reads in the member's
// language (the brain's own `summary` is English). Same sentences, same order as the brain.
export const roiFacts = r => {
  if (!r || !r.first_reply) return [];
  const out = [];
  const fr = r.first_reply;
  if (fr.compared) {
    out.push({
      key: fr.would_be ? 'FIRST_REPLY_WOULD' : 'FIRST_REPLY',
      params: {
        staff: fr.staff_median_s,
        tolzar: fr.tolzar_median_s,
        n: fr.compared,
      },
    });
  } else {
    out.push({ key: 'NO_FIRST_REPLY', params: {} });
  }
  const ai = r.ai_handled || {};
  if (ai.decisions) {
    out.push({
      key: 'AI_SHARE',
      params: {
        share: Math.round(100 * (ai.share || 0)),
        n: ai.decisions,
        guards: ai.guard_replaced || 0,
      },
    });
  }
  const oh = r.off_hours || {};
  if (oh.leads) {
    out.push({
      key: 'OFF_HOURS',
      params: { n: oh.off_hours || 0, of: oh.leads },
    });
  }
  if ((r.campaigns || []).length) {
    out.push({
      key: 'TOP_CAMPAIGN',
      params: {
        name: r.campaigns[0].campaign,
        n: r.campaigns[0].conversations,
      },
    });
  }
  if (r.won_contacts !== null && r.won_contacts !== undefined) {
    out.push({ key: 'WON', params: { n: r.won_contacts } });
  }
  if (r.mode_note) out.push({ key: 'SHADOW_NOTE', params: {} });
  return out;
};

// The brain's /roi with every block the page reads present (an older brain or a partial answer
// may omit one), so the template never reads `first_reply.would_be` off undefined.
export const roiView = r => {
  const d = r && typeof r === 'object' ? r : {};
  return {
    ...d,
    first_reply: d.first_reply && typeof d.first_reply === 'object' ? d.first_reply : {},
    ai_handled: d.ai_handled && typeof d.ai_handled === 'object' ? d.ai_handled : {},
    off_hours: d.off_hours && typeof d.off_hours === 'object' ? d.off_hours : {},
    won_rule: d.won_rule && typeof d.won_rule === 'object' ? d.won_rule : {},
    campaigns: Array.isArray(d.campaigns) ? d.campaigns.filter(Boolean) : [],
  };
};
