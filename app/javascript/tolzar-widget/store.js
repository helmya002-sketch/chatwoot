// Tolzar widget: the message list as plain data. Messages are kept by id, sorted by time; a message we sent
// first appears under its echo id and is replaced when the server's copy arrives (by echo_id or content).

export const TYPE = { INCOMING: 0, OUTGOING: 1, ACTIVITY: 2, TEMPLATE: 3 };

export function createStore() {
  return { messages: [], typing: false, status: 'open', unread: 0 };
}

const key = m => (m.id != null ? `id:${m.id}` : `echo:${m.echo_id}`);

export function normalise(raw) {
  return {
    id: raw.id ?? null,
    echo_id: raw.echo_id || raw.content_attributes?.echo_id || null,
    content: raw.content ?? '',
    type: Number(raw.message_type ?? TYPE.INCOMING),
    contentType: raw.content_type || 'text',
    content_attributes: raw.content_attributes || {},
    createdAt: Number(raw.created_at || Date.now() / 1000),
    sender: raw.sender
      ? {
          name: raw.sender.name || '',
          avatar: raw.sender.avatar_url || raw.sender.thumbnail || '',
        }
      : null,
    attachments: Array.isArray(raw.attachments) ? raw.attachments : [],
    pending: Boolean(raw.pending),
    failed: Boolean(raw.failed),
    private: Boolean(raw.private),
  };
}

// Adds or replaces messages; private notes never show to the visitor.
export function upsert(store, list) {
  const byKey = new Map(store.messages.map(m => [key(m), m]));
  list.map(normalise).forEach(m => {
    if (m.private) return;
    if (m.id != null && m.echo_id) byKey.delete(`echo:${m.echo_id}`);
    byKey.set(key(m), { ...(byKey.get(key(m)) || {}), ...m });
  });
  store.messages = [...byKey.values()].sort(
    (a, b) => a.createdAt - b.createdAt
  );
  return store;
}

export function markFailed(store, echoId) {
  store.messages = store.messages.map(m =>
    m.echo_id === echoId && m.id == null
      ? { ...m, pending: false, failed: true }
      : m
  );
  return store;
}

// Replies from the team (outgoing/template) the visitor has not seen yet.
export function countUnread(store, seenAt) {
  return store.messages.filter(
    m =>
      (m.type === TYPE.OUTGOING || m.type === TYPE.TEMPLATE) &&
      m.createdAt > seenAt
  ).length;
}
