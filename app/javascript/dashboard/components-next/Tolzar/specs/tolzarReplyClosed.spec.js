import { describe, it, expect } from 'vitest';
import { closedNotice } from '../tolzarReplyClosed';

describe('tolzarReplyClosed', () => {
  it('says why per channel', () => {
    expect(closedNotice({ kind: 'meta' }).key).toBe('META_24_HOURS');
    expect(closedNotice({ kind: 'meta', humanAgent: true }).key).toBe(
      'META_7_DAYS'
    );
    expect(closedNotice({ kind: 'whatsapp' }).key).toBe('WHATSAPP');
    expect(closedNotice({ kind: 'tiktok' }).key).toBe('TIKTOK');
    expect(closedNotice({ kind: 'nope' }).key).toBe('OTHER');
  });

  it("keeps an API inbox's own message, or its hours", () => {
    expect(closedNotice({ kind: 'api', apiMessage: 'Reply in 2 h' })).toEqual({
      text: 'Reply in 2 h',
    });
    expect(closedNotice({ kind: 'api', apiHours: '12' })).toEqual({
      key: 'API_HOURS',
      params: { hours: 12 },
    });
    expect(closedNotice({ kind: 'api' }).key).toBe('OTHER');
  });
});
