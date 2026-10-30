import {
  toLimit,
  saveQuotas,
  quotaRows,
  getQuotas,
  formatCount,
} from '../tolzarUsage';

describe('tolzarUsage', () => {
  beforeEach(() => {
    window.axios = {
      get: vi.fn().mockResolvedValue({ data: { ok: true } }),
      post: vi.fn().mockResolvedValue({ data: { ok: true } }),
    };
  });

  it('treats an empty limit as unlimited', () => {
    expect(toLimit('')).toBeNull();
    expect(toLimit(null)).toBeNull();
    expect(toLimit('250.7')).toBe(250);
    expect(toLimit(-3)).toBe(0);
  });

  it('reads and saves quotas through the proxy', async () => {
    await getQuotas(5);
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/5/tolzar/brain/quotas',
      { params: {} }
    );
    await saveQuotas(5, { daily_calls: '500', monthly_tokens: '' });
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/5/tolzar/brain/quotas',
      { daily_calls: 500, monthly_tokens: null }
    );
  });

  it('formats counts in the viewer\'s language and shows no limit as ∞', () => {
    expect(formatCount(1234, 'en')).toBe('1,234');
    expect(formatCount(1234, 'de')).toBe('1.234');
    expect(formatCount(null)).toBe('∞');
    expect(formatCount(undefined)).toBe('∞');
    expect(formatCount('')).toBe('∞');
    expect(formatCount('abc')).toBe('abc');
    expect(formatCount(7, 'zz-INVALID-!!')).toBe('7');
  });

  it('shows used, limit and remaining', () => {
    const rows = quotaRows({
      quota: { daily_calls: 100, monthly_tokens: null },
      used: { calls_today: 100, tokens_month: 1234 },
      remaining: { daily_calls: 0, monthly_tokens: null },
    });
    expect(rows[0]).toEqual({
      key: 'daily_calls',
      used: 100,
      limit: 100,
      remaining: 0,
      share: 1,
      reached: true,
    });
    expect(rows[1]).toEqual({
      key: 'monthly_tokens',
      used: 1234,
      limit: null,
      remaining: null,
      share: null,
      reached: false,
    });
    expect(quotaRows(null).map(r => r.used)).toEqual([0, 0]);
  });
});
