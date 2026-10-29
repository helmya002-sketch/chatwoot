// Tolzar AI-agent Skills: the shape the brain reads (tolzar_brain/agent_skills.py) and the editor's
// form. Skills are PROPOSALS only: the brain writes "would do" notes, it never executes one.
//
// Per agent:
//   skills_enabled: false            gate for the whole agent (default off)
//   skills_dry_run_workflows: true   trigger_workflow only records "would start" (default on)
//   skills: [{ type, enabled, when, config }]
// Config per type:
//   assign            { team_ids: [], agent_names: [] }
//   update_fields     { contact_fields: [], conversation_fields: [] }
//   change_stage      { stages: [] }
//   close             {}
//   add_tag           { tags: [] }
//   trigger_workflow  { workflow_ids: [] }
// The older draft shape { type: 'tags', config: '<text>' } loads too: the text becomes `when` and
// the old type names map like the brain's ALIASES. `comment` is not a skill any more (every
// proposal is already a private note), so it is dropped.

export const SKILL_TYPES = [
  'assign',
  'update_fields',
  'change_stage',
  'close',
  'add_tag',
  'trigger_workflow',
];
export const ALIASES = {
  update_lifecycle: 'change_stage',
  tags: 'add_tag',
  workflow: 'trigger_workflow',
};
// The brain's limits (agent_skills.py): more is cut there, so the editor refuses it here.
export const MAX_SKILLS = 8;
export const MAX_WHEN = 160;
export const MAX_LIST = 12;
export const MAX_VALUE = 200;

// The config lists of each type (all lists: an empty object for close).
export const CONFIG_KEYS = {
  assign: ['team_ids', 'agent_names'],
  update_fields: ['contact_fields', 'conversation_fields'],
  change_stage: ['stages'],
  close: [],
  add_tag: ['tags'],
  trigger_workflow: ['workflow_ids'],
};

export const skillType = type => {
  const t = String(type || '');
  return ALIASES[t] || t;
};

// team_ids stay numbers when they are numbers (Chatwoot team ids); everything else is a string.
const cleanList = (value, numeric = false) => {
  const raw = Array.isArray(value) ? value : [value];
  const out = [];
  raw.forEach(v => {
    if (typeof v !== 'string' && typeof v !== 'number') return;
    const s = String(v).trim().slice(0, MAX_VALUE);
    if (!s) return;
    const item = numeric && /^\d+$/.test(s) ? Number(s) : s;
    if (!out.some(x => String(x) === String(item))) out.push(item);
  });
  return out;
};

export const emptyConfig = type =>
  Object.fromEntries((CONFIG_KEYS[type] || []).map(k => [k, []]));

// One saved skill (any shape) -> the editor's form, or null when it is not a skill.
export const skillFromSaved = raw => {
  if (!raw || typeof raw !== 'object') return null;
  const type = skillType(raw.type);
  if (!SKILL_TYPES.includes(type)) return null;
  const conf = raw.config;
  let when = typeof conf === 'string' ? conf : '';
  if (typeof raw.when === 'string' && raw.when) when = raw.when;
  const src =
    conf && typeof conf === 'object' && !Array.isArray(conf) ? conf : {};
  const config = emptyConfig(type);
  Object.keys(config).forEach(k => {
    config[k] = cleanList(src[k] ?? [], k === 'team_ids');
  });
  return { type, enabled: raw.enabled !== false, when, config };
};

// The agent's saved skill fields -> the editor's form. One skill per type (the first wins, as
// in the brain).
export const skillsFromAgent = agent => {
  const a = agent || {};
  const skills = [];
  (Array.isArray(a.skills) ? a.skills : []).forEach(raw => {
    const s = skillFromSaved(raw);
    if (s && !skills.some(x => x.type === s.type)) skills.push(s);
  });
  return {
    skills_enabled: a.skills_enabled === true,
    skills_dry_run_workflows: a.skills_dry_run_workflows !== false,
    skills,
  };
};

export const newSkill = type => ({
  type,
  enabled: true,
  when: '',
  config: emptyConfig(type),
});

// The form -> what is saved with the agent (the brain's shape exactly).
export const skillsToAgent = form => ({
  skills_enabled: !!form.skills_enabled,
  skills_dry_run_workflows: form.skills_dry_run_workflows !== false,
  skills: (form.skills || []).map(s => {
    const type = skillType(s.type);
    const config = emptyConfig(type);
    Object.keys(config).forEach(k => {
      config[k] = cleanList(s.config?.[k] ?? [], k === 'team_ids');
    });
    return {
      type,
      enabled: s.enabled !== false,
      when: String(s.when || '')
        .replace(/\s+/g, ' ')
        .trim(),
      config,
    };
  }),
});

// "vip, follow-up ,vip" -> ['vip', 'follow-up'] (the tags box is free text).
export const parseTags = text => cleanList(String(text || '').split(','));

// Problems with the form: [{ index, type, error }] where error is one of
//   too_many_skills, duplicate, when_too_long, too_many_values, needs_values.
// `index` is -1 for a whole-list problem. Only enabled skills need allowed values (the brain
// skips an enabled skill with none, so it would silently do nothing).
export const skillProblems = form => {
  const out = [];
  const skills = form?.skills || [];
  if (skills.length > MAX_SKILLS)
    out.push({ index: -1, type: '', error: 'too_many_skills' });
  const seen = new Set();
  skills.forEach((s, index) => {
    const type = skillType(s.type);
    if (seen.has(type)) out.push({ index, type, error: 'duplicate' });
    seen.add(type);
    if (String(s.when || '').trim().length > MAX_WHEN)
      out.push({ index, type, error: 'when_too_long' });
    const keys = CONFIG_KEYS[type] || [];
    const lists = keys.map(k => cleanList(s.config?.[k] ?? []));
    if (lists.some(l => l.length > MAX_LIST))
      out.push({ index, type, error: 'too_many_values' });
    if (s.enabled !== false && type !== 'close' && !lists.some(l => l.length))
      out.push({ index, type, error: 'needs_values' });
  });
  return out;
};

// Saving is refused only while skills are switched on: with the gate off the brain reads none of
// them, so a half-filled draft can be kept.
export const blocksSave = form =>
  !!form?.skills_enabled && skillProblems(form).length > 0;

// Toggle a value in one of a skill's lists (the pickers).
export const toggleValue = (list, value) => {
  const i = (list || []).findIndex(x => String(x) === String(value));
  if (i >= 0) return list.filter((_, j) => j !== i);
  return [...(list || []), value];
};
