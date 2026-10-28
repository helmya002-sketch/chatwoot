// AI Agents test chat: the brain's POST /agent-test answer, run through the same safety chain
// as a real reply. When `replaced` is true the final reply is what Shadow would send instead
// of the model's draft; `reasons` are the chain's codes (e.g. "negotiation:semantic_offer").

// Readable labels for the common codes (i18n keys); anything else is shown raw.
const REASON_KEYS = {
  'negotiation:semantic_offer': 'SEMANTIC_OFFER',
  'negotiation:check_unavailable': 'CHECK_UNAVAILABLE',
  'output_policy:link': 'LINK',
  'output_policy:commitment': 'COMMITMENT',
};
export const reasonKey = code => {
  const c = String(code || '');
  if (REASON_KEYS[c]) return `TOLZAR_AGENT_TEST.REASON.${REASON_KEYS[c]}`;
  if (c.startsWith('price_guard:')) return 'TOLZAR_AGENT_TEST.REASON.PRICE';
  return null;
};
// Labels for a list of codes, de-duplicated (several price_guard codes read as one line).
export const reasonLabels = (codes, t) => [
  ...new Set(
    (Array.isArray(codes) ? codes : []).map(c => {
      const k = reasonKey(c);
      return k ? t(k) : String(c);
    })
  ),
];

const metaLine = d =>
  d.ok && d.model
    ? `${d.model}${d.latency_ms ? ` · ${Math.round(d.latency_ms / 100) / 10}s` : ''}`
    : '';

// One agent bubble from the answer: the final reply, plus the draft and reasons when replaced.
export const parseAgentTest = data => {
  const d = data || {};
  const replaced = !!(d.ok && d.replaced);
  return {
    who: 'agent',
    text: String(d.reply || ''),
    meta: metaLine(d),
    replaced,
    draft: replaced ? String(d.draft || '') : '',
    reasons: replaced && Array.isArray(d.reasons) ? d.reasons.map(String) : [],
  };
};
