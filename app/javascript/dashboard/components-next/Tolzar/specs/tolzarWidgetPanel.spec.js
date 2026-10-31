import { describe, it, expect } from 'vitest';
import { whiteContrast, contrastLevel } from '../settings/tolzarWidgetPanel';

describe('tolzarWidgetPanel', () => {
  it('measures white-text contrast on the widget colour (WCAG)', () => {
    expect(whiteContrast('#3E63DD')).toBeCloseTo(5.2, 1);
    expect(contrastLevel('#3E63DD')).toBe('aa');
    expect(contrastLevel('#12B886')).toBe('fail');
    expect(contrastLevel('#E5484D')).toBe('large');
    expect(contrastLevel('red')).toBe('fail');
    expect(whiteContrast('#000000')).toBe(21);
  });
});
