// Tolzar Workflows: the step catalogue the builder shows, matching the brain's engine
// (tolzar_brain/workflows.py). Labels are i18n keys under TOLZAR_WORKFLOWS. Colours are theme
// classes (white-label and dark mode safe), kept as static strings so Tailwind ships them.
export const STEP_TYPES = [
  { type: 'send_message', icon: 'i-lucide-message-circle', tone: 'brand' },
  { type: 'wait', icon: 'i-lucide-clock', tone: 'slate' },
  { type: 'branch', icon: 'i-lucide-git-branch', tone: 'amber' },
  { type: 'add_tag', icon: 'i-lucide-tag', tone: 'teal' },
  { type: 'ai_tag', icon: 'i-lucide-sparkles', tone: 'violet' },
  { type: 'update_field', icon: 'i-lucide-square-pen', tone: 'iris' },
  { type: 'update_stage', icon: 'i-lucide-target', tone: 'ruby' },
  { type: 'assign_team', icon: 'i-lucide-users', tone: 'blue' },
  { type: 'comment', icon: 'i-lucide-message-square', tone: 'slate' },
  { type: 'record_score', icon: 'i-lucide-gauge', tone: 'teal' },
  { type: 'close', icon: 'i-lucide-circle-check', tone: 'teal' },
];

const TONE_TEXT = {
  brand: 'text-n-brand',
  slate: 'text-n-slate-11',
  amber: 'text-n-amber-11',
  teal: 'text-n-teal-11',
  violet: 'text-n-violet-11',
  iris: 'text-n-iris-11',
  ruby: 'text-n-ruby-11',
  blue: 'text-n-blue-11',
};
const TONE_TOP = {
  brand: 'border-t-n-brand',
  slate: 'border-t-n-slate-9',
  amber: 'border-t-n-amber-9',
  teal: 'border-t-n-teal-9',
  violet: 'border-t-n-violet-9',
  iris: 'border-t-n-iris-9',
  ruby: 'border-t-n-ruby-9',
  blue: 'border-t-n-blue-9',
};

export const TRIGGERS = ['first_message', 'guest_message', 'field_equals', 'field_date'];
export const CONDITIONS = [
  'replied',
  'reply_matches',
  'reply_number',
  'field_equals',
  'field_empty',
  'has_tag',
  'channel_is',
];

export const stepMeta = type => {
  const m = STEP_TYPES.find(s => s.type === type) || {
    icon: 'i-lucide-circle-dot',
    tone: 'slate',
  };
  return {
    ...m,
    label: `TOLZAR_WORKFLOWS.STEP.${type}`,
    text: TONE_TEXT[m.tone] || TONE_TEXT.slate,
    top: TONE_TOP[m.tone] || TONE_TOP.slate,
  };
};

// Ids: a UUID where the platform has one (every current browser), a time+random string elsewhere.
const randomId = () => {
  const c = globalThis.crypto;
  if (c && typeof c.randomUUID === 'function') return c.randomUUID();
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
};
export const uid = () => `s${randomId()}`;

export const textOf = text =>
  text && typeof text === 'object' ? text.en || Object.values(text)[0] || '' : text || '';

const duration = m => {
  if (!m) return '';
  if (m % 1440 === 0) return `${m / 1440} d`;
  if (m % 60 === 0) return `${m / 60} h`;
  return `${m} min`;
};

// Wait step: minutes <-> { n, unit }. The editor keeps the unit the user picked (see TolzarWorkflows),
// so the select never flips on its own; a fraction is rounded to the unit ("1.5 days" -> 2 days).
export const WAIT_UNITS = [1, 60, 1440];
export const waitParts = minutes => {
  const m = Number(minutes) || 0;
  if (m > 0 && m % 1440 === 0) return { n: m / 1440, unit: 1440 };
  if (m > 0 && m % 60 === 0) return { n: m / 60, unit: 60 };
  return { n: m, unit: 1 };
};
export const waitMinutes = (n, unit) => {
  const u = WAIT_UNITS.includes(Number(unit)) ? Number(unit) : 1;
  const v = Math.round(Number(n) || 0);
  return Math.max(1, v) * u;
};

