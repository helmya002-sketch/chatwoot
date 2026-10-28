// Tolzar: the workspace's industry pack, for the contact pane and table. The core UI shows only
// generic fields (place, group size, language, phone, e-mail); a pack adds its own contact
// attributes with their labels (GET /workspace/pack in the brain, through the read-only
// Api::V1::Accounts::TolzarController#pack_view, open to every member of the workspace).
// A workspace without a pack, or a brain that is not reachable, shows the generic core only.

const cache = new Map();

export const packUrl = accountId => `/api/v1/accounts/${accountId}/tolzar/pack`;

export const EMPTY_PACK = Object.freeze({ pack: null, fields: [] });

const clean = data => {
  const fields = Array.isArray(data && data.fields) ? data.fields : [];
  return {
    pack: (data && data.pack) || null,
    fields: fields
      .filter(f => f && typeof f.key === 'string' && f.key)
      .map(f => ({
        key: f.key,
        kind: typeof f.kind === 'string' ? f.kind : 'text',
        label: f.label && typeof f.label === 'object' ? f.label : {},
      })),
  };
};

// One request per workspace per page load; a failure is not cached (the next view retries).
export const fetchPack = accountId => {
  if (!accountId) return Promise.resolve(EMPTY_PACK);
  if (!cache.has(accountId)) {
    const request = window.axios
      .get(packUrl(accountId))
      .then(r => clean(r.data))
      .catch(() => {
        cache.delete(accountId);
        return EMPTY_PACK;
      });
    cache.set(accountId, request);
  }
  return cache.get(accountId);
};

export const clearPackCache = () => cache.clear();

const KINDS = ['place', 'date', 'level', 'number', 'text'];

// The field's label in the UI language (de-DE -> de), else English, else the generic kind label.
export const fieldLabel = (field, locale, t) => {
  const lang = String(locale || 'en')
    .split(/[-_]/)[0]
    .toLowerCase();
  const own = field.label[lang] || field.label.en;
  if (own) return own;
  const kind = KINDS.includes(field.kind) ? field.kind : 'text';
  return t(`TOLZAR_CONTACTS.PANE.KIND.${kind.toUpperCase()}`);
};

// The contact's place for the table: the pack's own place detail first, then the core place.
export const contactPlace = (pack, attrs, add = {}) => {
  const own = (pack.fields || [])
    .filter(f => f.kind === 'place')
    .map(f => attrs[f.key])
    .find(v => v !== undefined && v !== null && v !== '');
  return own || attrs.location || add.city || '';
};

// Pack rows for the pane: [label, value] pairs, the place-kind ones apart (they go before the
// core place, the rest after it).
export const packRows = (pack, attrs, locale, t) => {
  const row = f => [fieldLabel(f, locale, t), attrs[f.key]];
  const fields = pack.fields || [];
  return {
    places: fields.filter(f => f.kind === 'place').map(row),
    others: fields.filter(f => f.kind !== 'place').map(row),
  };
};
