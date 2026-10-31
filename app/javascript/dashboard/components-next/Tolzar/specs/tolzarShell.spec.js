import { describe, it, expect } from 'vitest';
import { aiLiveSummary } from '../tolzarShell';

describe('tolzarShell', () => {
  it('summarises live and shadow inboxes, and the kill switch wins', () => {
    expect(aiLiveSummary(null, 3)).toEqual({
      state: 'shadow',
      live: 0,
      shadow: 3,
    });
    expect(aiLiveSummary({ inbox_modes: {} }, 4)).toEqual({
      state: 'shadow',
      live: 0,
      shadow: 4,
    });
    expect(aiLiveSummary({ inbox_modes: { 1: { mode: 'live' } } }, 4)).toEqual({
      state: 'live',
      live: 1,
      shadow: 3,
    });
    expect(
      aiLiveSummary(
        { kill_switch_on: true, inbox_modes: { 1: { mode: 'live' } } },
        4
      )
    ).toEqual({ state: 'stopped', live: 0, shadow: 4 });
  });
});
