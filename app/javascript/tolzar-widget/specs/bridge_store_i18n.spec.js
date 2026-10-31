import { describe, it, expect, vi } from 'vitest';
import { Bridge, encode, decode } from '../bridge';
import { createStore, upsert, markFailed, countUnread, TYPE } from '../store';
import { STRINGS, t, direction, lang } from '../i18n';

describe('tolzar widget bridge', () => {
  it('speaks the loader contract', () => {
    expect(encode('loaded', { config: { a: 1 } })).toBe(
      'chattz-widget:{"event":"loaded","config":{"a":1}}'
    );
    expect(
      decode('chattz-widget:{"event":"toggle-open","isOpen":true}')
    ).toEqual({ event: 'toggle-open', isOpen: true });
    expect(decode('other:{"event":"x"}')).toBeNull();
    expect(decode('chattz-widget:not json')).toBeNull();
  });

  it('reads only messages from the parent window', () => {
    const parent = { postMessage: vi.fn() };
    const listeners = {};
    const win = {
      parent,
      addEventListener: (n, fn) => {
        listeners[n] = fn;
      },
      removeEventListener: () => {},
    };
    const handler = vi.fn();
    const bridge = new Bridge({ win, handlers: { 'toggle-open': handler } });
    bridge.start();
    listeners.message({
      source: {},
      data: encode('toggle-open', { isOpen: true }),
    });
    expect(handler).not.toHaveBeenCalled();
    listeners.message({
      source: parent,
      data: encode('toggle-open', { isOpen: true }),
    });
    expect(handler).toHaveBeenCalledWith({
      event: 'toggle-open',
      isOpen: true,
    });
    bridge.send('closeWindow', {});
    expect(parent.postMessage).toHaveBeenCalledWith(
      'chattz-widget:{"event":"closeWindow"}',
      '*'
    );
  });
});

describe('tolzar widget store', () => {
  it('replaces a pending message with the server copy and hides private notes', () => {
    const store = createStore();
    upsert(store, [
      {
        echo_id: 'e1',
        content: 'hi',
        message_type: 0,
        created_at: 10,
        pending: true,
      },
    ]);
    upsert(store, [
      {
        id: 5,
        content: 'hi',
        message_type: 0,
        created_at: 10,
        content_attributes: { echo_id: 'e1' },
      },
    ]);
    upsert(store, [
      {
        id: 6,
        content: 'note',
        message_type: 1,
        created_at: 11,
        private: true,
      },
    ]);
    expect(store.messages).toHaveLength(1);
    expect(store.messages[0]).toMatchObject({ id: 5, pending: false });
  });

  it('marks a failed send and counts unread team replies', () => {
    const store = createStore();
    upsert(store, [
      { echo_id: 'e2', content: 'x', message_type: 0, created_at: 5 },
      { id: 1, content: 'answer', message_type: TYPE.OUTGOING, created_at: 20 },
    ]);
    markFailed(store, 'e2');
    expect(store.messages.find(m => m.echo_id === 'e2').failed).toBe(true);
    expect(countUnread(store, 10)).toBe(1);
    expect(countUnread(store, 30)).toBe(0);
  });
});

describe('tolzar widget i18n', () => {
  it('has every key in all six languages', () => {
    const keys = Object.keys(STRINGS.en).sort();
    ['ar', 'de', 'fr', 'es', 'pt'].forEach(l =>
      expect(Object.keys(STRINGS[l]).sort()).toEqual(keys)
    );
  });

  it('falls back to English and knows RTL', () => {
    expect(lang('pt_BR')).toBe('pt');
    expect(t('xx', 'SEND')).toBe('Send');
    expect(direction('ar')).toBe('rtl');
    expect(direction('en-GB')).toBe('ltr');
  });
});
