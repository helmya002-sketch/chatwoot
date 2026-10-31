// Tolzar win/loss reasons (round 4, c95): the reasons offered when a deal reaches the won or lost stage, and how they
// are stored on the contact (custom attributes tolzar_outcome_reason "won:price" and tolzar_outcome_reason_at).
export const WON_REASONS = ['price', 'speed', 'recommendation', 'fit', 'other'];
export const LOST_REASONS = [
  'price',
  'timing',
  'competitor',
  'no_reply',
  'not_fit',
  'other',
];

// 'won' | 'lost' | null for a stage key, given the board's won and lost stage keys.
export function outcomeFor(stageKey, wonKey, lostKey) {
  if (stageKey && stageKey === wonKey) return 'won';
  if (stageKey && stageKey === lostKey) return 'lost';
  return null;
}

export function reasonsFor(outcome) {
  if (outcome === 'won') return WON_REASONS;
  if (outcome === 'lost') return LOST_REASONS;
  return [];
}

// The attributes to merge onto the contact's current custom attributes.
export function reasonAttributes(outcome, reason, now = new Date()) {
  if (!reasonsFor(outcome).includes(reason)) return null;
  return {
    tolzar_outcome_reason: `${outcome}:${reason}`,
    tolzar_outcome_reason_at: now.toISOString(),
  };
}
