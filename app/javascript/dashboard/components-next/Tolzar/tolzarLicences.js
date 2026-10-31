// Tolzar "Open-source licences" page (profile menu): the notices of every component the product ships,
// from GET /api/v1/accounts/:id/open_source_licences (Tolzar::OpenSourceNotices). Pure helpers here; the
// page is routes/dashboard/tolzar/TolzarLicences.vue.

export const GROUPS = ['gems', 'javascript', 'system', 'ai'];

export const getLicences = accountId =>
  window.axios
    .get(`/api/v1/accounts/${accountId}/open_source_licences`)
    .then(r => r.data);

const text = v => (v === null || v === undefined ? '' : String(v));

// Every field the template reads is present, whatever the server omitted.
export const licencesView = data => {
  const d = data || {};
  const groups = d.groups || {};
  const item = i => ({
    name: text(i && i.name),
    version: text(i && i.version),
    licences: Array.isArray(i && i.licences) ? i.licences.map(text) : [],
    homepage: text(i && i.homepage),
    author: text(i && i.author),
    text: text(i && i.text),
  });
  return {
    foundation: item(d.foundation),
    groups: Object.fromEntries(
      GROUPS.map(g => [
        g,
        (Array.isArray(groups[g]) ? groups[g] : []).map(item),
      ])
    ),
    sourceOffer: (Array.isArray(d.source_offer) ? d.source_offer : []).map(
      item
    ),
  };
};

// Only http(s) links are rendered as links; anything else shows as text.
export const safeUrl = url => (/^https?:\/\//i.test(text(url)) ? url : '');

// Case-insensitive match on the name or the licence.
export const filterItems = (items, query) => {
  const q = text(query).trim().toLowerCase();
  if (!q) return items;
  return items.filter(
    i =>
      i.name.toLowerCase().includes(q) ||
      i.licences.some(l => l.toLowerCase().includes(q))
  );
};

// {licence: count}, most used first: the summary line of each group.
export const licenceSummary = items => {
  const counts = {};
  items.forEach(i => {
    const key = i.licences.join(' / ') || 'UNKNOWN';
    counts[key] = (counts[key] || 0) + 1;
  });
  return Object.entries(counts)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([licence, count]) => ({ licence, count }));
};

// "MIT: 260 · Apache-2.0: 17": the line under each group's title.
export const summaryLine = items =>
  licenceSummary(items)
    .map(s => `${s.licence}: ${s.count}`)
    .join(' · ');

// "vue 3.5.0 · MIT": one component's line.
export const itemLabel = i =>
  [[i.name, i.version].filter(Boolean).join(' '), i.licences.join(' / ')]
    .filter(Boolean)
    .join(' · ');
