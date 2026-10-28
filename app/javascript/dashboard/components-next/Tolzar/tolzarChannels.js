// Tolzar "Channels": SMS fallback, CRM sync, Commerce (plugins/sms.py, crm_sync.py, commerce.py).
// Everything is Shadow / dry run: Tolzar shows what it WOULD send and never sends.
import { brainGet, brainPost, envRows } from './tolzarBrainApi';

export const SMS_PROVIDERS = ['twilio', 'unifonic', 'vonage'];
export const CRM_PROVIDERS = ['hubspot', 'zoho', 'pipedrive'];
export const CRM_DIRECTIONS = ['to_crm', 'from_crm', 'both'];
export const SHOP_PROVIDERS = ['shopify', 'woocommerce', 'salla', 'zid'];

// Which env-name fields a provider uses (mirrors NEEDS in the brain plugins).
export const SMS_ENV = {
  twilio: ['account_sid_env', 'key_env'],
  unifonic: ['key_env'],
  vonage: ['account_sid_env', 'key_env'],
};
export const SHOP_ENV = {
  shopify: ['key_env'],
  woocommerce: ['key_env', 'secret_env'],
  salla: ['key_env'],
  zid: ['key_env', 'secret_env'],
};

// ---- SMS --------------------------------------------------------------------------------
export const getSms = accountId => brainGet(accountId, 'sms');
// Shadow is the only mode the UI ever sends.
export const saveSms = (accountId, s) =>
  brainPost(accountId, 'sms', {
    provider: s.provider,
    from: s.from,
    key_env: s.key_env,
    account_sid_env: s.account_sid_env,
    enabled: !!s.enabled,
    mode: 'shadow',
  });
export const previewSms = (accountId, to, text) =>
  brainPost(accountId, 'sms_preview', { to, text });
export const smsEnvRows = data =>
  envRows(data && data.settings, data && data.env_present, [
    'account_sid_env',
    'key_env',
  ]);

// ---- CRM sync ---------------------------------------------------------------------------
export const getCrm = accountId => brainGet(accountId, 'crm_sync');
export const saveCrm = (accountId, s) =>
  brainPost(accountId, 'crm_sync', {
    provider: s.provider,
    key_env: s.key_env,
    direction: s.direction,
    field_map: s.field_map,
    stage_map: s.stage_map || {},
    read_crm: !!s.read_crm,
    enabled: !!s.enabled,
    ...(s.provider === 'zoho' && s.api_domain
      ? { api_domain: s.api_domain }
      : {}),
  });
export const crmRuns = accountId => brainGet(accountId, 'crm_sync_runs');
export const previewCrm = (accountId, contactId) =>
  brainPost(accountId, 'crm_sync_preview', { contact_id: Number(contactId) });
export const crmEnvRows = data =>
  envRows(data && data.settings, { key_env: !!(data && data.key_present) }, [
    'key_env',
  ]);

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
export const saveCommerce = (accountId, s) =>
  brainPost(accountId, 'commerce', {
    provider: s.provider,
    shop_domain: s.shop_domain,
    currency: s.currency,
    key_env: s.key_env,
    secret_env: s.secret_env,
    agent_id: s.agent_id,
    catalogue_auto: !!s.catalogue_auto,
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
export const commerceEnvRows = data =>
  envRows(data && data.settings, data && data.env_present, [
    'key_env',
    'secret_env',
  ]);
