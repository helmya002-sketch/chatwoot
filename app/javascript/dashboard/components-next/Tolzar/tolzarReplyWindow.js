// Tolzar: how long a person may still reply on Messenger / Instagram (round 4, c77; Tolzar::MetaHumanAgent.window).
// Meta's standard window is 24 hours after the customer's last message; with HUMAN_AGENT on for the workspace a
// person may reply up to 7 days after it. Computed from the conversation's loaded messages, so the list never
// pays for it. WhatsApp and other channels have no line here.
export const META_CHANNELS = ['Channel::FacebookPage', 'Channel::Instagram'];
const HOUR = 3600;
const STANDARD = 24 * HOUR;
const HUMAN_AGENT = 7 * 24 * HOUR;
const INCOMING = 0;

export function lastIncomingAt(messages) {
  return (messages || []).reduce(
    (latest, m) =>
      m && m.message_type === INCOMING && m.created_at > latest
        ? m.created_at
        : latest,
    0
  );
}

// { kind: 'standard' | 'human_agent' | 'closed', secondsLeft } or null when the channel has no such window.
export function replyWindow({ channelType, messages, humanAgent, now }) {
  if (!META_CHANNELS.includes(channelType)) return null;
  const last = lastIncomingAt(messages);
  if (!last) return { kind: 'closed', secondsLeft: 0 };
  const at = Math.floor((now ?? Date.now()) / 1000);
  if (at < last + STANDARD)
    return { kind: 'standard', secondsLeft: last + STANDARD - at };
  if (humanAgent && at < last + HUMAN_AGENT)
    return { kind: 'human_agent', secondsLeft: last + HUMAN_AGENT - at };
  return { kind: 'closed', secondsLeft: 0 };
}

// "3 h" / "5 d" / "40 min": the largest whole unit, at least 1.
export function leftLabel(seconds) {
  if (seconds >= 86400) return { n: Math.floor(seconds / 86400), unit: 'D' };
  if (seconds >= HOUR) return { n: Math.floor(seconds / HOUR), unit: 'H' };
  return { n: Math.max(1, Math.floor(seconds / 60)), unit: 'MIN' };
}
