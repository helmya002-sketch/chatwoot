import {
  billingUrl,
  toAllowance,
  memberIds,
  saveBillingGroup,
  deleteBillingGroup,
  getBillingGroup,
  poolMeter,
  countingSince,
  billingErrorKey,
} from '../tolzarBilling';

describe('tolzarBilling', () => {
  beforeEach(() => {
    window.axios = {
      get: vi.fn().mockResolvedValue({ data: { ok: true } }),
      post: vi.fn().mockResolvedValue({ data: { ok: true } }),
    };
  });

  it('reads an empty allowance as no ceiling', () => {
    expect(toAllowance('')).toBeNull();
    expect(toAllowance(null)).toBeNull();
    expect(toAllowance('18000')).toBe(18000);
    expect(toAllowance('0')).toBeNull();
  });

  it('keeps member ids unique and numeric', () => {
    expect(memberIds(['4', 4, 7, 'x', -1])).toEqual([4, 7]);
  });

  it('saves the group through the proxy', async () => {
    await saveBillingGroup(4, {
      members: ['4', '9'],
      monthly_ai_replies: '18000',
      tz: 'Africa/Cairo',
      enabled: true,
    });
    expect(window.axios.post).toHaveBeenCalledWith(billingUrl(4), {
      members: [4, 9],
      monthly_ai_replies: 18000,
      tz: 'Africa/Cairo',
      enabled: true,
    });
    await deleteBillingGroup(4);
    expect(window.axios.post).toHaveBeenLastCalledWith(
      '/api/v1/accounts/4/tolzar/billing_group/delete',
      {}
    );
  });

  it('returns a refusal as data', async () => {
    window.axios.get = vi.fn().mockRejectedValue({
      response: { data: { ok: false, error: 'owner_only' } },
    });
    const r = await getBillingGroup(4);
    expect(billingErrorKey(r)).toBe('owner_only');
    expect(billingErrorKey({ ok: false, error: 'weird' })).toBe('other');
    expect(billingErrorKey({ ok: true })).toBe('');
  });

  it('computes the pooled meter', () => {
    expect(poolMeter({ used: 90, group: { monthly_ai_replies: 100 } })).toEqual(
      { used: 90, limit: 100, remaining: 10, share: 0.9, reached: false }
    );
    expect(
      poolMeter({ used: 5, group: { monthly_ai_replies: null } }).limit
    ).toBeNull();
  });

  it('reads counting_since, a missing field as not counting yet', () => {
    expect(countingSince({ counting_since: '2026-11-01T08:00:00Z' })).toBe(
      '2026-11-01'
    );
    expect(countingSince({ counting_since: null })).toBeNull();
    expect(countingSince({})).toBeNull();
  });
});
