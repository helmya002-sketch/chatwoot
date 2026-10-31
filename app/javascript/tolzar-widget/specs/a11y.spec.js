import { describe, it, expect, vi } from 'vitest';
import { WidgetApp } from '../app';

// WCAG 2.2 AA checks the widget can prove in a DOM: names, live region, keyboard, target size, language, labels.
function setup(messages = []) {
  const posted = [];
  const win = {
    parent: {
      postMessage: m =>
        posted.push(JSON.parse(m.replace('chattz-widget:', ''))),
    },
    location: { href: 'https://x.test/widget' },
    addEventListener: () => {},
    removeEventListener: () => {},
    setTimeout,
    clearTimeout,
  };
  const api = {
    messages: vi.fn().mockResolvedValue(messages),
    seen: vi.fn(),
    typing: vi.fn(),
  };
  const root = document.createElement('div');
  document.body.appendChild(root);
  const app = new WidgetApp({
    config: {
      locale: 'ar',
      channel: { websiteToken: 'w', welcomeTitle: 'Hi' },
    },
    root,
    win,
    api,
    cable: { start: () => {} },
  });
  return { app, root, posted };
}

describe('widget accessibility', () => {
  it('has a polite live region, a labelled composer, language and direction', async () => {
    const { app, root } = setup();
    await app.start();
    const list = root.querySelector('.tz-list');
    expect(list.getAttribute('aria-live')).toBe('polite');
    expect(list.getAttribute('aria-label')).toBeTruthy();
    expect(
      root.querySelector('.tz-input').getAttribute('aria-label')
    ).toBeTruthy();
    expect(root.lang).toBe('ar');
    expect(root.dir).toBe('rtl');
    root
      .querySelectorAll('button')
      .forEach(b =>
        expect(
          b.textContent.trim() || b.getAttribute('aria-label')
        ).toBeTruthy()
      );
  });

  it('tells screen readers who wrote each message', async () => {
    const { app, root } = setup([
      {
        id: 1,
        content: 'Hello',
        message_type: 1,
        created_at: 1,
        sender: { name: 'Mona' },
      },
    ]);
    await app.start();
    expect(root.querySelector('.tz-theirs .tz-sr').textContent).toMatch(
      /^Mona, /
    );
  });

  it('closes on Escape', async () => {
    const { app, root, posted } = setup();
    await app.start();
    root.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(posted.map(p => p.event)).toContain('closeWindow');
  });
});
