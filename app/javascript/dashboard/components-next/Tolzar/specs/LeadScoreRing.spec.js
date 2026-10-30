import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import LeadScoreRing from '../LeadScoreRing.vue';
import messages from '../../../i18n/locale/en/tolzarInbox.json';

// The global test i18n carries no messages; this spec asserts on the real English key.
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: messages },
});

const ring = props =>
  mount(LeadScoreRing, { props, global: { plugins: [i18n] } });

describe('LeadScoreRing', () => {
  it('names the score for screen readers and shows it in the centre', () => {
    const w = ring({ score: 78 });
    expect(w.attributes('role')).toBe('img');
    expect(w.attributes('aria-label')).toBe('Lead score 78 of 100');
    expect(w.find('i').text()).toBe('78');
  });

  it('clamps and rounds the score', () => {
    expect(ring({ score: 133 }).find('i').text()).toBe('100');
    expect(ring({ score: -4 }).find('i').text()).toBe('0');
    expect(ring({ score: 71.6 }).find('i').text()).toBe('72');
  });

  it('draws the arc with currentColor from the brand token, no hex', () => {
    const w = ring({ score: 40 });
    expect(w.classes()).toContain('text-n-brand');
    expect(w.attributes('style')).toContain('conic-gradient(currentColor 40%');
    expect(w.attributes('style')).not.toMatch(/#[0-9a-f]{3,6}/i);
  });

  it('has a small and a medium size', () => {
    expect(ring({ score: 10, size: 'sm' }).classes()).toContain('tz-lsr-sm');
    expect(ring({ score: 10 }).classes()).toContain('tz-lsr-md');
  });
});
