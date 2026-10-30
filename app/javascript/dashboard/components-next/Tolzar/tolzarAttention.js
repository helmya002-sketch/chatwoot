// Tolzar Dashboard "Needs attention": what an inbox manager opens the page for, from data the
// page already loads (the open conversations list and its meta). Nothing here is estimated.
//   hot        lead score >= HOT_SCORE (the brain's `tolzar_lead_score`, BriefingStrip's rule)
//   waiting    open, no first reply yet (`first_reply_created_at` is 0/absent)
//   unassigned open, nobody assigned
// The brain's SLA counts are not fetched by the Dashboard today, so "waiting" stands in for
// "later than the SLA" until a pooled summary endpoint exists.
export const HOT_SCORE = 70;
export const KINDS = ['hot', 'waiting', 'unassigned'];

const scoreOf = c => {
  const raw = c?.meta?.sender?.custom_attributes?.tolzar_lead_score;
  const n = Number(raw);
  return raw !== '' && raw !== null && raw !== undefined && Number.isFinite(n)
    ? Math.round(n)
    : null;
};

// The reasons one conversation needs a person, in priority order.
export const reasonsFor = c => {
  if (!c || (c.status && c.status !== 'open')) return [];
  const out = [];
  const score = scoreOf(c);
  if (score !== null && score >= HOT_SCORE) out.push('hot');
  if (!c.first_reply_created_at) out.push('waiting');
  if (!c.meta?.assignee) out.push('unassigned');
  return out;
};

// Rows for the list: one per conversation, hot first, then the longest waiting. `limit` rows.
export const attentionRows = (conversations, { limit = 8 } = {}) => {
  const rows = (conversations || [])
    .map(c => {
      const reasons = reasonsFor(c);
      if (!reasons.length) return null;
      const since = c.waiting_since || c.created_at || 0;
      return {
        id: c.id,
        name: c.meta?.sender?.name || '',
        reasons,
        score: scoreOf(c),
        since,
        inbox: c.inbox_id,
        assignee: c.meta?.assignee?.name || '',
      };
    })
    .filter(Boolean);
  const rank = r => KINDS.indexOf(r.reasons[0]);
  rows.sort((a, b) => {
    const byKind = rank(a) - rank(b);
    if (byKind) return byKind;
    if (a.reasons[0] === 'hot' && a.score !== b.score)
      return (b.score || 0) - (a.score || 0);
    return (a.since || 0) - (b.since || 0);
  });
  return rows.slice(0, limit);
};

// How many conversations carry each reason (a conversation can count in several).
export const attentionCounts = conversations => {
  const counts = { hot: 0, waiting: 0, unassigned: 0 };
  (conversations || []).forEach(c => {
    reasonsFor(c).forEach(k => {
      counts[k] += 1;
    });
  });
  return counts;
};