export const conditionText = c => {
  if (!c) return '';
  if (c.kind === 'reply_matches') return `reply ~ ${(c.words || []).slice(0, 3).join(', ')}`;
  if (c.kind === 'reply_number') return `reply ${c.min ?? 0}–${c.max ?? 10}`;
  if (c.kind === 'field_equals') return `${c.field} = ${c.value}`;
  if (c.kind === 'field_empty') return `${c.field} empty`;
  if (c.kind === 'has_tag') return `#${c.tag}`;
  if (c.kind === 'channel_is') return `channel ${c.value}`;
  return c.kind;
};

export const stepSummary = s => {
  const c = s.config || {};
  switch (s.type) {
    case 'send_message':
    case 'comment':
      return textOf(c.text);
    case 'wait':
      return `${duration(c.minutes)}${c.until_reply ? ' · or a reply' : ''}`;
    case 'branch':
      return (c.conditions || []).map(conditionText).join(c.match === 'any' ? ' or ' : ' and ');
    case 'add_tag':
      return c.tag || '';
    case 'ai_tag':
      return (c.tags || []).map(t => t.tag).join(', ');
    case 'update_field':
      return `${c.field || ''} = ${c.value ?? ''}`;
    case 'update_stage':
      return c.stage || '';
    case 'assign_team':
      return c.team || String(c.team_id || '');
    case 'record_score':
      return c.name || 'nps';
    default:
      return '';
  }
};

// Every branch gets its Yes / No lists before the canvas renders (a workflow saved by the brain may
// have a branch without them), so the canvas never has to create state while it draws.
export const normaliseBranches = steps => {
  (steps || []).forEach(s => {
    if (s && s.type === 'branch') {
      s.config = s.config || {};
      s.config.then = Array.isArray(s.config.then) ? s.config.then : [];
      s.config.else = Array.isArray(s.config.else) ? s.config.else : [];
      normaliseBranches(s.config.then);
      normaliseBranches(s.config.else);
    }
  });
  return steps;
};

export const newStep = type => {
  const config = {
    send_message: { text: { en: '' } },
    comment: { text: '' },
    wait: { minutes: 1440 },
    branch: { match: 'all', conditions: [{ kind: 'replied' }], then: [], else: [] },
    add_tag: { tag: '' },
    ai_tag: { max: 1, tags: [{ tag: '', when: '' }] },
    update_field: { field: '', value: '' },
    update_stage: { stage: '' },
    assign_team: { team_id: '' },
    record_score: { name: 'nps' },
    close: {},
  }[type];
  return { id: uid(), type, config: JSON.parse(JSON.stringify(config || {})) };
};

// Fresh step ids all the way down (a duplicated workflow must not share ids with its original).
const reId = steps => {
  (steps || []).forEach(s => {
    if (!s) return;
    s.id = uid();
    if (s.type === 'branch' && s.config) {
      reId(s.config.then);
      reId(s.config.else);
    }
  });
  return steps;
};

// A copy of a workflow for the builder (UI only): new id, "(copy)" in the name, off until saved,
// without the brain's bookkeeping fields. Saving it is an ordinary POST /workflows.
export const duplicateWorkflow = (wf, suffix = '(copy)') => {
  const copy = JSON.parse(JSON.stringify(wf || {}));
  copy.id = uid();
  copy.name = `${copy.name || ''} ${suffix}`.trim();
  copy.status = 'draft';
  delete copy.updated_at;
  delete copy.created_at;
  copy.steps = reId(normaliseBranches(Array.isArray(copy.steps) ? copy.steps : []));
  return copy;
};

// Run status -> tone (the page maps tones to tzClasses TONE_*): finished well, failed, stopped, busy.
export const runTone = status =>
  ({ done: 'ok', failed: 'bad', cancelled: 'muted' })[status] || 'warn';

// The languages a workspace writes in (brain workspace settings view -> merged.languages), as
// lower-case codes. A list or a comma/newline string; anything that is not a code is dropped.
export const workspaceLanguages = view => {
  const raw = view && view.merged ? view.merged.languages : null;
  const list = Array.isArray(raw) ? raw : String(raw || '').split(/[\n,]/);
  return [
    ...new Set(
      list
        .map(x => String(x).trim().toLowerCase())
        .filter(x => /^[a-z]{2,3}(-[a-z]{2,4})?$/.test(x))
    ),
  ];
};

// Which language the message editor shows: the chosen one while it exists, else the first.
export const pickLang = (langs, current) =>
  (langs || []).includes(current) ? current : (langs || [])[0] || '';
