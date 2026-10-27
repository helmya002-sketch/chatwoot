// Tolzar Reports: data + formatting helpers (kept out of the component so they're testable).
// Everything reads live Chatwoot data or the brain's scoreboard; nothing is estimated.
import ContactAPI from 'dashboard/api/contacts';
import { STAGES } from 'dashboard/components-next/Tolzar/tolzarStages';

const DAY = 86400;

export const rangeFor = (days, now = Date.now()) => {
  const until = Math.floor(now / 1000);
  return {
    since: until - days * DAY,
    until,
    prevSince: until - 2 * days * DAY,
  };
};

export const isoDate = unix => new Date(unix * 1000).toISOString().slice(0, 10);

// 3001 s -> "50 min"; 31697 s -> "8 h 48 min"; 2 days -> "2 d 0 h"
export const duration = seconds => {
  if (
    seconds === null ||
    seconds === undefined ||
    Number.isNaN(Number(seconds))
  )
    return '—';
  const s = Math.round(Number(seconds));
  if (s < 60) return `${s} s`;
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h} h ${m % 60} min`;
  return `${Math.floor(h / 24)} d ${h % 24} h`;
};

export const pct = (v, digits = 0) =>
  v === null || v === undefined ? '—' : `${(v * 100).toFixed(digits)}%`;

export const euro = v =>
  `€${v >= 10000 ? `${(v / 1000).toFixed(1)}k` : Math.round(v).toLocaleString()}`;

// Relative change, or null when there is nothing to compare with.
export const delta = (now, prev) => {
  if (!prev) return null;
  return (now - prev) / prev;
};

const stageFilter = stage => ({
  payload: [
    {
      attribute_key: 'lifecycle_stage',
      filter_operator: 'equal_to',
      values: [stage],
      query_operator: null,
      custom_attribute_type: 'contact_attribute',
    },
  ],
});

const createdBetween = (fromDate, toDate) => ({
  payload: [
    {
      attribute_key: 'created_at',
      filter_operator: 'is_greater_than',
      values: [fromDate],
      query_operator: toDate ? 'and' : null,
      attribute_model: 'standard',
    },
    ...(toDate
      ? [
          {
            attribute_key: 'created_at',
            filter_operator: 'is_less_than',
            values: [toDate],
            query_operator: null,
            attribute_model: 'standard',
          },
        ]
      : []),
  ],
});

const countOf = async query => {
  const { data } = await ContactAPI.filter(1, 'name', query);
  return data?.meta?.count || 0;
};

// Contacts with no stage yet count as New Lead, as everywhere else in the app.
export const stageCounts = async () => {
  const [entries, all] = await Promise.all([
    Promise.all(
      STAGES.map(async s => [s.key, await countOf(stageFilter(s.key))])
    ),
    ContactAPI.get(1).then(({ data }) => data?.meta?.count || 0),
  ]);
  const out = Object.fromEntries(entries);
  const staged = STAGES.filter(s => s.key !== 'New Lead').reduce(
    (sum, s) => sum + (out[s.key] || 0),
    0
  );
  out['New Lead'] = Math.max(out['New Lead'] || 0, all - staged);
  return out;
};

export const newContacts = (sinceUnix, untilUnix) =>
  countOf(
    createdBetween(isoDate(sinceUnix), untilUnix ? isoDate(untilUnix) : null)
  );

export const weeklyNewContacts = async (weeks = 5, now = Date.now()) => {
  const end = Math.floor(now / 1000);
  const spans = [...Array(weeks)].map((_, i) => {
    const to = end - (weeks - 1 - i) * 7 * DAY;
    return { from: to - 7 * DAY, to };
  });
  return Promise.all(
    spans.map(async w => ({
      week: isoDate(w.from),
      count: await countOf(
        createdBetween(isoDate(w.from), w.to >= end ? null : isoDate(w.to))
      ),
    }))
  );
};

// Sum of booking_value_eur for contacts in a stage (pages of 15; capped).
export const stageValue = async (stage, maxPages = 10) => {
  let total = 0;
  let count = 0;
  let page = 1;
  let capped = false;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    // eslint-disable-next-line no-await-in-loop
    const { data } = await ContactAPI.filter(page, 'name', stageFilter(stage));
    const rows = data?.payload || [];
    total += rows.reduce((sum, c) => {
      const v = Number(c.custom_attributes?.booking_value_eur);
      return Number.isFinite(v) ? sum + v : sum;
    }, 0);
    count = data?.meta?.count || 0;
    if (page * 15 >= count || !rows.length) break;
    if (page >= maxPages) {
      capped = true;
      break;
    }
    page += 1;
  }
  return { stage, total, count, capped };
};
