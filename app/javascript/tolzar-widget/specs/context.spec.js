import { describe, it, expect, vi } from 'vitest';
import { sourcesNode, pageContext } from '../context';
import { WidgetApp } from '../app';

describe('widget sources and page context', () => {
  it('shows up to three sources as safe links', () => {
    const node = sourcesNode(
      document,
      {
        tolzar_sources: [
          { title: 'Price list', url: 'https://shop.test/prices' },
          { title: 'Bad', url: ['java', 'script:alert(1)'].join('') },
          { title: 'FAQ', url: 'https://shop.test/faq' },
          { title: 'Fourth', url: 'https://shop.test/4' },
        ],
      },
      'en'
    );
    expect(node.textContent).toBe('Sources: Price list · Bad · FAQ');
    const links = node.querySelectorAll('a');
    expect([...links].map(a => a.getAttribute('href'))).toEqual([
      'https://shop.test/prices',
      'https://shop.test/faq',
    ]);
    expect(sourcesNode(document, {}, 'en')).toBeNull();
  });

  it('keeps only origin and path of the page', () => {
    expect(
      pageContext('https://shop.test/pricing?utm=x&email=a@b.c#plans')
    ).toEqual({ tolzar_page: 'https://shop.test/pricing' });
    expect(pageContext('file:///etc/passwd')).toBeNull();
    expect(pageContext('')).toBeNull();
  });

  it('tags the conversation with the page once, after the first message', async () => {
    const api = {
      messages: vi.fn().mockResolvedValue([]),
      sendText: vi.fn().mockResolvedValue({
        id: 3,
        content: 'hi',
        message_type: 0,
        created_at: 1,
      }),
      setConversationAttributes: vi.fn().mockResolvedValue({}),
      campaigns: vi.fn().mockResolvedValue([]),
      seen: vi.fn(),
      typing: vi.fn(),
    };
    const win = {
      parent: { postMessage: () => {} },
      location: { href: 'https://x.test/widget' },
      addEventListener: () => {},
      removeEventListener: () => {},
      setTimeout,
      clearTimeout,
    };
    const app = new WidgetApp({
      config: { channel: { websiteToken: 'w' } },
      root: document.createElement('div'),
      win,
      api,
      cable: { start: () => {} },
    });
    await app.start();
    await app.onPage('https://shop.test/pricing?x=1');
    await app.send('hi');
    await app.send('again');
    expect(api.setConversationAttributes).toHaveBeenCalledTimes(1);
    expect(api.setConversationAttributes).toHaveBeenCalledWith({
      tolzar_page: 'https://shop.test/pricing',
    });
  });
});
