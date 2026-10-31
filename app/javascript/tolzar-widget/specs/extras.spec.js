import { describe, it, expect, vi } from 'vitest';
import { isOpen, localTime } from '../hours';
import { fields, needed, validate, toRequest } from '../prechat';
import { attachmentNodes, fileTooBig } from '../extras';
import { WidgetApp } from '../app';
import { STRINGS } from '../i18n';

const HOURS = [1, 2, 3, 4, 5].map(d => ({
  day_of_week: d,
  open_hour: 9,
  open_minutes: 0,
  close_hour: 17,
  close_minutes: 30,
}));

describe('office hours', () => {
  it('reads the time in the inbox time zone', () => {
    // 2026-11-02 is a Monday; 07:00 UTC is 09:00 in Cairo (UTC+2).
    expect(localTime(new Date('2026-11-02T07:00:00Z'), 'Africa/Cairo')).toEqual(
      { day: 1, minutes: 540 }
    );
  });

  it('is open inside the hours, closed outside and on days without hours', () => {
    const cfg = { enabled: true, hours: HOURS, timeZone: 'Africa/Cairo' };
    expect(isOpen(cfg, new Date('2026-11-02T07:00:00Z'))).toBe(true);
    expect(isOpen(cfg, new Date('2026-11-02T15:31:00Z'))).toBe(false);
    expect(isOpen(cfg, new Date('2026-11-01T10:00:00Z'))).toBe(false);
    expect(isOpen({ enabled: false }, new Date())).toBe(true);
    expect(
      isOpen(
        {
          enabled: true,
          hours: [{ day_of_week: 0, open_all_day: true }],
          timeZone: 'UTC',
        },
        new Date('2026-11-01T03:00:00Z')
      )
    ).toBe(true);
  });
});

describe('pre-chat form', () => {
  const options = {
    pre_chat_fields: [
      {
        name: 'emailAddress',
        label: 'Email',
        type: 'email',
        required: true,
        enabled: true,
        field_type: 'standard',
      },
      {
        name: 'fullName',
        label: 'Name',
        type: 'text',
        required: false,
        enabled: true,
        field_type: 'standard',
      },
      {
        name: 'phoneNumber',
        label: 'Phone',
        type: 'text',
        required: false,
        enabled: false,
        field_type: 'standard',
      },
      {
        name: 'order_ref',
        label: 'Order',
        type: 'text',
        required: false,
        enabled: true,
        field_type: 'conversation_attribute',
      },
      {
        name: 'company',
        label: 'Company',
        type: 'text',
        required: false,
        enabled: true,
        field_type: 'contact_attribute',
      },
    ],
  };

  it('shows only enabled fields, and only before the first message', () => {
    expect(fields(options).map(f => f.name)).toEqual([
      'emailAddress',
      'fullName',
      'order_ref',
      'company',
    ]);
    expect(needed({ enabled: true, options, hasMessages: false })).toBe(true);
    expect(needed({ enabled: true, options, hasMessages: true })).toBe(false);
    expect(needed({ enabled: false, options, hasMessages: false })).toBe(false);
  });

  it('validates required fields, e-mail and the message', () => {
    const list = fields(options);
    expect(validate(list, {}, '')).toEqual({
      emailAddress: 'REQUIRED',
      message: 'REQUIRED',
    });
    expect(validate(list, { emailAddress: 'nope' }, 'hi')).toEqual({
      emailAddress: 'EMAIL',
    });
    expect(validate(list, { emailAddress: 'sara@example.com' }, 'hi')).toEqual(
      {}
    );
  });

  it('builds the conversation request with contact and conversation attributes', () => {
    const body = toRequest(
      fields(options),
      {
        emailAddress: ' sara@example.com ',
        fullName: 'Sara',
        order_ref: 'A-1',
        company: 'Nile',
      },
      ' Hello '
    );
    expect(body.contact).toEqual({
      email: 'sara@example.com',
      name: 'Sara',
      custom_attributes: { company: 'Nile' },
    });
    expect(body.custom_attributes).toEqual({ order_ref: 'A-1' });
    expect(body.message.content).toBe('Hello');
  });

  it('replaces the composer with the form, and sends it', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);
    const api = {
      messages: vi.fn().mockResolvedValue([]),
      startConversation: vi.fn().mockResolvedValue({ id: 1 }),
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
      config: {
        authToken: 't',
        channel: {
          websiteToken: 'w',
          preChatFormEnabled: true,
          preChatFormOptions: options,
        },
      },
      root,
      win,
      api,
      cable: { start: () => {} },
    });
    await app.start();
    const form = root.querySelector('.tz-prechat');
    expect(form).not.toBeNull();
    expect(app.composer.hidden).toBe(true);
    root.querySelector('#tz-pc-emailAddress').value = 'sara@example.com';
    root.querySelector('#tz-pc-message').value = 'I need a quote';
    form.dispatchEvent(new Event('submit', { cancelable: true }));
    await new Promise(r => {
      setTimeout(r, 0);
    });
    expect(api.startConversation).toHaveBeenCalledWith(
      expect.objectContaining({
        contact: expect.objectContaining({ email: 'sara@example.com' }),
      })
    );
    expect(root.querySelector('.tz-prechat')).toBeNull();
    expect(app.composer.hidden).toBe(false);
  });
});

describe('attachments', () => {
  it('renders images and files with safe links only', () => {
    const nodes = attachmentNodes(
      document,
      [
        {
          file_type: 'image',
          data_url: 'https://cdn.test/a.png',
          thumb_url: 'https://cdn.test/a-thumb.png',
        },
        { file_type: 'file', data_url: 'https://cdn.test/files/quote.pdf' },
        {
          file_type: 'file',
          data_url: `${['java', 'script:'].join('')}alert(1)`,
        },
      ],
      'en'
    );
    expect(nodes).toHaveLength(2);
    expect(nodes[0].querySelector('img').getAttribute('src')).toBe(
      'https://cdn.test/a-thumb.png'
    );
    expect(nodes[1].textContent).toBe('quote.pdf');
  });

  it('refuses files over the limit', () => {
    expect(fileTooBig({ size: 41 * 1024 * 1024 }, 40)).toBe(true);
    expect(fileTooBig({ size: 1024 }, 40)).toBe(false);
  });

  it('keeps every new string in all six languages', () => {
    const keys = Object.keys(STRINGS.en).sort();
    Object.values(STRINGS).forEach(s =>
      expect(Object.keys(s).sort()).toEqual(keys)
    );
  });
});
