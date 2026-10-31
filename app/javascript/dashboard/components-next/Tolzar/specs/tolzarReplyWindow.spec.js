import { describe, it, expect } from 'vitest';
import { replyWindow, leftLabel, lastIncomingAt } from '../tolzarReplyWindow';

const H = 3600;
const now = 1_800_000_000 * 1000;
const at = s => now / 1000 - s;
const msgs = ago => [
  { message_type: 0, created_at: at(ago) },
  { message_type: 1, created_at: at(10) },
];

describe('tolzarReplyWindow', () => {
  it('counts the standard 24 hours from the last incoming message', () => {
    const w = replyWindow({
      channelType: 'Channel::FacebookPage',
      messages: msgs(21 * H),
      humanAgent: false,
      now,
    });
    expect(w).toEqual({ kind: 'standard', secondsLeft: 3 * H });
    expect(leftLabel(w.secondsLeft)).toEqual({ n: 3, unit: 'H' });
  });

  it('gives a person 7 days only with HUMAN_AGENT on, then closes', () => {
    const base = {
      channelType: 'Channel::Instagram',
      messages: msgs(2 * 24 * H),
      now,
    };
    expect(replyWindow({ ...base, humanAgent: false }).kind).toBe('closed');
    const w = replyWindow({ ...base, humanAgent: true });
    expect(w.kind).toBe('human_agent');
    expect(leftLabel(w.secondsLeft)).toEqual({ n: 5, unit: 'D' });
    expect(
      replyWindow({ ...base, messages: msgs(8 * 24 * H), humanAgent: true })
        .kind
    ).toBe('closed');
  });

  it('has no line for WhatsApp or other channels, and closes with no customer message', () => {
    expect(
      replyWindow({ channelType: 'Channel::Whatsapp', messages: msgs(H), now })
    ).toBeNull();
    expect(
      replyWindow({ channelType: 'Channel::FacebookPage', messages: [], now })
        .kind
    ).toBe('closed');
    expect(lastIncomingAt(null)).toBe(0);
    expect(leftLabel(30)).toEqual({ n: 1, unit: 'MIN' });
  });
});
