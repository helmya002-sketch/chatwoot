import { describe, it, expect, vi } from 'vitest';
import { richNode } from '../rich';
import { WidgetApp } from '../app';

const app = (overrides = {}) => ({
  doc: document,
  locale: 'en',
  choose: vi.fn(),
  submitForm: vi.fn(),
  ...overrides,
});

describe('widget rich replies', () => {
  it('renders options (booking slots too) as buttons that answer', () => {
    const a = app();
    const m = {
      id: 4,
      contentType: 'input_select',
      content_attributes: {
        items: [
          { title: 'Sat 10:00', value: '2026-11-07T10:00' },
          { title: 'Sun 09:00', value: '2026-11-08T09:00' },
        ],
      },
    };
    const node = richNode(a, m);
    const buttons = node.querySelectorAll('button');
    expect([...buttons].map(b => b.textContent)).toEqual([
      'Sat 10:00',
      'Sun 09:00',
    ]);
    buttons[1].click();
    expect(a.choose).toHaveBeenCalledWith(m, {
      title: 'Sun 09:00',
      value: '2026-11-08T09:00',
    });
    const done = richNode(a, {
      ...m,
      content_attributes: {
        ...m.content_attributes,
        submitted_values: [{ title: 'Sat 10:00' }],
      },
    });
    expect(done.textContent).toBe('Sat 10:00');
  });

  it('renders cards with safe links, postback buttons and no unsafe image', () => {
    const a = app();
    const m = {
      id: 5,
      contentType: 'cards',
      content_attributes: {
        items: [
          {
            title: 'Open Water',
            description: '3 days',
            media_url: ['java', 'script:x'].join(''),
            actions: [
              { type: 'link', text: 'Details', uri: 'https://dive.test/ow' },
              { type: 'postback', text: 'Book it', payload: 'BOOK_OW' },
              {
                type: 'link',
                text: 'Bad',
                uri: ['java', 'script:alert(1)'].join(''),
              },
            ],
          },
        ],
      },
    };
    const node = richNode(a, m);
    expect(node.querySelector('img')).toBeNull();
    expect(node.querySelector('a').getAttribute('href')).toBe(
      'https://dive.test/ow'
    );
    expect(node.querySelectorAll('a')).toHaveLength(1);
    node.querySelector('button').click();
    expect(a.choose).toHaveBeenCalledWith(m, {
      title: 'Book it',
      value: 'BOOK_OW',
    });
  });

  it('checks required form fields and submits name/value pairs', () => {
    const a = app();
    const m = {
      id: 6,
      contentType: 'form',
      content_attributes: {
        items: [
          { name: 'email', label: 'E-mail', type: 'email', required: true },
          { name: 'note', label: 'Note', type: 'text_area' },
        ],
      },
    };
    const node = richNode(a, m);
    document.body.appendChild(node);
    node.dispatchEvent(new Event('submit', { cancelable: true }));
    expect(a.submitForm).not.toHaveBeenCalled();
    expect(node.querySelector('[role="alert"]').textContent).toBe(
      'Please fill this in.'
    );
    node.querySelector('#tz-f-6-0').value = 'sara@example.com';
    node.dispatchEvent(new Event('submit', { cancelable: true }));
    expect(a.submitForm).toHaveBeenCalledWith(m, [
      { name: 'email', value: 'sara@example.com' },
      { name: 'note', value: '' },
    ]);
  });

  it('records a choice on the message and sends it as the visitor answer', async () => {
    const api = {
      messages: vi.fn().mockResolvedValue([
        {
          id: 4,
          content: 'Pick a time',
          message_type: 1,
          content_type: 'input_select',
          created_at: 1,
          content_attributes: {
            items: [{ title: 'Sat 10:00', value: 'sat' }],
          },
        },
      ]),
      submit: vi.fn().mockResolvedValue({}),
      sendText: vi.fn().mockResolvedValue({
        id: 9,
        content: 'Sat 10:00',
        message_type: 0,
        created_at: 2,
      }),
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
    const root = document.createElement('div');
    const w = new WidgetApp({
      config: { channel: { websiteToken: 'w' } },
      root,
      win,
      api,
      cable: { start: () => {} },
    });
    await w.start();
    root.querySelector('.tz-option').click();
    await new Promise(r => {
      setTimeout(r, 0);
    });
    expect(api.submit).toHaveBeenCalledWith(4, [
      { title: 'Sat 10:00', value: 'sat' },
    ]);
    expect(api.sendText).toHaveBeenCalledWith(
      'Sat 10:00',
      expect.any(String),
      undefined
    );
    expect(root.querySelector('.tz-option')).toBeNull();
  });
});
