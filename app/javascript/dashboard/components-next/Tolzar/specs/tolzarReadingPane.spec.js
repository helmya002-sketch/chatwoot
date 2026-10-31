import { describe, it, expect } from 'vitest';
import { checkChips, sourcesLine } from '../tolzarReadingPane';

describe('tolzarReadingPane', () => {
  it('shows the price, policy, language and grounding checks in a fixed order', () => {
    const decision = {
      checks: [
        { check: 'language', passed: true },
        { check: 'price_guard', passed: false },
        { check: 'consistency', passed: true },
      ],
    };
    expect(checkChips(decision)).toEqual([
      { check: 'price_guard', passed: false },
      { check: 'language', passed: true },
    ]);
    expect(checkChips(null)).toEqual([]);
  });

  it('lists up to three sources without duplicates', () => {
    const d = {
      based_on: [
        { title: 'Price list' },
        { title: 'Price list' },
        { snippet: 'FAQ: delivery' },
        { title: 'Terms' },
        { title: 'Hours' },
      ],
    };
    expect(sourcesLine(d)).toBe('Price list, FAQ: delivery, Terms +1');
    expect(sourcesLine({})).toBe('');
  });
});
