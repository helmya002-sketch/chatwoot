import { describe, it, expect } from 'vitest';
import { handoffLinks, handoffNode } from '../handoff';

describe('widget channel hand-off links', () => {
  it('keeps only https deep links to wa.me, ig.me and t.me', () => {
    const list = [
      { channel: 'whatsapp', url: 'https://wa.me/201001234567' },
      { channel: 'instagram', url: 'https://ig.me/m/nilebikes' },
      { channel: 'telegram', url: 'https://evil.test/x' },
      { channel: 'whatsapp', url: 'http://wa.me/1' },
    ];
    expect(handoffLinks(list).map(l => l.channel)).toEqual([
      'whatsapp',
      'instagram',
    ]);
  });

  it('renders labelled links in the visitor language', () => {
    const node = handoffNode(
      document,
      [{ channel: 'telegram', url: 'https://t.me/nilebikes' }],
      'de'
    );
    expect(node.getAttribute('aria-label')).toBe('Weiter auf');
    const a = node.querySelector('a');
    expect(a.textContent).toBe('Telegram');
    expect(a.getAttribute('href')).toBe('https://t.me/nilebikes');
    expect(handoffNode(document, [], 'en')).toBeNull();
  });
});
