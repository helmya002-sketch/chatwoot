import { describe, it, expect } from 'vitest';
import { formatMessage, safeHref, cleanText } from '../format';

const JS = ['java', 'script:'].join('');

const html = text => {
  const div = document.createElement('div');
  div.appendChild(formatMessage(text));
  return div;
};

describe('tolzar widget formatter', () => {
  it('never turns network text into HTML', () => {
    const corpus = [
      '<script>alert(1)</script>',
      '<img src=x onerror=alert(1)>',
      '&lt;b&gt;x&lt;/b&gt;',
      '"><svg onload=alert(1)>',
    ];
    corpus.forEach(text => {
      const div = html(text);
      expect(div.querySelector('script, img, svg')).toBeNull();
      expect(div.textContent).toBe(text);
    });
  });

  it('links only http, https and mailto, never javascript or data', () => {
    expect(safeHref(`${JS}alert(1)`)).toBeNull();
    expect(safeHref('data:text/html,hi')).toBeNull();
    const div = html(`see https://tolzar.com/pricing. or ${JS}alert(1)`);
    const links = div.querySelectorAll('a');
    expect(links).toHaveLength(1);
    expect(links[0].getAttribute('href')).toBe('https://tolzar.com/pricing');
    expect(links[0].rel).toContain('noopener');
    expect(div.textContent).toContain(`${JS}alert(1)`);
  });

  it('keeps bold, italics and line breaks as elements', () => {
    const div = html('*Price* is _final_\nthanks');
    expect(div.querySelector('strong').textContent).toBe('Price');
    expect(div.querySelector('em').textContent).toBe('final');
    expect(div.querySelectorAll('br')).toHaveLength(1);
  });

  it('drops bidi override characters', () => {
    expect(cleanText('abc‮def⁦')).toBe('abcdef');
  });
});
