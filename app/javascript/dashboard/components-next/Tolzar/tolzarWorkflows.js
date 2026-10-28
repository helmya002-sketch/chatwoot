// Tolzar Workflows: the step catalogue the builder shows, matching the brain's engine
// (aquarius_brain/workflows.py). Labels are i18n keys under TOLZAR_WORKFLOWS.
export const STEP_TYPES = [
  { type: 'send_message', icon: 'i-lucide-message-circle', accent: '#3e63dd' },
  { type: 'wait', icon: 'i-lucide-clock', accent: '#64748b' },
  { type: 'branch', icon: 'i-lucide-git-branch', accent: '#f59e0b' },
  { type: 'add_tag', icon: 'i-lucide-tag', accent: '#10b981' },
  { type: 'ai_tag', icon: 'i-lucide-sparkles', accent: '#8b5cf6' },
  { type: 'update_field', icon: 'i-lucide-square-pen', accent: '#8b5cf6' },
  { type: 'update_stage', icon: 'i-lucide-target', accent: '#ec4899' },
  { type: 'assign_team', icon: 'i-lucide-users', accent: '#0ea5e9' },
  { type: 'comment', icon: 'i-lucide-message-square', accent: '#64748b' },
  { type: 'record_score', icon: 'i-lucide-gauge', accent: '#14b8a6' },
  { type: 'close', icon: 'i-lucide-circle-check', accent: '#22c55e' },
];

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
    accent: '#64748b',
  };
  return { ...m, label: `TOLZAR_WORKFLOWS.STEP.${type}` };
};

export const uid = () => `s${Math.random().toString(36).slice(2, 9)}`;

export const textOf = text =>
  text && typeof text === 'object' ? text.en || Object.values(text)[0] || '' : text || '';

const duration = m => {
  if (!m) return '';
  if (m % 1440 === 0) return `${m / 1440} d`;
  if (m % 60 === 0) return `${m / 60} h`;
  return `${m} min`;
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
