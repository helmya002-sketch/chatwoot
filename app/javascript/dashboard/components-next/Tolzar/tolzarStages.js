import { reactive } from 'vue';
import AttributeAPI from 'dashboard/api/attributes';

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

// Where a contact's stage is stored, best first. Tolzar writes `lifecycle_stage`; a workspace
// imported from respond.io also has `rio_lifecycle` (the mirror's copy, never written here).
// The first filled one wins. Override with the account setting `stage_attributes`.
export const DEFAULT_STAGE_ATTRIBUTES = Object.freeze([
  'lifecycle_stage',
  'rio_lifecycle',
]);
export const STAGE_ATTRIBUTES = reactive([...DEFAULT_STAGE_ATTRIBUTES]);

// A deal's value: which contact attribute holds it and its currency (settings deal_value_attribute,
// deal_currency; Settings > Pipeline). No currency: the number is shown without a symbol.
export const DEAL = reactive({ attribute: 'deal_value', currency: '' });

export const parseStageAttributes = value => {
  if (!Array.isArray(value)) return null;
  const out = [
    ...new Set(value.filter(k => /^[a-z0-9_]{1,60}$/.test(String(k)))),
  ];
  return out.length ? out.slice(0, 4) : null;
};

// accountSettings: the account's `settings` object (accounts/getAccount(id).settings).
export const applyPipelineStages = accountSettings => {
  const next =
    parsePipelineStages(accountSettings?.pipeline_stages) || DEFAULT_STAGES;
  STAGES.splice(0, STAGES.length, ...next.map(s => ({ ...s })));
  const attrs =
    parseStageAttributes(accountSettings?.stage_attributes) ||
    DEFAULT_STAGE_ATTRIBUTES;
  STAGE_ATTRIBUTES.splice(0, STAGE_ATTRIBUTES.length, ...attrs);
  const dealKey = String(accountSettings?.deal_value_attribute || '');
  DEAL.attribute = /^[a-z0-9_]{1,60}$/.test(dealKey) ? dealKey : 'deal_value';
  const code = String(accountSettings?.deal_currency || '');
  DEAL.currency = /^[A-Z]{3}$/.test(code) ? code : '';
  return STAGES;
};

// The contact's deal value as a number (0 when none).
export const dealValue = attrs => {
  const n = Number(attrs?.[DEAL.attribute]);
  return Number.isFinite(n) ? n : 0;
};

// 1234 -> "€1,234" (or "1,234" with no currency); `short` gives "€12.3k" from 10,000 up.
export const money = (v, { short = false } = {}) => {
  const n = Number(v) || 0;
  const compact = short && Math.abs(n) >= 10000;
  const opts = compact
    ? { notation: 'compact', maximumFractionDigits: 1 }
    : { maximumFractionDigits: 0 };
  try {
    return new Intl.NumberFormat(undefined, {
      ...opts,
      ...(DEAL.currency ? { style: 'currency', currency: DEAL.currency } : {}),
    }).format(n);
  } catch (e) {
    return Math.round(n).toLocaleString();
  }
};

// The workspace's list decides, by position: the first stage takes contacts with no stage, the last
// two are won and lost. Nothing is matched by a stage's name.
export const defaultStage = () => STAGES[0]?.key || DEFAULT_STAGES[0].key;
export const wonStage = () => STAGES[STAGES.length - 2]?.key;
export const lostStage = () => STAGES[STAGES.length - 1]?.key;
// Kept for older imports; prefer defaultStage() (it follows the workspace's list).
export const DEFAULT_STAGE = DEFAULT_STAGES[0].key;

// The stored stage of a contact ('' when none is set).
export const contactStage = attrs => {
  const key = STAGE_ATTRIBUTES.find(k => attrs?.[k]);
  return key ? String(attrs[key]) : '';
};

// Contact attributes the current workspace has defined; filtering on an undefined one is a 422.
const defined = { account: null, keys: null };
export const loadStageAttributes = async accountId => {
  if (defined.account === accountId && defined.keys) return defined.keys;
  try {
    const { data } = await AttributeAPI.getAttributesByModel();
    defined.keys = (data || [])
      .filter(d => d.attribute_model === 'contact_attribute')
      .map(d => d.attribute_key);
    defined.account = accountId;
  } catch (e) {
    defined.keys = null;
  }
  return defined.keys;
};

export const usableStageAttributes = () =>
  STAGE_ATTRIBUTES.filter(k => !defined.keys || defined.keys.includes(k));

const condition = (key, op, values) => ({
  attribute_key: key,
  filter_operator: op,
  values,
  query_operator: 'or',
  custom_attribute_type: 'contact_attribute',
  attribute_model: 'customAttributes',
});

// Contact-filter conditions for "the contact's stage is `key`" (first filled attribute wins);
// the default stage also takes contacts with no stage at all. The server joins conditions in
// order as SQL, where AND binds tighter than OR:
//   a = X OR a absent AND b = X [OR a absent AND b absent]
// null when the workspace defines none of the stage attributes.
export const stageConditions = key => {
  const keys = usableStageAttributes();
  if (!keys.length) return null;
  const out = [];
  const absentBefore = i =>
    keys.slice(0, i).forEach(k => {
      out.push({
        ...condition(k, 'is_not_present', []),
        query_operator: 'and',
      });
    });
  keys.forEach((k, i) => {
    absentBefore(i);
    out.push(condition(k, 'equal_to', [key]));
  });
  if (key === defaultStage()) {
    absentBefore(keys.length - 1);
    out.push(condition(keys[keys.length - 1], 'is_not_present', []));
  }
  out[out.length - 1] = { ...out[out.length - 1], query_operator: null };
  return out;
};

// The stage a set of applied contact filters selects, or '' when it is not a stage view.
export const stageOfConditions = list => {
  if (
    !list?.length ||
    !list.every(f => STAGE_ATTRIBUTES.includes(f.attribute_key))
  )
    return '';
  const eq = list.find(f => f.filter_operator === 'equal_to');
  return eq ? [eq.values].flat()[0] || '' : '';
};

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
  (key ? { key, label: key, tone: 'slate' } : stageOf(defaultStage()));

export const stageClass = key => TONE_CLASSES[stageOf(key).tone];

// Hex accents for the Dashboard and Pipeline charts (inline styles), one per tone.
export const TONE_HEX = {
  slate: '#64748b',
  amber: '#f59e0b',
  iris: '#5472e4',
  teal: '#10b981',
  ruby: '#f43f5e',
};
const TONE_ICON = {
  slate: 'i-lucide-user-plus',
  amber: 'i-lucide-activity',
  iris: 'i-lucide-file-text',
  teal: 'i-lucide-trophy',
  ruby: 'i-lucide-circle-x',
};
export const stageColor = key => TONE_HEX[stageOf(key).tone];
export const stageIcon = key => TONE_ICON[stageOf(key).tone];
// A stage chip's colours (inline style), from the stage's tone: the same in every list and header.
export const stageChipStyle = key => {
  const hex = stageColor(key);
  return { backgroundColor: `${hex}1f`, color: hex };
};

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
