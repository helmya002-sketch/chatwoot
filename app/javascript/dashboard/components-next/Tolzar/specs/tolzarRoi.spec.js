import { getRoi, roiTiles, roiFacts, workingHoursLabel } from '../tolzarRoi';

const shadow = {
  first_reply: {
    compared: 12,
    staff_median_s: 3000,
    staff_p90_s: 9000,
    tolzar_median_s: 41,
    tolzar_p90_s: 70,
    would_be: true,
  },
  ai_handled: { decisions: 40, ai: 30, guard_replaced: 6, share: 0.75 },
  off_hours: { leads: 20, off_hours: 9, share: 0.45 },
  campaigns: [{ campaign: 'Autumn', conversations: 8, codes: 2 }],
  won_contacts: 3,
  mode_note: 'Tolzar is in Shadow here',
};

describe('tolzarRoi', () => {
  beforeEach(() => {
    window.axios = { get: vi.fn().mockResolvedValue({ data: { ok: true } }) };
  });

  it('reads /roi for the chosen window', async () => {
    await getRoi(6, 90);
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/6/tolzar/brain/roi',
      { params: { days: 90 } }
    );
  });

  it('marks Tolzar values as would-be in Shadow, never the team ones', () => {
    const tiles = Object.fromEntries(roiTiles(shadow).map(t => [t.key, t]));
    expect(tiles.tolzar_first_reply).toMatchObject({
      value: 41,
      wouldBe: true,
      kind: 'seconds',
    });
    expect(tiles.ai_share).toMatchObject({ value: 0.75, wouldBe: true });
    expect(tiles.staff_first_reply.wouldBe).toBe(false);
    expect(tiles.off_hours.sub).toEqual({ n: 9, of: 20 });
    const live = roiTiles({
      ...shadow,
      first_reply: { ...shadow.first_reply, would_be: false },
    });
    expect(live.some(t => t.wouldBe)).toBe(false);
    expect(roiTiles({})).toEqual([]);
  });

  it('shows working hours as HH:MM without seconds', () => {
    expect(workingHoursLabel('09:00:00-19:00:00', 'en')).toBe('09:00–19:00');
    expect(workingHoursLabel('9:30-17:05', 'de')).toBe('09:30–17:05');
    expect(workingHoursLabel('08:00:00-18:00:00', 'fr')).toBe('08:00–18:00');
    expect(workingHoursLabel('08:00:00-18:00:00', 'pt_BR')).toBe('08:00–18:00');
    expect(workingHoursLabel('08:00:00-18:00:00', 'not a locale!')).toBe(
      '08:00–18:00'
    );
    expect(workingHoursLabel('always', 'en')).toBe('always');
    expect(workingHoursLabel(undefined)).toBe('');
  });

  it('builds the plain-language summary in the brain order', () => {
    expect(roiFacts(shadow).map(f => f.key)).toEqual([
      'FIRST_REPLY_WOULD',
      'AI_SHARE',
      'OFF_HOURS',
      'TOP_CAMPAIGN',
      'WON',
      'SHADOW_NOTE',
    ]);
    expect(roiFacts(shadow)[1].params).toEqual({ share: 75, n: 40, guards: 6 });
    const empty = roiFacts({
      first_reply: { compared: 0 },
      ai_handled: {},
      off_hours: {},
      campaigns: [],
      won_contacts: null,
      mode_note: '',
    });
    expect(empty.map(f => f.key)).toEqual(['NO_FIRST_REPLY']);
  });
});
