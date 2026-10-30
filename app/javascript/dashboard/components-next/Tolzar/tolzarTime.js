// One place for every timestamp Tolzar shows. The brain returns ISO strings in UTC; the viewer
// reads them in their own zone and language, so nothing here slices the ISO string by hand.

const safeDate = iso => {
  if (!iso) return null;
  const d = iso instanceof Date ? iso : new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
};

const cache = new Map();
const formatter = (locale, opts) => {
  const key = `${locale}|${JSON.stringify(opts)}`;
  if (!cache.has(key)) {
    let f;
    try {
      f = new Intl.DateTimeFormat(locale || undefined, opts);
    } catch {
      f = new Intl.DateTimeFormat('en', opts);
    }
    cache.set(key, f);
  }
  return cache.get(key);
};

// "30 Oct 2026, 14:05" in the viewer's zone and language. Replaces `iso.slice(0, 16)`.
export const fmtAt = (iso, locale = 'en') => {
  const d = safeDate(iso);
  if (!d) return '';
  return formatter(locale, { dateStyle: 'medium', timeStyle: 'short' }).format(d);
};

// "30 Oct" for chart axes and week labels.
export const fmtDay = (iso, locale = 'en') => {
  const d = safeDate(iso);
  if (!d) return '';
  return formatter(locale, { month: 'short', day: 'numeric' }).format(d);
};

// "14:05" when the date is obvious from context.
export const fmtClock = (iso, locale = 'en') => {
  const d = safeDate(iso);
  if (!d) return '';
  return formatter(locale, { timeStyle: 'short' }).format(d);
};

const UNITS = [
  ['year', 365 * 86400],
  ['month', 30 * 86400],
  ['week', 7 * 86400],
  ['day', 86400],
  ['hour', 3600],
  ['minute', 60],
];

// "3 minutes ago", "in 2 days", localised by Intl; `now` is injectable for tests.
export const ago = (iso, locale = 'en', now = Date.now()) => {
  const d = safeDate(iso);
  if (!d) return '';
  const diff = Math.round((d.getTime() - now) / 1000);
  let rtf;
  try {
    rtf = new Intl.RelativeTimeFormat(locale || undefined, { numeric: 'auto' });
  } catch {
    rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });
  }
  const abs = Math.abs(diff);
  if (abs < 45) return rtf.format(0, 'second');
  const [unit, size] = UNITS.find(([, s]) => abs >= s) || ['minute', 60];
  return rtf.format(Math.round(diff / size), unit);
};

// Durations in seconds as "4 min", "1 h 20 min", "2 d": Intl units, no English literals.
export const duration = (seconds, locale = 'en') => {
  const s = Number(seconds);
  if (!Number.isFinite(s) || s < 0) return '';
  const nf = (n, unit) => {
    try {
      return new Intl.NumberFormat(locale || undefined, {
        style: 'unit',
        unit,
        unitDisplay: 'short',
        maximumFractionDigits: 0,
      }).format(n);
    } catch {
      return `${Math.round(n)} ${unit}`;
    }
  };
  if (s < 60) return nf(s, 'second');
  if (s < 3600) return nf(s / 60, 'minute');
  if (s < 86400) {
    const h = Math.floor(s / 3600);
    const m = Math.round((s % 3600) / 60);
    return m ? `${nf(h, 'hour')} ${nf(m, 'minute')}` : nf(h, 'hour');
  }
  return nf(s / 86400, 'day');
};
