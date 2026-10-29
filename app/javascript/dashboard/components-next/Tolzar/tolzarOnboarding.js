// Tolzar first-run setup (brain plugins/onboarding.py) through the proxy:
//   POST /tolzar/workspace/bootstrap  (Owner-only; the proxy adds the workspace and its owner)
//     -> 200 {ok, version, settings, pack, agent (status "inactive") | null, checklist}
//     -> 400 invalid_settings {errors}, 403 owner_only,
//        409 already_bootstrapped | settings_exist | workspace_has_config_file
//   GET  /tolzar/workspace/checklist  (every administrator)
//     -> {ok, done, total, bootstrapped, items: [{key, done, detail, action_hint, required}]}
// The starter agent is created INACTIVE; nothing here turns anything live.

const base = accountId => `/api/v1/accounts/${accountId}/tolzar`;

// A refused request comes back as its body (the page says why); only a network failure throws.
const answer = request =>
  request
    .then(r => r.data)
    .catch(e => {
      if (e && e.response && e.response.data) return e.response.data;
      throw e;
    });

export const bootstrapWorkspace = (accountId, body) =>
  answer(window.axios.post(`${base(accountId)}/workspace/bootstrap`, body));
export const getChecklist = accountId =>
  answer(window.axios.get(`${base(accountId)}/workspace/checklist`));

export const NONE_PACK = 'none';
export const ALREADY_SET_UP = [
  'already_bootstrapped',
  'settings_exist',
  'workspace_has_config_file',
];
// 0 = Monday ... 6 = Sunday, as the brain's working_hours.closed_days.
export const WEEKDAYS = [0, 1, 2, 3, 4, 5, 6];

export const browserTimezone = () => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  } catch (e) {
    return 'UTC';
  }
};

export const emptyForm = () => ({
  workspaceName: '',
  timezone: browserTimezone(),
  start: '09:00',
  end: '18:00',
  closedDays: [],
  languages: 'en',
  pack: NONE_PACK,
  template: '',
  agentName: 'Assistant',
  website: '',
});

// "en, DE ,en" -> ['en', 'de'] (language codes, first wins, at most 30 like the brain).
export const parseLanguages = text => {
  const out = [];
  String(text || '')
    .split(/[,\s]+/)
    .map(x => x.trim().toLowerCase())
    .filter(Boolean)
    .forEach(code => {
      if (!out.includes(code) && out.length < 30) out.push(code);
    });
  return out;
};

// The form -> the bootstrap body. No account id and no owner: the proxy sets both server-side.
export const bootstrapBody = form => {
  const body = {
    workspace_name: String(form.workspaceName || '').trim(),
    timezone: String(form.timezone || '').trim(),
    working_hours: {
      start: form.start,
      end: form.end,
      closed_days: [...(form.closedDays || [])].sort((a, b) => a - b),
    },
    pack: form.pack || NONE_PACK,
    agent_name: String(form.agentName || '').trim() || 'Assistant',
  };
  const langs = parseLanguages(form.languages);
  if (langs.length) body.languages = langs;
  if (form.template) body.template = form.template;
  return body;
};

// What the page can say before sending: [{ path, error }] with error 'required' | 'hours'.
export const formProblems = form => {
  const out = [];
  if (!String(form.workspaceName || '').trim())
    out.push({ path: 'workspace_name', error: 'required' });
  if (!String(form.timezone || '').trim())
    out.push({ path: 'timezone', error: 'required' });
  if (
    !/^\d{2}:\d{2}$/.test(form.start || '') ||
    !/^\d{2}:\d{2}$/.test(form.end || '')
  )
    out.push({ path: 'working_hours', error: 'hours' });
  return out;
};

// The brain's answer -> 'done' | 'already' | 'invalid' | 'owner_only' | 'error'.
export const bootstrapOutcome = data => {
  if (data && data.ok) return 'done';
  const code = data && data.error;
  if (ALREADY_SET_UP.includes(code)) return 'already';
  if (code === 'invalid_settings') return 'invalid';
  if (code === 'owner_only') return 'owner_only';
  return 'error';
};

// A checklist item's action_hint -> where in the app it is fixed (a router location).
const settings = section => ({ name: 'tolzar_settings', query: { section } });
const ACTIONS = {
  workspace_settings: () => settings('workspace_settings'),
  choose_pack: () => settings('workspace_settings'),
  agents: () => ({ name: 'tolzar_ai_agents' }),
  knowledge_refresh: () => ({ name: 'tolzar_ai_agents' }),
  price_source: () => ({ name: 'tolzar_ai_agents' }),
  add_inbox: accountId => `/app/accounts/${accountId}/settings/inboxes/new`,
  compliance: () => settings('disclosure'),
  owner: () => settings('roles'),
  go_live_review: () => settings('go_live'),
};
export const checklistLink = (hint, accountId) => {
  const make = ACTIONS[hint];
  return make ? make(accountId) : null;
};

// Required items first (in the brain's order), then the informational ones.
export const checklistItems = data => {
  const items = Array.isArray(data?.items) ? data.items : [];
  return [
    ...items.filter(i => i && i.required !== false),
    ...items.filter(i => i && i.required === false),
  ];
};

export const checklistProgress = data => {
  const req = checklistItems(data).filter(i => i.required !== false);
  return { done: req.filter(i => i.done).length, total: req.length };
};
