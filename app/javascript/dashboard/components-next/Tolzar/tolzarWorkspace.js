// Tolzar workspace settings (brain workspace_settings.py), per-agent price sources and going live,
// through the admin proxy (TolzarController#workspace_settings, #price_source*, #go_live,
// #kill_switch). The proxy adds the workspace id and, for go-live, the account's real name; the UI
// never sends either. The brain's refusals come back as data with their status kept:
// 400 invalid_settings {errors}, 409 version_conflict {version}, 422 not_live_ready {reasons}.

const base = accountId => `/api/v1/accounts/${accountId}/tolzar`;

// A refused request comes back as its body (the page says why); only a network failure throws.
const answer = request =>
  request
    .then(r => r.data)
    .catch(e => {
      if (e && e.response && e.response.data) return e.response.data;
      throw e;
    });

// ---- API -------------------------------------------------------------------------------------
export const getWorkspaceSettings = accountId =>
  answer(window.axios.get(`${base(accountId)}/workspace/settings`));
export const saveWorkspaceSettings = (accountId, patch) =>
  answer(window.axios.post(`${base(accountId)}/workspace/settings`, patch));
export const goLive = (accountId, inboxId, mode, confirm = '') =>
  answer(
    window.axios.post(`${base(accountId)}/workspace/go_live`, {
      inbox_id: Number(inboxId),
      mode,
      confirm: String(confirm || '').trim(),
    })
  );
export const killSwitch = accountId =>
  answer(window.axios.post(`${base(accountId)}/workspace/kill_switch`, {}));

// The kill switch locks go-live until an Owner releases it (nothing goes live by releasing).
export const releaseKillSwitch = accountId =>
  answer(
    window.axios.post(`${base(accountId)}/workspace/kill_switch/release`, {})
  );

const priceUrl = (accountId, agentId) =>
  `${base(accountId)}/agents/${encodeURIComponent(agentId)}/price_source`;
export const getPriceSource = (accountId, agentId) =>
  answer(window.axios.get(priceUrl(accountId, agentId)));
export const savePriceSource = (accountId, agentId, body) =>
  answer(window.axios.post(priceUrl(accountId, agentId), body));
export const testPriceSource = (accountId, agentId, body) =>
  answer(window.axios.post(`${priceUrl(accountId, agentId)}/test`, body));

// ---- reading a settings view ------------------------------------------------------------------
// A dotted path in a tree. `categories` is a list in the config (defaults / merged) but keyed by
// category key in the overrides, so a path like categories.sales_lead.description works in both.
export const getIn = (tree, path) => {
  let node = tree;
  const segs = String(path).split('.');
  for (let i = 0; i < segs.length; i += 1) {
    if (node === null || node === undefined) return undefined;
    if (Array.isArray(node)) {
      node = node.find(x => x && x.key === segs[i]);
    } else if (typeof node === 'object') {
      node = node[segs[i]];
    } else {
      return undefined;
    }
  }
  return node;
};

export const TEMPLATE_NAMES = [
  'ask_location',
  'handover',
  'handover_owners',
  'nudge',
  'after_hours',
];
export const WEEKDAYS = [0, 1, 2, 3, 4, 5, 6]; // 0 = Monday ... 6 = Sunday (brain WorkingHours)

// Every editable field the panel shows, from the view (which places, categories, teams and
// languages this workspace has). kind: text | time | days | lines | list | number | select | longtext.
export const workspaceFields = view => {
  const merged = (view && view.merged) || {};
  const langs = [
    ...new Set([
      ...(merged.languages || []),
      ...TEMPLATE_NAMES.flatMap(n =>
        Object.keys((merged.templates || {})[n] || {})
      ),
    ]),
  ];
  const f = (group, path, kind, extra = {}) => ({
    group,
    path,
    kind,
    ...extra,
  });
  return [
    f('general', 'workspace_name', 'text'),
    f('general', 'bot.display_name', 'text'),
    f('general', 'timezone', 'select'),
    f('general', 'languages', 'list'),
    f('general', 'local_currency', 'text'),
    f('general', 'phone_region', 'text'),
    f('hours', 'working_hours.start', 'time'),
    f('hours', 'working_hours.end', 'time'),
    f('hours', 'working_hours.closed_days', 'days'),
    f('hours', 'working_hours.holidays', 'lines'),
    f('budgets', 'budgets.max_llm_calls_per_conversation', 'number'),
    f('budgets', 'budgets.max_llm_calls_per_day', 'number'),
    ...TEMPLATE_NAMES.flatMap(n =>
      langs.map(l =>
        f('templates', `templates.${n}.${l}`, 'longtext', { name: n, lang: l })
      )
    ),
    ...Object.keys(merged.destinations || {}).map(k =>
      f('places', `destinations.${k}.name`, 'text', { name: k })
    ),
    ...(merged.categories || [])
      .filter(c => c && c.key)
      .map(c =>
        f('categories', `categories.${c.key}.description`, 'longtext', {
          name: c.key,
        })
      ),
    ...Object.keys(merged.teams || {}).map(k =>
      f('teams', `team_descriptions.${k}`, 'longtext', { name: k })
    ),
  ];
};

