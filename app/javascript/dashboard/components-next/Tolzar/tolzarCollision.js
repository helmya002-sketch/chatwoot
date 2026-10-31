// Tolzar collision guard (round 4, c92): did someone else on the team reply to the customer since I started writing?
// Only public replies by another person count (not notes, not the AI or bots, not my own). `since` is unix seconds.
const OUTGOING = 1;

export function recentReplyByOther(messages, myUserId, since) {
  if (!since) return '';
  const hit = (messages || [])
    .filter(
      m =>
        m &&
        m.message_type === OUTGOING &&
        !m.private &&
        m.created_at >= since &&
        m.sender?.type === 'user' &&
        m.sender?.id !== myUserId
    )
    .pop();
  return hit ? hit.sender.name || '?' : '';
}
