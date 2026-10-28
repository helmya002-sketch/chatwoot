// Tolzar workspace credentials (brain vault.py): write-only fields on the settings POSTs.
// The brain stores them encrypted and only ever answers { field: { set, last4, source } }.
// A key is sent only when the user typed one; "" or a missing field keeps the stored key;
// `clear_credentials: [field]` removes it. Nothing here is ever pre-filled from a GET.
import { brainGet, brainPost } from './tolzarBrainApi';

// The write-only part of a settings POST: typed keys for the allowed fields, plus the fields to clear.
export const credentialBody = (typed, fields, clear = []) => {
  const out = {};
  fields.forEach(f => {
    const v = String((typed && typed[f]) || '').trim();
    if (v) out[f] = v;
  });
  const drop = (clear || []).filter(f => fields.includes(f) && !out[f]);
  if (drop.length) out.clear_credentials = drop;
  return out;
};

// One field's status from a GET's `credentials` block: never a value, at most the last 4 characters.
export const credentialStatus = (data, field) => {
  const c = (data && data.credentials && data.credentials[field]) || {};
  return {
    set: !!c.set,
    last4: String(c.last4 || ''),
    source: c.source || null,
  };
};

// ---- Price feed key, per AI agent (plugins/price_credentials.py) --------------------------
export const getPriceKey = (accountId, agentId) =>
  brainGet(accountId, 'credentials_prices', { agent_id: agentId });
export const savePriceKey = (accountId, agentId, apiKey) =>
  brainPost(accountId, 'credentials_prices', {
    agent_id: agentId,
    ...credentialBody({ api_key: apiKey }, ['api_key']),
  });
export const clearPriceKey = (accountId, agentId) =>
  brainPost(accountId, 'credentials_prices', {
    agent_id: agentId,
    clear_credentials: ['api_key'],
  });
