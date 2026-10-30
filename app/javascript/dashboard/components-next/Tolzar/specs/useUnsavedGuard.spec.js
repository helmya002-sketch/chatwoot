import { describe, it, expect } from 'vitest';
import { snapshot } from '../useUnsavedGuard';

describe('snapshot', () => {
  it('ignores key order and undefined values', () => {
    expect(snapshot({ a: 1, b: [1, { d: 2, c: 3 }] })).toBe(
      snapshot({ b: [1, { c: 3, d: 2 }], a: 1 })
    );
    expect(snapshot({ a: 1, b: undefined })).toBe(snapshot({ a: 1 }));
  });

  it('differs when a value changes', () => {
    expect(snapshot({ a: 1 })).not.toBe(snapshot({ a: 2 }));
    expect(snapshot(null)).toBe('null');
  });
});
