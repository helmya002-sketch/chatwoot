// Tolzar: one lifecycle palette for every surface (Contacts first; Pipeline, Dashboard and the
// conversation chips still carry their own copies and move here next). Theme scales only, so
// light/dark follow the app theme. Keys are the stored `lifecycle_stage` values.
export const STAGES = [
  { key: 'New Lead', label: 'New Lead', tone: 'slate' },
  { key: 'Active', label: 'Active', tone: 'amber' },
  { key: 'Offer Sent Follow up', label: 'Offer Sent', tone: 'iris' },
  { key: 'Customer Won', label: 'Won', tone: 'teal' },
  { key: 'Customer Lost', label: 'Lost', tone: 'ruby' },
];

export const DEFAULT_STAGE = 'New Lead';

// Static class strings so Tailwind keeps them in the build.
const TONE_CLASSES = {
  slate: 'bg-n-slate-3 text-n-slate-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
};

export const stageOf = key =>
  STAGES.find(s => s.key === key) ||
  (key ? { key, label: key, tone: 'slate' } : STAGES[0]);

export const stageClass = key => TONE_CLASSES[stageOf(key).tone];

// Lead score 0–100 from the brain (`tolzar_lead_score`); null when the brain hasn't scored yet.
export const leadScore = attrs => {
  const n = Number(attrs?.tolzar_lead_score);
  return Number.isFinite(n) && attrs?.tolzar_lead_score !== ''
    ? Math.round(n)
    : null;
};

export const scoreTone = n => {
  if (n === null) return 'text-n-slate-10';
  if (n >= 75) return 'text-n-ruby-11';
  if (n >= 50) return 'text-n-amber-11';
  return 'text-n-slate-11';
};

export const scoreBar = n => {
  if (n >= 75) return 'bg-n-ruby-9';
  if (n >= 50) return 'bg-n-amber-9';
  return 'bg-n-slate-9';
};
