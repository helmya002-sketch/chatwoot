import { describe, it, expect, vi } from 'vitest';
import { WidgetApp } from '../app';
import { encode } from '../bridge';

const flush = () =>
  new Promise(r => {
    setTimeout(r, 0);
  });

function setup() {
  const posted = [];
  const listeners = {};
  const parent = {
    postMessage: m => posted.push(JSON.parse(m.replace('chattz-widget:', ''))),
  };
  const win = {
    parent,
    location: { href: 'https://app.tolzar.com/widget' },
    addEventListener: (n, fn) => {
      listeners[n] = fn;
    },
    removeEventListener: () => {},
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: id => clearTimeout(id),
  };
  const api = {
    messages: vi.fn().mockResolvedValue([
      {
        id: 1,
        content: 'Welcome!',
        message_type: 1,
        created_at: 1,
        sender: { name: 'Mona' },
      },
    ]),
    sendText: vi
      .fn()
      .mockImplementation(content =>
        Promise.resolve({ id: 2, content, message_type: 0, created_at: 2 })
      ),
    seen: vi.fn(),
    typing: vi.fn(),
  };
  const cable = { start: vi.fn() };
  const root = document.createElement('div');
  document.body.appendChild(root);
  const app = new WidgetApp({
    config: {
      authToken: 'tok',
      pubsubToken: 'pub',
      channel: {
        websiteToken: 'wt',
        widgetColor: '#123456',
        welcomeTitle: 'Hi there',
      },
    },
    root,
    win,
    api,
    cable,
  });
  const fromLoader = (event, payload) =>
    listeners.message({ source: parent, data: encode(event, payload) });
  return { app, api, cable, root, posted, fromLoader };
}

describe('tolzar widget app', () => {
  it('tells the loader it loaded, shows the history and sends a message', async () => {
    const { app, api, cable, root, posted } = setup();
    await app.start();
    expect(cable.start).toHaveBeenCalled();
    expect(posted[0]).toMatchObject({
      event: 'loaded',
      config: { authToken: 'tok', channelConfig: { widgetColor: '#123456' } },
    });
    expect(root.querySelector('.tz-title').textContent).toBe('Hi there');
    expect(root.querySelector('.tz-theirs .tz-bubble').textContent).toBe(
      'Welcome!'
    );
    await app.send('  Hello  ');
    expect(api.sendText).toHaveBeenCalledWith(
      'Hello',
      expect.stringMatching(/^tz-/)
    );
    expect(root.querySelector('.tz-mine .tz-bubble').textContent).toBe('Hello');
  });

  it('shows a live team reply and raises the unread dot while closed', async () => {
    const { app, root, posted } = setup();
    await app.start();
    app.onLive({
      event: 'message.created',
      data: {
        id: 9,
        content: 'We can help',
        message_type: 1,
        created_at: Date.now() / 1000 + 5,
      },
    });
    expect(
      [...root.querySelectorAll('.tz-bubble')].map(b => b.textContent)
    ).toContain('We can help');
    const events = posted.map(p => p.event);
    expect(events).toEqual(
      expect.arrayContaining([
        'onEvent',
        'setUnreadMode',
        'handleNotificationDot',
      ])
    );
    expect(
      posted.find(p => p.event === 'handleNotificationDot').unreadMessageCount
    ).toBe(1);
  });

  it('follows the loader: open, locale (RTL) and a dark scheme', async () => {
    const { app, api, root, fromLoader } = setup();
    await app.start();
    fromLoader('toggle-open', { isOpen: true });
    expect(app.open).toBe(true);
    expect(api.seen).toHaveBeenCalled();
    fromLoader('set-locale', { locale: 'ar' });
    expect(root.dir).toBe('rtl');
    expect(root.querySelector('.tz-send').textContent).toBe('إرسال');
    fromLoader('set-color-scheme', { darkMode: 'dark' });
    expect(root.dataset.scheme).toBe('dark');
    await flush();
  });
});
