// Tolzar routing editor (readiness row 4): one screen for the workspace's places (teams), the keywords that
// send a message to each place, the "always a person" words (the hand-over category's keywords) and the
// hand-over message, on top of the brain's workspace settings (workspace_settings.py). Keywords are editable
// only while the brain's TOLZAR_ROUTING_EDITOR switch is on (view.routing_editor); names, team descriptions and
// the hand-over message are ordinary settings. Only an Owner saves; the routing logic itself never changes here.

const words = list => (Array.isArray(list) ? list.map(String) : []);

// "Makadi, El Gouna\nsoma bay" -> ['makadi', 'el gouna', 'soma bay'] (trimmed, lower-case, no repeats).
export const parseKeywords = text => {
  const out = [];
  String(text || '')
    .split(/[,\n]/)
    .map(w => w.trim().toLowerCase())
    .forEach(w => {
      if (w && !out.includes(w)) out.push(w);
    });
  return out;
};
export const keywordText = list => words(list).join(', ');

export const routingModel = view => {
  const m = (view && view.merged) || {};
  const rules = m.rules || {};
  const destKw = rules.destination_keywords || {};
  const catKw = rules.category_keywords || {};
  const handoverCat = (m.categories || []).find(c => c && c.handover) || null;
  return {
    version: view ? view.version : 0,
    keywordsEditable: !!(view && view.routing_editor),
    owner: !!view && view.viewer_role === 'owner',
    places: Object.entries(m.destinations || {}).map(([key, d]) => ({
      key,
      name: (d && (d.name || d.location)) || key,
      team: (d && d.team) || '',
      keywords: words(destKw[key]),
    })),
    teams: Object.keys(m.teams || {}),
    teamDescriptions: { ...(m.team_descriptions || {}) },
    handoverCategory: handoverCat ? handoverCat.key : null,
    alwaysPerson: handoverCat ? words(catKw[handoverCat.key]) : [],
    handover: { ...((m.templates && m.templates.handover) || {}) },
    handoverOwners: {
      ...((m.templates && m.templates.handover_owners) || {}),
    },
  };
};

// The form the screen edits: plain strings, so text boxes bind directly.
export const routingForm = model => ({
  places: Object.fromEntries(
    model.places.map(p => [
      p.key,
      { name: p.name, keywords: keywordText(p.keywords) },
    ])
  ),
  teamDescriptions: { ...model.teamDescriptions },
  alwaysPerson: keywordText(model.alwaysPerson),
  handover: { ...model.handover },
  handoverOwners: { ...model.handoverOwners },
});

const sameList = (a, b) =>
  a.length === b.length && a.every((x, i) => x === b[i]);

// Only what changed, as the settings API's {path: value} "set" map.
export const routingPatch = (model, form) => {
  const set = {};
  model.places.forEach(p => {
    const f = form.places[p.key] || {};
    const name = String(f.name || '').trim();
    if (name && name !== p.name) set[`destinations.${p.key}.name`] = name;
    if (model.keywordsEditable) {
      const kw = parseKeywords(f.keywords);
      if (!sameList(kw, p.keywords))
        set[`rules.destination_keywords.${p.key}`] = kw;
    }
  });
  model.teams.forEach(team => {
    const v = String(form.teamDescriptions[team] || '').trim();
    if (v !== String(model.teamDescriptions[team] || '').trim())
      set[`team_descriptions.${team}`] = v;
  });
  if (model.keywordsEditable && model.handoverCategory) {
    const kw = parseKeywords(form.alwaysPerson);
    if (!sameList(kw, model.alwaysPerson))
      set[`rules.category_keywords.${model.handoverCategory}`] = kw;
  }
  [
    ['handover', 'handover'],
    ['handoverOwners', 'handover_owners'],
  ].forEach(([key, template]) => {
    Object.keys(form[key] || {}).forEach(lang => {
      const v = String(form[key][lang] || '').trim();
      if (v && v !== String(model[key][lang] || '').trim())
        set[`templates.${template}.${lang}`] = v;
    });
  });
  return set;
};
