import {
  EMPTY_SCOREBOARD,
  OTHER_STAGES,
  delta,
  downloadCsv,
  duration,
  euro,
  isoDate,
  newContacts,
  normalizeScoreboard,
  pct,
  rangeFor,
  stageCounts,
  stageValue,
  toCsv,
  weeklyNewContacts,
} from '../tolzarReportsData';
import ContactAPI from 'dashboard/api/contacts';
import {
  applyPipelineStages,
  loadStageAttributes,
} from 'dashboard/components-next/Tolzar/tolzarStages';

vi.mock('dashboard/api/contacts', () => ({
  default: { filter: vi.fn(), get: vi.fn() },
}));
vi.mock('dashboard/api/attributes', () => ({
  default: {
    getAttributesByModel: vi.fn().mockResolvedValue({
      data: [
        {
          attribute_model: 'contact_attribute',
          attribute_key: 'lifecycle_stage',
        },
      ],
    }),
  },
}));

describe('tolzarReportsData', () => {
  it('formats durations the way people read them', () => {
    expect(duration(null)).toBe('—');
    expect(duration(42)).toBe('42 s');
    expect(duration(3001)).toBe('50 min');
    expect(duration(31697)).toBe('8 h 48 min');
    expect(duration(2 * 86400 + 3600)).toBe('2 d 1 h');
  });

  it('formats money and percentages', () => {
    applyPipelineStages({ deal_currency: 'EUR' });
    expect(euro(640)).toMatch(/^€\s?640$/);
    expect(euro(38400)).toMatch(/^€\s?38\.4K$/i);
    applyPipelineStages({});
    expect(euro(640)).toBe('640'); // no currency set: no symbol
    expect(pct(0.885, 1)).toBe('88.5%');
    expect(pct(null)).toBe('—');
  });

  it('only reports a change when there is something to compare with', () => {
    expect(delta(12, 0)).toBeNull();
    expect(delta(12, null)).toBeNull();
    expect(delta(15, 10)).toBeCloseTo(0.5);
  });

  it('builds the current and previous windows', () => {
    const now = Date.UTC(2026, 9, 27, 12);
    const r = rangeFor(30, now);
    expect(r.until - r.since).toBe(30 * 86400);
    expect(r.since - r.prevSince).toBe(30 * 86400);
    expect(isoDate(r.until)).toBe('2026-10-27');
  });
});

describe('tolzarReportsData contact queries', () => {
  beforeEach(async () => {
    applyPipelineStages({});
    await loadStageAttributes(1);
    ContactAPI.filter.mockReset();
    ContactAPI.get.mockReset();
  });

  it('counts each stage and puts contacts in unlisted stages under __other', async () => {
    ContactAPI.filter.mockImplementation((page, sort, query) => {
      const stage = query.payload.find(c => c.filter_operator === 'equal_to')
        .values[0];
      const n = { 'New Lead': 4, Active: 3, 'Customer Won': 2 }[stage] || 0;
      return Promise.resolve({ data: { meta: { count: n }, payload: [] } });
    });
    ContactAPI.get.mockResolvedValue({ data: { meta: { count: 12 } } });
    const out = await stageCounts();
    expect(out['New Lead']).toBe(4);
    expect(out['Customer Lost']).toBe(0);
    expect(out[OTHER_STAGES]).toBe(3); // 12 - (4 + 3 + 2)
    expect(OTHER_STAGES).toBe('__other');
  });

  it('never reports a negative __other when the stage sums pass the total', async () => {
    ContactAPI.filter.mockResolvedValue({
      data: { meta: { count: 5 }, payload: [] },
    });
    ContactAPI.get.mockResolvedValue({ data: { meta: { count: 3 } } });
    expect((await stageCounts())[OTHER_STAGES]).toBe(0);
  });

  it('bounds new contacts by created_at days, open-ended when no end is given', async () => {
    ContactAPI.filter.mockResolvedValue({
      data: { meta: { count: 7 }, payload: [] },
    });
    const since = Date.UTC(2026, 9, 1) / 1000;
    const until = Date.UTC(2026, 9, 8) / 1000;
    expect(await newContacts(since, until)).toBe(7);
    const [, , q] = ContactAPI.filter.mock.calls[0];
    expect(q.payload).toEqual([
      expect.objectContaining({
        attribute_key: 'created_at',
        filter_operator: 'is_greater_than',
        values: ['2026-10-01'],
        query_operator: 'and',
      }),
      expect.objectContaining({
        filter_operator: 'is_less_than',
        values: ['2026-10-08'],
        query_operator: null,
      }),
    ]);
    await newContacts(since);
    const [, , open] = ContactAPI.filter.mock.calls[1];
    expect(open.payload).toHaveLength(1);
    expect(open.payload[0].query_operator).toBeNull();
  });

  it('builds five 7-day weeks ending now, the last one open-ended', async () => {
    ContactAPI.filter.mockResolvedValue({
      data: { meta: { count: 1 }, payload: [] },
    });
    const now = Date.UTC(2026, 9, 29, 12);
    const weeks = await weeklyNewContacts(5, now);
    expect(weeks).toHaveLength(5);
    expect(weeks[4].week).toBe('2026-10-22');
    expect(weeks[0].week).toBe('2026-09-24');
    const last = ContactAPI.filter.mock.calls[4][2].payload;
    expect(last).toHaveLength(1);
  });

  it('sums the deal value over pages and says when it stopped at the cap', async () => {
    const page = n => ({
      data: {
        meta: { count: 45 },
        payload: [...Array(15)].map((_, i) => ({
          custom_attributes: { deal_value: n * 100 + i },
        })),
      },
    });
    ContactAPI.filter.mockImplementation(p => Promise.resolve(page(p)));
    const full = await stageValue('Active');
    expect(full.count).toBe(45);
    expect(full.capped).toBe(false);
    expect(ContactAPI.filter).toHaveBeenCalledTimes(3);
    expect(full.total).toBe(
      [1, 2, 3].reduce((s, n) => s + 15 * n * 100 + 105, 0)
    );
    ContactAPI.filter.mockClear();
    const capped = await stageValue('Active', 2);
    expect(capped.capped).toBe(true);
    expect(ContactAPI.filter).toHaveBeenCalledTimes(2);
    expect(capped.total).toBe(full.total - (3 * 1500 + 105));
  });

  it('stops on an empty page', async () => {
    ContactAPI.filter.mockResolvedValue({
      data: { meta: { count: 30 }, payload: [] },
    });
    const v = await stageValue('Active');
    expect(v).toEqual({ stage: 'Active', total: 0, count: 30, capped: false });
    expect(ContactAPI.filter).toHaveBeenCalledTimes(1);
  });
});

