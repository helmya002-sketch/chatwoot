// Tolzar "Plan and usage": the Business plan's pooled AI-reply allowance (billing groups, up to 5
// workspaces share one monthly allowance). Through the admin proxy
// (Api::V1::Accounts::TolzarController, TolzarBillingGroupActions); Rails lets only an Owner of every
// member workspace change a group. The proxy adds the workspace id itself.
export const MAX_MEMBERS = 5;

export const billingUrl = (accountId, suffix = '') =>
  `/api/v1/accounts/${accountId}/tolzar/billing_group${suffix}`;

// A refusal (403 owner_only, 409, 422) comes back as data so the page can say why; only a network
// failure throws.
const answer = request =>
  request
    .then(r => r.data)
    .catch(e => {
      if (e && e.response && e.response.data) return e.response.data;
      throw e;
    });

// Empty = no ceiling (null); otherwise a positive whole number.
export const toAllowance = v => {
  if (v === null || v === undefined || String(v).trim() === '') return null;
  const n = Math.floor(Number(v));
  return Number.isFinite(n) && n > 0 ? n : null;
};

export const memberIds = ids => [
  ...new Set((ids || []).map(Number).filter(n => Number.isInteger(n) && n > 0)),
];

export const getBillingGroup = accountId =>
  answer(window.axios.get(billingUrl(accountId)));

export const saveBillingGroup = (accountId, form) =>
  answer(
    window.axios.post(billingUrl(accountId), {
      members: memberIds(form && form.members),
      monthly_ai_replies: toAllowance(form && form.monthly_ai_replies),
      tz: String((form && form.tz) || 'UTC').trim(),
      enabled: !!(form && form.enabled),
    })
  );

export const deleteBillingGroup = accountId =>
  answer(window.axios.post(billingUrl(accountId, '/delete'), {}));

// The pooled meter: used / allowance, what is left and the share used (null when unlimited).
export const poolMeter = status => {
  const used = Number((status && status.used) || 0);
  const limit = status && status.group ? status.group.monthly_ai_replies : null;
  const limited = limit !== null && limit !== undefined;
  return {
    used,
    limit: limited ? limit : null,
    remaining: limited ? Math.max(0, limit - used) : null,
    share: limited && limit > 0 ? Math.min(1, used / limit) : null,
    reached: limited && used >= limit,
  };
};

// The day counting started, as YYYY-MM-DD, or null (not counting yet, or the brain does not say).
export const countingSince = status => {
  const v = status && status.counting_since;
  if (!v) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
};

// The i18n key (under TOLZAR_SETTINGS.BILLING.ERRORS) for a refusal, or '' when it went through.
const KNOWN_ERRORS = [
  'owner_only',
  'too_many_members',
  'in_another_group',
  'must_include_this_workspace',
  'invalid_settings',
  'not_found',
  'brain_unreachable',
];
export const billingErrorKey = data => {
  if (!data || data.ok === true) return '';
  if (data.ok === false && KNOWN_ERRORS.includes(data.error)) return data.error;
  return 'other';
};
