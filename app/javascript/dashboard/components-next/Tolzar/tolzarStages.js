import { reactive } from 'vue';

// Tolzar: one lifecycle palette for every surface (Contacts first; Pipeline, Dashboard and the
// conversation chips still carry their own copies and move here next). Theme scales only, so
// light/dark follow the app theme. Keys are the stored `lifecycle_stage` values.
// The brain has no pipeline-stage endpoint yet, so these are the defaults. A workspace can
// override the list with the account setting `pipeline_stages` (account.settings, set by an
// admin; shown read-only here): ["New Lead", "Qualified", ...] or
// [{ key, label, tone }, ...]. Bad entries are skipped; an empty or invalid list keeps the defaults.
export const DEFAULT_STAGES = Object.freeze([
  { key: 'New Lead', label: 'New Lead', tone: 'slate' },
  { key: 'Active', label: 'Active', tone: 'amber' },
  { key: 'Offer Sent Follow up', label: 'Offer Sent', tone: 'iris' },
  { key: 'Customer Won', label: 'Won', tone: 'teal' },
  { key: 'Customer Lost', label: 'Lost', tone: 'ruby' },
]);

// Reactive and replaced in place, so every importer follows the workspace setting.
export const STAGES = reactive(DEFAULT_STAGES.map(s => ({ ...s })));

const MAX_STAGES = 12;
const TONES = ['slate', 'amber', 'iris', 'teal', 'ruby'];

export const parsePipelineStages = value => {
  if (!Array.isArray(value)) return null;
  const seen = new Set();
  const out = [];
  value.forEach((raw, i) => {
    const item = typeof raw === 'string' ? { key: raw } : raw;
    const key = String(item?.key ?? '')
      .trim()
      .slice(0, 60);
    if (!key || seen.has(key) || out.length >= MAX_STAGES) return;
    seen.add(key);
    const label =
      String(item.label ?? key)
        .trim()
        .slice(0, 40) || key;
    const tone = TONES.includes(item.tone)
      ? item.tone
      : TONES[i % TONES.length];
    out.push({ key, label, tone });
  });
  return out.length ? out : null;
};

// accountSettings: the account's `settings` object (accounts/getAccount(id).settings).
export const applyPipelineStages = accountSettings => {
  const next =
    parsePipelineStages(accountSettings?.pipeline_stages) || DEFAULT_STAGES;
  STAGES.splice(0, STAGES.length, ...next.map(s => ({ ...s })));
  return STAGES;
};

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
  (key ? { key, label: key, tone: 'slate' } : stageOf(DEFAULT_STAGE));

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
