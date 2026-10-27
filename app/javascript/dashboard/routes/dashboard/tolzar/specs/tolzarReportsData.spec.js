import {
  delta,
  duration,
  euro,
  isoDate,
  pct,
  rangeFor,
} from '../tolzarReportsData';

describe('tolzarReportsData', () => {
  it('formats durations the way people read them', () => {
    expect(duration(null)).toBe('—');
    expect(duration(42)).toBe('42 s');
    expect(duration(3001)).toBe('50 min');
    expect(duration(31697)).toBe('8 h 48 min');
    expect(duration(2 * 86400 + 3600)).toBe('2 d 1 h');
  });

  it('formats money and percentages', () => {
    expect(euro(640)).toBe('€640');
    expect(euro(38400)).toBe('€38.4k');
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
