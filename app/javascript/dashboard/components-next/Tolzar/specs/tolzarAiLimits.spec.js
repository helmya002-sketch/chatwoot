import {
  parsePerks,
  allowedDiscount,
  saveNegotiation,
  saveAgentTeams,
  teamRows,
  teamsFromRows,
  runTuning,
  decideTuning,
} from '../tolzarAiLimits';

const url = f => `/api/v1/accounts/4/tolzar/brain/${f}`;

describe('tolzarAiLimits', () => {
  beforeEach(() => {
    window.axios = {
      get: vi.fn().mockResolvedValue({ data: { ok: true } }),
      post: vi.fn().mockResolvedValue({ data: { ok: true } }),
    };
  });

  it('reads perks one per line', () => {
    expect(parsePerks('free pickup\n\n  photos  ')).toEqual([
      'free pickup',
      'photos',
    ]);
    expect(parsePerks(['a', ' '])).toEqual(['a']);
  });

  it('computes the allowed discount like the brain guard', () => {
    expect(
      allowedDiscount({ enabled: false, floor_pct: 80, max_discount_pct: 30 })
    ).toBe(0);
    expect(
      allowedDiscount({ enabled: true, floor_pct: 90, max_discount_pct: 15 })
    ).toBe(10);
    expect(
      allowedDiscount({ enabled: true, floor_pct: 80, max_discount_pct: 5 })
    ).toBe(5);
  });

  it('saves negotiation limits as numbers', async () => {
    await saveNegotiation(4, {
      enabled: true,
      floor_pct: '90',
      max_discount_pct: '10',
      perks: 'free pickup',
    });
    expect(window.axios.post).toHaveBeenCalledWith(url('negotiation'), {
      enabled: true,
      floor_pct: 90,
      max_discount_pct: 10,
      perks: ['free pickup'],
    });
  });

  it('maps teams to agents ("" keeps the default agent)', async () => {
    const rows = teamRows(
      [
        { id: 1, name: 'Sales' },
        { id: 2, name: 'Support' },
      ],
      { 1: 'seller' }
    );
    expect(rows).toEqual([
      { id: '1', name: 'Sales', agent: 'seller' },
      { id: '2', name: 'Support', agent: '' },
    ]);
    await saveAgentTeams(4, teamsFromRows(rows));
    expect(window.axios.post).toHaveBeenCalledWith(url('agent_teams'), {
      teams: { 1: 'seller', 2: '' },
    });
  });

  it('runs and decides tuning proposals', async () => {
    await runTuning(4);
    expect(window.axios.post).toHaveBeenLastCalledWith(url('tuning_run'), {});
    await decideTuning(4, '2026-10-28', 'approved', 2);
    expect(window.axios.post).toHaveBeenLastCalledWith(url('tuning_decide'), {
      date: '2026-10-28',
      status: 'approved',
      edit: 2,
    });
    await decideTuning(4, '2026-10-28', 'rejected');
    expect(window.axios.post).toHaveBeenLastCalledWith(url('tuning_decide'), {
      date: '2026-10-28',
      status: 'rejected',
    });
  });
});
