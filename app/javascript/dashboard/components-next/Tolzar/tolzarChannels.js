// Tolzar "Channels": SMS fallback, CRM sync, Commerce (plugins/sms.py, crm_sync.py, commerce.py).
// Everything is Shadow / dry run: Tolzar shows what it WOULD send and never sends.
import { brainGet, brainPost } from './tolzarBrainApi';
import { credentialBody } from './tolzarCredentials';

export const SMS_PROVIDERS = ['twilio', 'unifonic', 'vonage'];
export const CRM_PROVIDERS = ['hubspot', 'zoho', 'pipedrive'];
export const CRM_DIRECTIONS = ['to_crm', 'from_crm', 'both'];
export const SHOP_PROVIDERS = ['shopify', 'woocommerce', 'salla', 'zid'];
export const ORDER_LOOKUPS_DEFAULT = 200;
export const ORDER_PATTERN_MAX = 200; // MAX_PATTERN in plugins/commerce.py

// Which credential fields a provider uses (mirrors NEEDS / CRED_FIELDS in the brain plugins).
// The keys are write-only: typed here, stored encrypted by the brain, never shown again.
export const SMS_CREDS = {
  twilio: ['account_sid', 'api_key'],
  unifonic: ['api_key'],
  vonage: ['account_sid', 'api_key'],
};
export const SHOP_CREDS = {
  shopify: ['api_key'],
  woocommerce: ['api_key', 'api_secret'],
  salla: ['api_key'],
  zid: ['api_key', 'api_secret'],
};
export const CRM_CREDS = ['api_key'];
const smsFieldsOf = p => SMS_CREDS[p] || ['api_key'];
const shopFieldsOf = p => SHOP_CREDS[p] || ['api_key'];

// ---- SMS --------------------------------------------------------------------------------
export const getSms = accountId => brainGet(accountId, 'sms');
// Shadow is the only mode the UI ever sends. `keys` holds what the user typed, `clear` the
// fields to remove; only the provider's own fields are sent.
export const saveSms = (accountId, s, keys = {}, clear = []) =>
  brainPost(accountId, 'sms', {
    provider: s.provider,
    from: s.from,
    enabled: !!s.enabled,
    mode: 'shadow',
    ...credentialBody(keys, smsFieldsOf(s.provider), clear),
  });
export const previewSms = (accountId, to, text) =>
  brainPost(accountId, 'sms_preview', { to, text });

// ---- CRM sync ---------------------------------------------------------------------------
export const getCrm = accountId => brainGet(accountId, 'crm_sync');
export const saveCrm = (accountId, s, keys = {}, clear = []) =>
  brainPost(accountId, 'crm_sync', {
    provider: s.provider,
    direction: s.direction,
    field_map: s.field_map,
    stage_map: s.stage_map || {},
    read_crm: !!s.read_crm,
    enabled: !!s.enabled,
    ...(s.provider === 'zoho' && s.api_domain
      ? { api_domain: s.api_domain }
      : {}),
    ...credentialBody(keys, CRM_CREDS, clear),
  });
export const crmRuns = accountId => brainGet(accountId, 'crm_sync_runs');
export const previewCrm = (accountId, contactId) =>
  brainPost(accountId, 'crm_sync_preview', { contact_id: Number(contactId) });

// The fields each section asks for, for the current provider.
export const credentialFields = (section, provider) => {
  if (section === 'sms') return smsFieldsOf(provider);
  if (section === 'crm') return CRM_CREDS;
  return shopFieldsOf(provider);
};
// The i18n key of a field's label: per provider (Twilio auth token, Woo consumer secret, ...).
export const credentialLabelKey = (section, provider, field) =>
  `TOLZAR_SETTINGS.CHANNELS.CRED.${section === 'crm' ? 'crm' : provider}_${field}`;

// The mapping table: every Tolzar field, with the saved CRM field (placeholder: the default).
export const crmMapRows = (fields, fieldMap, defaults) =>
  (fields || []).map(f => ({
    field: f,
    crm: (fieldMap && fieldMap[f]) || '',
    placeholder: (defaults && defaults[f]) || '',
  }));
export const mapFromRows = rows =>
  Object.fromEntries(
    rows
      .filter(r => String(r.crm || '').trim())
      .map(r => [r.field, r.crm.trim()])
  );

// A dry run in one line: when, how many contacts were checked, how many would change.
export const runSummary = run => ({
  at: String((run && run.at) || '')
    .slice(0, 16)
    .replace('T', ' '),
  checked: (run && run.contacts_checked) || 0,
  changes: ((run && run.changes) || []).length,
  crmRead: !!(run && run.crm_read),
});

// ---- Commerce ---------------------------------------------------------------------------
export const getCommerce = accountId => brainGet(accountId, 'commerce');
export const saveCommerce = (accountId, s, keys = {}, clear = []) =>
  brainPost(accountId, 'commerce', {
    provider: s.provider,
    shop_domain: s.shop_domain,
    currency: s.currency,
    agent_id: s.agent_id,
    catalogue_auto: !!s.catalogue_auto,
    // "Where is my order?" in chat: opt-in (a contact's email/phone is only as trustworthy as
    // its channel). The brain validates the pattern and the daily cap and says what is wrong.
    order_chat: !!s.order_chat,
    order_pattern: String(s.order_pattern || '').trim(),
    ...(String(s.order_lookups_per_day ?? '').trim() === ''
      ? {}
      : { order_lookups_per_day: Number(s.order_lookups_per_day) }),
    ...credentialBody(keys, shopFieldsOf(s.provider), clear),
  });
export const syncCatalogue = (accountId, agentId) =>
  brainPost(
    accountId,
    'commerce_catalogue_sync',
    agentId ? { agent_id: agentId } : {}
  );
export const orderStatus = (accountId, orderNumber) =>
  brainPost(accountId, 'commerce_order_status', { order_number: orderNumber });
export const commerceTemplates = accountId =>
  brainGet(accountId, 'commerce_templates');
