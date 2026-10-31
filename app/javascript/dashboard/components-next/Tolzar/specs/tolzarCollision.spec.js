import { describe, it, expect } from 'vitest';
import { recentReplyByOther } from '../tolzarCollision';

const msg = (over = {}) => ({
  message_type: 1,
  private: false,
  created_at: 1000,
  sender: { type: 'user', id: 2, name: 'Mona' },
  ...over,
});

describe('tolzarCollision', () => {
  it("names a teammate's public reply sent since I started writing", () => {
    expect(recentReplyByOther([msg()], 1, 900)).toBe('Mona');
  });

  it('ignores my own replies, notes, bots, older replies and incoming messages', () => {
    expect(
      recentReplyByOther(
        [msg({ sender: { type: 'user', id: 1, name: 'Me' } })],
        1,
        900
      )
    ).toBe('');
    expect(recentReplyByOther([msg({ private: true })], 1, 900)).toBe('');
    expect(
      recentReplyByOther(
        [msg({ sender: { type: 'agent_bot', id: 9, name: 'Bot' } })],
        1,
        900
      )
    ).toBe('');
    expect(recentReplyByOther([msg({ created_at: 800 })], 1, 900)).toBe('');
    expect(recentReplyByOther([msg({ message_type: 0 })], 1, 900)).toBe('');
    expect(recentReplyByOther([msg()], 1, null)).toBe('');
  });
});
