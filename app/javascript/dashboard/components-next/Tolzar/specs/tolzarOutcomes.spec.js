import { describe, it, expect } from 'vitest';
import { outcomeFor, reasonsFor, reasonAttributes } from '../tolzarOutcomes';

describe('tolzarOutcomes', () => {
  it('knows won and lost stages', () => {
    expect(outcomeFor('Signed', 'Signed', 'Declined')).toBe('won');
    expect(outcomeFor('Declined', 'Signed', 'Declined')).toBe('lost');
    expect(outcomeFor('Active', 'Signed', 'Declined')).toBeNull();
    expect(outcomeFor(undefined, undefined, 'Declined')).toBeNull();
  });

  it('offers reasons per outcome and stores only known ones', () => {
    expect(reasonsFor('won')).toContain('speed');
    expect(reasonsFor('lost')).toContain('competitor');
    expect(reasonsFor(null)).toEqual([]);
    const at = new Date('2026-11-02T10:00:00Z');
    expect(reasonAttributes('lost', 'timing', at)).toEqual({
      tolzar_outcome_reason: 'lost:timing',
      tolzar_outcome_reason_at: '2026-11-02T10:00:00.000Z',
    });
    expect(reasonAttributes('won', 'timing', at)).toBeNull();
  });
});
