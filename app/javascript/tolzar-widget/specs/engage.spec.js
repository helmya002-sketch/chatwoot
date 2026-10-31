import { describe, it, expect, vi } from 'vitest';
import { urlMatches, pickCampaign, armCampaign, csatNode } from '../engage';
import { WidgetApp } from '../app';

const CAMPAIGNS = [
  {
    id: 3,
    trigger_rules: { url: 'https://shop.test/pricing*', time_on_page: 10 },
    message: 'Questions about plans?',
  },
  {
    id: 4,
    trigger_rules: { url: 'https://shop.test/*', time_on_page: 30 },
    trigger_only_during_business_hours: true,
  },
];

describe('campaigns', () => {
  it('matches page URLs with a wildcard, case-insensitively, ignoring the #hash', () => {
    expect(
      urlMatches(
        'https://shop.test/pricing*',
        'https://shop.test/pricing?plan=team#faq'
      )
    ).toBe(true);
    expect(
      urlMatches('https://shop.test/pricing', 'https://SHOP.test/pricing')
    ).toBe(true);
    expect(
      urlMatches('https://shop.test/pricing', 'https://shop.test/pricing-old')
    ).toBe(false);
    expect(urlMatches('', 'https://shop.test/')).toBe(false);
  });

  it('picks the first matching campaign, never during a running chat or out of hours when asked', () => {
    expect(
      pickCampaign(CAMPAIGNS, {
        pageUrl: 'https://shop.test/pricing',
        inOfficeHours: false,
        hasMessages: false,
      }).id
    ).toBe(3);
    expect(
      pickCampaign(CAMPAIGNS, {
        pageUrl: 'https://shop.test/about',
        inOfficeHours: false,
        hasMessages: false,
      })
    ).toBeNull();
    expect(
      pickCampaign(CAMPAIGNS, {
        pageUrl: 'https://shop.test/about',
        inOfficeHours: true,
        hasMessages: false,
      }).id
    ).toBe(4);
    expect(
      pickCampaign(CAMPAIGNS, {
        pageUrl: 'https://shop.test/pricing',
        inOfficeHours: true,
        hasMessages: true,
      })
    ).toBeNull();
  });

  it('fires after the time on page, and can be cancelled', () => {
    vi.useFakeTimers();
    const fire = vi.fn();
    const cancel = armCampaign(CAMPAIGNS[0], fire);
    vi.advanceTimersByTime(9999);
    expect(fire).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(fire).toHaveBeenCalledWith(CAMPAIGNS[0]);
    const fire2 = vi.fn();
    armCampaign(CAMPAIGNS[0], fire2)();
    vi.advanceTimersByTime(20000);
    expect(fire2).not.toHaveBeenCalled();
    cancel();
    vi.useRealTimers();
  });
});

describe('satisfaction rating', () => {
  it('offers five labelled buttons, and thanks once rated', () => {
    const app = { doc: document, locale: 'en', rate: vi.fn() };
    const node = csatNode(app, { id: 7, content_attributes: {} });
    const buttons = node.querySelectorAll('button');
    expect(buttons).toHaveLength(5);
    expect(buttons[4].getAttribute('aria-label')).toBe('Very good');
    buttons[3].click();
    expect(app.rate).toHaveBeenCalledWith(
      expect.objectContaining({ id: 7 }),
      4
    );
    const done = csatNode(app, {
      id: 7,
      content_attributes: {
        submitted_values: { csat_survey_response: { rating: 4 } },
      },
    });
    expect(done.textContent).toBe('Thank you for your rating.');
  });

  it('renders a CSAT message in the app and sends the rating', async () => {
    const root = document.createElement('div');
    const api = {
      messages: vi.fn().mockResolvedValue([
        {
          id: 7,
          content: 'Please rate us',
          message_type: 3,
          content_type: 'input_csat',
          created_at: 1,
        },
      ]),
      rate: vi.fn().mockResolvedValue({}),
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
      root,
      win,
      api,
      cable: { start: () => {} },
    });
    await app.start();
    root.querySelectorAll('.tz-csat-btn')[4].click();
    await new Promise(r => {
      setTimeout(r, 0);
    });
    expect(api.rate).toHaveBeenCalledWith(7, 5);
    expect(root.querySelector('.tz-csat-thanks')).not.toBeNull();
  });
});
