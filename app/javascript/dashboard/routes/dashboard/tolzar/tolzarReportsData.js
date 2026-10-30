// Tolzar Reports: data + formatting helpers (kept out of the component so they're testable).
// Everything reads live Chatwoot data or the brain's scoreboard; nothing is estimated.
import ContactAPI from 'dashboard/api/contacts';
import {
  STAGES,
  stageConditions,
  dealValue,
  money,
} from 'dashboard/components-next/Tolzar/tolzarStages';

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

// In the workspace's deal currency (Settings > Pipeline).
export const euro = v => money(v, { short: true });

// Relative change, or null when there is nothing to compare with.
export const delta = (now, prev) => {
  if (!prev) return null;
  return (now - prev) / prev;
};

// null when the workspace has no stage attribute at all (nothing to count).
const stageFilter = stage => {
  const payload = stageConditions(stage);
  return payload ? { payload } : null;
};

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
  if (!query) return 0;
  const { data } = await ContactAPI.filter(1, 'name', query);
  return data?.meta?.count || 0;
};

// Contacts with no stage yet count in the first (default) stage: stageConditions includes them.
// Contacts in a stage that is not in the workspace's list (e.g. an imported "spam" stage) are counted
// apart under OTHER_STAGES, so no stage looks bigger than it is.
export const OTHER_STAGES = '__other';
export const stageCounts = async () => {
  const [entries, all] = await Promise.all([
    Promise.all(
      STAGES.map(async s => [s.key, await countOf(stageFilter(s.key))])
    ),
    ContactAPI.get(1).then(({ data }) => data?.meta?.count || 0),
  ]);
  const out = Object.fromEntries(entries);
  const listed = STAGES.reduce((sum, s) => sum + (out[s.key] || 0), 0);
  out[OTHER_STAGES] = Math.max(0, all - listed);
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

// Sum of the deal value field for contacts in a stage (pages of 15; capped).
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
      return sum + dealValue(c.custom_attributes);
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

// The brain's /scoreboard, in one safe shape: an older brain or a partial answer may omit any
// block, and the page reads `checks.length`, `guards.price_guard`, `disagreements.length`
// without further guards. `ok` is kept so the page can still say the board is unavailable.
export const EMPTY_SCOREBOARD = Object.freeze({
  ok: false,
  measured: 0,
  scored: 0,
  passing: 0,
  days: 0,
  awaiting_staff: 0,
  model_latest: '',
  models: {},
  checks: [],
  guards: { price_guard: 0, output_policy: {}, llm_errors: 0 },
  disagreements: [],
  daily: [],
  by_model: [],
});
const num = (v, d = 0) => (Number.isFinite(Number(v)) && v !== null && v !== '' ? Number(v) : d);
const list = v => (Array.isArray(v) ? v.filter(Boolean) : []);
export const normalizeScoreboard = raw => {
  const r = raw && typeof raw === 'object' ? raw : {};
  const guards = r.guards && typeof r.guards === 'object' ? r.guards : {};
  return {
    ...r,
    ok: r.ok === true,
    measured: num(r.measured),
    scored: num(r.scored),
    passing: num(r.passing),
    days: num(r.days),
    awaiting_staff: num(r.awaiting_staff),
    model_latest: typeof r.model_latest === 'string' ? r.model_latest : '',
    models: r.models && typeof r.models === 'object' ? r.models : {},
    checks: list(r.checks)
      .filter(c => typeof c.key === 'string' && c.key)
      .map(c => ({
        key: c.key,
        value: c.value === null || c.value === undefined ? null : num(c.value, null),
        target: num(c.target),
        pass: typeof c.pass === 'boolean' ? c.pass : null,
        higher_is_better: c.higher_is_better !== false,
      })),
    guards: {
      price_guard: num(guards.price_guard),
      llm_errors: num(guards.llm_errors),
      output_policy:
        guards.output_policy && typeof guards.output_policy === 'object'
          ? guards.output_policy
          : {},
    },
    disagreements: list(r.disagreements).filter(d => d.conversation_id),
    daily: list(r.daily).filter(d => d.day),
    by_model: list(r.by_model).filter(m => m.model),
  };
};

// ---- CSV (client-side, no dependency) -------------------------------------------------------
// `rows` is an array of arrays; `headers` the first line. Fields with a comma, a quote or a line
// break are quoted; quotes are doubled. UTF-8 BOM so spreadsheets read accents; CRLF lines.
const csvField = v => {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
export const toCsv = (headers, rows) =>
  `\uFEFF${[headers, ...rows].map(r => r.map(csvField).join(',')).join('\r\n')}\r\n`;

// Hands the browser a file to save (a Blob URL on a hidden link). Injectable for tests.
export const downloadCsv = (
  name,
  headers,
  rows,
  { doc = typeof document === 'undefined' ? null : document, win = typeof window === 'undefined' ? null : window } = {}
) => {
  const text = toCsv(headers, rows);
  if (!doc || !win || !win.URL || typeof win.URL.createObjectURL !== 'function') return text;
  const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
  const url = win.URL.createObjectURL(blob);
  const a = doc.createElement('a');
  a.href = url;
  a.download = `${String(name || 'export').replace(/[^\w.-]+/g, '-')}.csv`;
  a.style.display = 'none';
  doc.body.appendChild(a);
  a.click();
  doc.body.removeChild(a);
  win.URL.revokeObjectURL(url);
  return text;
};
