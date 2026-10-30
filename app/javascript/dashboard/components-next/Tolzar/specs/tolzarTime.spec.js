import { describe, it, expect } from 'vitest';
import { fmtAt, fmtDay, fmtClock, ago, duration } from '../tolzarTime';

describe('tolzarTime', () => {
  const iso = '2026-10-30T14:05:00Z';

  it('formats a full timestamp in the given locale and never returns the raw ISO slice', () => {
    const en = fmtAt(iso, 'en');
    expect(en).toContain('2026');
    expect(en).not.toContain('T14');
    expect(fmtAt(iso, 'de')).toContain('2026');
  });

  it('returns an empty string for empty or invalid input', () => {
    expect(fmtAt('')).toBe('');
    expect(fmtAt(null)).toBe('');
    expect(fmtAt('not a date')).toBe('');
    expect(fmtDay(undefined)).toBe('');
    expect(fmtClock('x')).toBe('');
  });

  it('falls back to English on an unknown locale instead of throwing', () => {
    expect(fmtAt(iso, 'zz-INVALID-!!')).toContain('2026');
  });

  it('gives a localised relative time with an injectable clock', () => {
    const now = Date.parse('2026-10-30T14:08:00Z');
    expect(ago(iso, 'en', now)).toBe('3 minutes ago');
    expect(ago('2026-11-01T14:05:00Z', 'en', now)).toBe('in 2 days');
    expect(ago('2026-10-30T14:07:50Z', 'en', now)).toBe('now');
    expect(ago(iso, 'de', now)).toMatch(/Minuten/);
  });

  it('formats durations with Intl units', () => {
    expect(duration(40, 'en')).toBe('40 sec');
    expect(duration(240, 'en')).toBe('4 min');
    expect(duration(4800, 'en')).toBe('1 hr 20 min');
    expect(duration(2 * 86400, 'en')).toBe('2 days');
    expect(duration(-1)).toBe('');
    expect(duration('abc')).toBe('');
  });
});