describe('normalizeScoreboard', () => {
  it('fills every block the page reads', () => {
    const sb = normalizeScoreboard(null);
    expect(sb).toEqual(EMPTY_SCOREBOARD);
    expect(normalizeScoreboard({ ok: true }).checks).toEqual([]);
    expect(normalizeScoreboard({ ok: true }).guards.price_guard).toBe(0);
    expect(normalizeScoreboard({ ok: true }).disagreements).toEqual([]);
    expect(
      normalizeScoreboard({ ok: true, guards: null }).guards.output_policy
    ).toEqual({});
  });

  it('keeps the brain values and coerces the odd ones', () => {
    const sb = normalizeScoreboard({
      ok: true,
      measured: '12',
      passing: 2,
      checks: [
        { key: 'agreement', value: 0.9, target: 0.85, pass: true },
        {
          key: 'price_leaks',
          value: null,
          target: 0,
          pass: null,
          higher_is_better: false,
        },
        { value: 1 },
        null,
      ],
      guards: { price_guard: 3, output_policy: { a: 1, b: 2 } },
      disagreements: [{ conversation_id: 9 }, {}],
      daily: [{ day: '2026-10-01', agreement: 1 }, { agreement: 0 }],
      by_model: [{ model: 'm1' }, { scored: 1 }],
      model_latest: 'm1',
      extra: 'kept',
    });
    expect(sb.measured).toBe(12);
    expect(sb.checks).toHaveLength(2);
    expect(sb.checks[0]).toEqual({
      key: 'agreement',
      value: 0.9,
      target: 0.85,
      pass: true,
      higher_is_better: true,
    });
    expect(sb.checks[1]).toMatchObject({
      value: null,
      higher_is_better: false,
    });
    expect(sb.guards).toEqual({
      price_guard: 3,
      llm_errors: 0,
      output_policy: { a: 1, b: 2 },
    });
    expect(sb.disagreements).toEqual([{ conversation_id: 9 }]);
    expect(sb.daily).toHaveLength(1);
    expect(sb.by_model).toEqual([{ model: 'm1' }]);
    expect(sb.extra).toBe('kept');
    expect(normalizeScoreboard({ ok: 'yes' }).ok).toBe(false);
  });
});

describe('CSV export', () => {
  it('quotes only what needs quoting, doubles quotes and starts with a BOM', () => {
    const csv = toCsv(
      ['Stage', 'Contacts'],
      [
        ['New', 4],
        ['Offer, sent', 2],
        ['He said "hi"', null],
        ['two\nlines', undefined],
      ]
    );
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv.slice(1)).toBe(
      'Stage,Contacts\r\nNew,4\r\n"Offer, sent",2\r\n"He said ""hi""",\r\n"two\nlines",\r\n'
    );
  });

  it('hands the browser a .csv file with a safe name', () => {
    const a = { click: vi.fn(), style: {} };
    const doc = {
      createElement: vi.fn(() => a),
      body: { appendChild: vi.fn(), removeChild: vi.fn() },
    };
    const win = {
      URL: {
        createObjectURL: vi.fn(() => 'blob:x'),
        revokeObjectURL: vi.fn(),
      },
    };
    const text = downloadCsv('Team members / 2026', ['a'], [[1]], {
      doc,
      win,
    });
    expect(a.download).toBe('Team-members-2026.csv');
    expect(a.href).toBe('blob:x');
    expect(a.click).toHaveBeenCalled();
    expect(doc.body.removeChild).toHaveBeenCalledWith(a);
    expect(win.URL.revokeObjectURL).toHaveBeenCalledWith('blob:x');
    expect(text).toContain('a\r\n1\r\n');
    // No document (a test, a worker): the text alone comes back.
    expect(downloadCsv('x', ['a'], [], { doc: null, win: null })).toContain(
      'a'
    );
  });
});