// The value in the form's shape: times as HH:MM, lists as arrays, numbers as numbers.
export const normalize = (kind, v) => {
  if (v === undefined || v === null) {
    if (['days', 'lines', 'list'].includes(kind)) return [];
    return kind === 'number' ? null : '';
  }
  if (kind === 'time') return String(v).slice(0, 5);
  if (kind === 'days')
    return [...new Set((v || []).map(Number))].sort((a, b) => a - b);
  if (kind === 'lines' || kind === 'list') {
    const items = Array.isArray(v) ? v : String(v).split(/[\n,]/);
    return items.map(x => String(x).trim()).filter(Boolean);
  }
  if (kind === 'number') {
    if (v === '') return null;
    const n = Number(v);
    return Number.isFinite(n) ? n : v;
  }
  return String(v).trim();
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

export const defaultOf = (view, field) =>
  normalize(field.kind, getIn((view && view.defaults) || {}, field.path));
export const hasOverride = (view, field) =>
  getIn((view && view.overrides) || {}, field.path) !== undefined;
export const currentOf = (view, field) =>
  hasOverride(view, field)
    ? normalize(field.kind, getIn(view.overrides, field.path))
    : defaultOf(view, field);

// {path: value} for the editor (lists of lines are edited as text).
export const formFromView = (view, fields = workspaceFields(view)) =>
  Object.fromEntries(
    fields.map(fd => {
      const v = currentOf(view, fd);
      if (fd.kind === 'lines') return [fd.path, v.join('\n')];
      return [fd.path, fd.kind === 'list' ? v.join(', ') : v];
    })
  );

// The POST body: {version, set, unset}. A field set back to its default drops the override; a
// field in `resets` ("Reset to default") is unset; an unchanged field is not sent.
export const buildPatch = (
  view,
  form,
  fields = workspaceFields(view),
  resets = []
) => {
  const set = {};
  const unset = [];
  fields.forEach(fd => {
    const overridden = hasOverride(view, fd);
    if (resets.includes(fd.path)) {
      if (overridden) unset.push(fd.path);
      return;
    }
    const value = normalize(fd.kind, form[fd.path]);
    if (same(value, currentOf(view, fd))) return;
    if (same(value, defaultOf(view, fd)) && overridden) unset.push(fd.path);
    else set[fd.path] = value;
  });
  return { version: (view && view.version) || 0, set, unset };
};
export const isEmptyPatch = p =>
  !Object.keys(p.set || {}).length && !(p.unset || []).length;

// The brain's 400 errors, per field (an error on a parent or a child path lands on the field);
// what matches no field is returned in `other`.
export const fieldErrors = (res, fields = []) => {
  const byPath = {};
  const other = [];
  ((res && res.errors) || []).forEach(e => {
    const p = String(e.path || '');
    const hit = fields.filter(
      fd =>
        fd.path === p ||
        fd.path.startsWith(`${p}.`) ||
        p.startsWith(`${fd.path}.`)
    );
    if (!hit.length) other.push(p ? `${p}: ${e.error}` : String(e.error));
    hit.forEach(fd => {
      byPath[fd.path] = byPath[fd.path]
        ? `${byPath[fd.path]} · ${e.error}`
        : e.error;
    });
  });
  return { byPath, other };
};

export const isConflict = res => !!res && res.error === 'version_conflict';
export const isInvalid = res => !!res && res.error === 'invalid_settings';
export const isOwner = view => !!view && view.viewer_role === 'owner';

// ---- going live -------------------------------------------------------------------------------
export const KNOWN_REASONS = [
  'no_price_table',
  'price_table_without_prices',
  'legacy_path',
  'mirror_inbox',
  'negotiation_on',
  'no_active_agent',
  'live_check_error',
  'not_live_ready',
];

// One refusal reason: "team sales: no_price_table" / "team_agent:no_price_table" name the team
// agent the reason is about. `known` = there is a plain-words label for `code`.
export const parseReason = raw => {
  const s = String(raw || '').trim();
  let team = null;
  let code = s;
  let m = s.match(/^team\s+([^:]+):\s*(.+)$/);
  if (m) [, team, code] = m;
  m = !team && s.match(/^team_agent:\s*(.+)$/);
  if (m) {
    team = '';
    [, code] = m;
  }
  code = code.trim();
  return { raw: s, code, team, known: KNOWN_REASONS.includes(code) };
};
export const parseReasons = res =>
  ((res && res.reasons) || []).map(parseReason);

// Each inbox with its effective mode: the merged config's triage mode for that inbox (it already
// carries the go-live entries and the kill switch), else the triage default, else Shadow.
export const inboxModes = (view, inboxes = []) => {
  const triage = getIn((view && view.merged) || {}, 'skills.triage') || {};
  const modes = triage.inbox_modes || {};
  const stored = (view && view.inbox_modes) || {};
  return inboxes.map(ib => {
    let mode = modes[String(ib.id)] || triage.mode || 'shadow';
    if (stored[String(ib.id)] && stored[String(ib.id)].mode === 'live')
      mode = 'live';
    return { id: ib.id, name: ib.name, mode, since: stored[String(ib.id)] };
  });
};
export const anyLive = rows => rows.some(r => r.mode === 'live');

// What the go-live confirmation must say (the brain checks the same): the workspace name set in
// the settings, else the account's name.
export const confirmName = view =>
  String(
    getIn((view && view.overrides) || {}, 'workspace_name') ||
      (view && view.account_name) ||
      ''
  ).trim();
export const confirmMatches = (typed, view) => {
  const name = confirmName(view);
  return !!name && String(typed || '').trim() === name;
};

// ---- price source -----------------------------------------------------------------------------
export const PRICE_TYPES = ['url', 'feed', 'table', 'commerce'];
export const defaultRefreshHours = type => (type === 'feed' ? 1 : 24);

export const priceSourceForm = view => {
  const s = (view && view.source) || {};
  const type = PRICE_TYPES.includes(s.type) ? s.type : 'url';
  return {
    type,
    url: s.url || '',
    refresh_hours: s.refresh_hours || defaultRefreshHours(type),
  };
};

// What the form would be refused for, before asking the brain (which checks again).
export const priceSourceProblems = form => {
  if (!form || !PRICE_TYPES.includes(form.type)) return ['type'];
  if (form.type === 'commerce') return [];
  const out = [];
  const url = String(form.url || '').trim();
  if (!url) out.push('url_required');
  else if (!/^https:\/\//i.test(url)) out.push('https_only');
  const h = Number(form.refresh_hours);
  if (!Number.isInteger(h) || h < 1 || h > 168) out.push('hours_range');
  return out;
};

export const priceSourceBody = form =>
  form.type === 'commerce'
    ? { type: 'commerce' }
    : {
        type: form.type,
        url: String(form.url || '').trim(),
        refresh_hours: Number(form.refresh_hours),
      };

// The 3 sample rows as table columns (union of keys, empty values left out).
export const sampleColumns = sample => {
  const keys = [];
  (sample || []).forEach(r =>
    Object.entries(r || {}).forEach(([k, v]) => {
      if (v !== null && v !== '' && v !== undefined && !keys.includes(k))
        keys.push(k);
    })
  );
  return keys;
};

// The saved source in the agent's own shape (generic.prices, as the brain stores it), so the
// agent editor's copy stays in step and a later "Save agent" does not put the old source back.
const BRAIN_PRICE_TYPES = {
  url: 'jsonld',
  feed: 'departures',
  table: 'csv',
  commerce: 'commerce',
};
export const agentPrices = (source, old = {}) => {
  const type = BRAIN_PRICE_TYPES[source && source.type];
  if (!type) return old || null;
  if (type === 'commerce') return { type };
  const out = {
    type,
    value: source.url || '',
    refresh_hours: source.refresh_hours,
  };
  if (type === 'departures' && old && old.key_env) out.key_env = old.key_env;
  return out;
};
