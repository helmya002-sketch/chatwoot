// Tolzar UI phase 3 dashboard helpers (pure, unit-tested): the first-reply series and the live table's status pill.

const DAY = 86400;

// The report API's points ([{ value, timestamp }], value in seconds) as one bar per day for the last `days` days,
// oldest first; a missing day is a gap (null), never a zero that would read as "instant".
export function firstReplySeries(points, days = 14, now = Date.now() / 1000) {
  const end = Math.floor(now / DAY) * DAY;
  const byDay = new Map(
    (points || []).map(p => [
      Math.floor(Number(p.timestamp) / DAY) * DAY,
      Number(p.value),
    ])
  );
  return Array.from({ length: days }, (_, i) => {
    const day = end - (days - 1 - i) * DAY;
    const v = byDay.get(day);
    return {
      day,
      minutes: Number.isFinite(v) && v > 0 ? Math.round(v / 6) / 10 : null,
    };
  });
}

export function niceMax(values) {
  const max = Math.max(0, ...values.filter(v => v != null));
  if (max <= 0) return 1;
  const step = 10 ** Math.floor(Math.log10(max));
  return Math.ceil(max / step) * step;
}

// The live table's pill for one open conversation: assigned to a person, to a team, or waiting.
export function liveStatus(conversation) {
  const meta = conversation?.meta || {};
  if (meta.assignee?.name) return { key: 'assigned', who: meta.assignee.name };
  if (meta.team?.name) return { key: 'team', who: meta.team.name };
  return { key: 'waiting', who: '' };
}
