// Tolzar "Usage": model quotas per workspace (plugins/quotas.py). Empty = unlimited.
import { brainGet, brainPost } from './tolzarBrainApi';

export const QUOTA_LIMITS = ['daily_calls', 'monthly_tokens'];
const USED = { daily_calls: 'calls_today', monthly_tokens: 'tokens_month' };

export const toLimit = v => {
  if (v === null || v === undefined || String(v).trim() === '') return null;
  return Math.max(0, Math.floor(Number(v)));
};

// A count in the viewer's language ("1,234" / "1.234"); null or undefined is "no limit" (∞).
export const formatCount = (v, locale = 'en') => {
  if (v === null || v === undefined || v === '') return '∞';
  const n = Number(v);
  if (!Number.isFinite(n)) return String(v);
  try {
    return new Intl.NumberFormat(locale || undefined).format(n);
  } catch {
    return new Intl.NumberFormat('en').format(n);
  }
};

export const getQuotas = accountId => brainGet(accountId, 'quotas');
export const saveQuotas = (accountId, limits) =>
  brainPost(
    accountId,
    'quotas',
    Object.fromEntries(QUOTA_LIMITS.map(k => [k, toLimit(limits && limits[k])]))
  );

// Used / limit / remaining per limit, with the share used (null when unlimited).
export const quotaRows = status =>
  QUOTA_LIMITS.map(k => {
    const limit = status && status.quota ? status.quota[k] : null;
    const used = (status && status.used && status.used[USED[k]]) || 0;
    const remaining = status && status.remaining ? status.remaining[k] : null;
    const limited = limit !== null && limit !== undefined;
    return {
      key: k,
      used,
      limit: limited ? limit : null,
      remaining: limited ? remaining : null,
      share: limited && limit > 0 ? Math.min(1, used / limit) : null,
      reached: limited && used >= limit,
    };
  });
