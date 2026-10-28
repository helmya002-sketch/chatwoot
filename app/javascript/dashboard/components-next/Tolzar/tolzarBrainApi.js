// Tolzar: the one door from the UI to the brain, through the admin proxy
// (Api::V1::Accounts::TolzarController#brain_get / #brain_post, allow-listed features).
// The proxy adds the workspace id itself; the UI never sends one.
export const brainUrl = (accountId, feature) =>
  `/api/v1/accounts/${accountId}/tolzar/brain/${feature}`;

// A refused or invalid request (403 owner_only, brain 400 detail) comes back as data so the
// page can say why; only a network failure throws.
const answer = request =>
  request
    .then(r => r.data)
    .catch(e => {
      if (e && e.response && e.response.data) return e.response.data;
      throw e;
    });

export const brainGet = (accountId, feature, params = {}) =>
  answer(window.axios.get(brainUrl(accountId, feature), { params }));

export const brainPost = (accountId, feature, body = {}) =>
  answer(window.axios.post(brainUrl(accountId, feature), body));

// What went wrong, as a list of plain messages: the proxy's { ok: false, error } or the
// brain's FastAPI { detail } (a string, a list of strings, or validation objects).
export const brainErrors = data => {
  if (!data) return [];
  if (data.detail !== undefined) {
    const d = Array.isArray(data.detail) ? data.detail : [data.detail];
    return d.map(x => (typeof x === 'string' ? x : x.msg || JSON.stringify(x)));
  }
  if (data.ok === false) return [data.error || 'error'];
  return [];
};

export const isOwnerOnly = data => !!data && data.error === 'owner_only';

// Secrets are never typed into Tolzar: settings hold env var NAMES. One row per named
// field: which variable the server should have, and whether the brain sees it.
export const envRows = (settings, present, fields) =>
  fields
    .filter(f => settings && settings[f])
    .map(f => ({
      field: f,
      name: settings[f],
      present: !!(present && present[f]),
    }));
