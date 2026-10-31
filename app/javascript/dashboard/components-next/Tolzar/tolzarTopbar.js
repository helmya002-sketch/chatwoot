// Tolzar top bar (round 4, c62): the briefing's "right now" counts as chips and the AI state as a pill. Pure and
// unit-tested; the server decides every number (Tolzar::Briefing), this only orders, hides zeros and links.

export const CHIP_ORDER = [
  'mine',
  'waiting',
  'unassigned',
  'due_today',
  'bookings_today',
];

// Where each chip opens. The inbox reads ?tab= and ?status= (ChatList.vue, tzQuickView).
export function chipRoute(key, accountId) {
  const base = `/app/accounts/${accountId}`;
  switch (key) {
    case 'mine':
      return `${base}/dashboard?tab=me&status=open`;
    case 'waiting':
      return `${base}/unattended/conversations`;
    case 'unassigned':
      return `${base}/dashboard?tab=unassigned&status=open`;
    case 'due_today':
      return `${base}/dashboard?tab=all&status=snoozed`;
    case 'bookings_today':
      return `${base}/tolzar-settings?section=bookings`;
    default:
      return null;
  }
}

// Chips with a count above zero, in a fixed order; nothing when the workspace has the top bar off.
export function nowChips(now, accountId) {
  if (!now || typeof now !== 'object') return [];
  return CHIP_ORDER.filter(k => Number(now[k]) > 0).map(k => ({
    key: k,
    n: Number(now[k]),
    to: chipRoute(k, accountId),
  }));
}

// The AI pill: view-only, never a switch.
const PILLS = {
  off: { key: 'OFF', tone: 'muted' },
  shadow: { key: 'SHADOW', tone: 'shadow' },
  live: { key: 'LIVE', tone: 'live' },
  unknown: { key: 'UNKNOWN', tone: 'warn' },
};
export function aiPill(state) {
  if (state === undefined || state === null) return null;
  return PILLS[state] || PILLS.unknown;
}

// The inbox's quick view from the URL: only known values pass.
const TABS = ['me', 'unassigned', 'all'];
const STATUSES = ['open', 'resolved', 'pending', 'snoozed', 'all'];
export function tzQuickView(query) {
  const q = query || {};
  return {
    tab: TABS.includes(q.tab) ? q.tab : null,
    status: STATUSES.includes(q.status) ? q.status : null,
  };
}
