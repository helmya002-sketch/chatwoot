import { describe, it, expect, beforeEach, vi } from 'vitest';
import { readFileSync } from 'fs';
import { join } from 'path';
import { gzipSync } from 'zlib';

// The own loader (public/tz/widget.js): the compatible public API, a lazy iframe, origin checks, the unread dot,
// the auth cookie, and its size budget (plan A5: ≤ 6 KB gzip).
const SRC = readFileSync(
  join(__dirname, '..', '..', '..', '..', 'public', 'tz', 'widget.js'),
  'utf8'
);
const load = () => {
  // eslint-disable-next-line no-new-func
  new Function(SRC)();
};
const frameWin = () =>
  document.querySelector('.tz-l-holder iframe').contentWindow;
const fromFrame = (data, { origin = 'https://app.tolzar.com', source } = {}) =>
  window.dispatchEvent(
    new MessageEvent('message', {
      data: `chattz-widget:${JSON.stringify(data)}`,
      origin,
      source: source || frameWin(),
    })
  );

describe('tolzar loader', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
    document.head.innerHTML = '';
    document.cookie = 'cw_conversation=; Path=/; Max-Age=0';
    delete window.tolzar;
    delete window.$chatwoot;
    delete window.chatwootSDK;
    load();
  });

  it('fits the 6 KB gzip budget and exposes the compatible API', () => {
    expect(gzipSync(Buffer.from(SRC)).length).toBeLessThan(6 * 1024);
    expect(typeof window.chatwootSDK.run).toBe('function');
    expect(window.$chatwoot).toBe(window.tolzar);
    [
      'toggle',
      'setUser',
      'setCustomAttributes',
      'setLocale',
      'setLabel',
      'removeLabel',
      'reset',
      'popoutChatWindow',
    ].forEach(fn => expect(typeof window.$chatwoot[fn]).toBe('function'));
  });

  it('draws the launcher and creates the iframe only on first open', () => {
    window.chatwootSDK.run({
      websiteToken: 'wt1',
      baseUrl: 'https://app.tolzar.com/',
    });
    const bubble = document.querySelector('.tz-l-bubble');
    expect(bubble.getAttribute('aria-expanded')).toBe('false');
    expect(document.querySelector('iframe')).toBeNull();
    bubble.click();
    const iframe = document.querySelector('iframe');
    expect(iframe.getAttribute('src')).toBe(
      'https://app.tolzar.com/widget?website_token=wt1'
    );
    expect(bubble.getAttribute('aria-expanded')).toBe('true');
  });

  it('accepts messages only from its iframe and origin, stores the token and raises events', () => {
    window.tolzar.run({
      websiteToken: 'wt1',
      baseUrl: 'https://app.tolzar.com',
    });
    window.tolzar.toggle('open');
    const ready = vi.fn();
    window.addEventListener('chatwoot:ready', ready);
    fromFrame(
      { event: 'loaded', config: { authToken: 'TOKEN' } },
      { origin: 'https://evil.test' }
    );
    expect(ready).not.toHaveBeenCalled();
    fromFrame({
      event: 'loaded',
      config: { authToken: 'TOKEN', channelConfig: { widgetColor: '#112233' } },
    });
    expect(ready).toHaveBeenCalled();
    expect(document.cookie).toContain('cw_conversation=TOKEN');
    window.tolzar.toggle('close');
    fromFrame({ event: 'handleNotificationDot', unreadMessageCount: 2 });
    expect(document.querySelector('.tz-l-bubble').className).toContain(
      'tz-l-unread'
    );
  });

  it('gives focus back to the launcher when the chat closes itself', () => {
    window.tolzar.run({ websiteToken: 'wt1', baseUrl: 'https://app.tolzar.com' });
    window.tolzar.toggle('open');
    fromFrame({ event: 'closeWindow' });
    expect(document.activeElement).toBe(document.querySelector('.tz-l-bubble'));
    expect(document.querySelector('.tz-l-holder').className).not.toContain(
      'tz-l-open'
    );
  });

  it('loads quietly for a returning visitor so new replies can show', () => {
    document.cookie = 'cw_conversation=OLD; Path=/';
    window.tolzar.run({
      websiteToken: 'wt1',
      baseUrl: 'https://app.tolzar.com',
    });
    expect(document.querySelector('iframe').getAttribute('src')).toContain(
      'cw_conversation=OLD'
    );
    expect(document.querySelector('.tz-l-holder').className).not.toContain(
      'tz-l-open'
    );
  });
});
