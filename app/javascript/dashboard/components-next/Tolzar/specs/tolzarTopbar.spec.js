import { describe, it, expect } from 'vitest';
import { nowChips, chipRoute, aiPill, tzQuickView } from '../tolzarTopbar';

describe('tolzarTopbar', () => {
  it('shows only counts above zero, in a fixed order, each with its list', () => {
    const chips = nowChips(
      { unassigned: 2, mine: 4, waiting: 0, due_today: 1, extra: 9 },
      7
    );
    expect(chips.map(c => c.key)).toEqual(['mine', 'unassigned', 'due_today']);
    expect(chips[0]).toEqual({
      key: 'mine',
      n: 4,
      to: '/app/accounts/7/dashboard?tab=me&status=open',
    });
    expect(nowChips(null, 7)).toEqual([]);
    expect(chipRoute('waiting', 7)).toBe(
      '/app/accounts/7/unattended/conversations'
    );
    expect(chipRoute('nope', 7)).toBeNull();
  });

  it('turns the AI state into a view-only pill', () => {
    expect(aiPill('shadow')).toEqual({ key: 'SHADOW', tone: 'shadow' });
    expect(aiPill('off').key).toBe('OFF');
    expect(aiPill('weird').key).toBe('UNKNOWN');
    expect(aiPill(undefined)).toBeNull();
  });

  it('only accepts known tabs and statuses from the URL', () => {
    expect(tzQuickView({ tab: 'unassigned', status: 'snoozed' })).toEqual({
      tab: 'unassigned',
      status: 'snoozed',
    });
    expect(tzQuickView({ tab: '<x>', status: 'gone' })).toEqual({
      tab: null,
      status: null,
    });
    expect(tzQuickView(undefined)).toEqual({ tab: null, status: null });
  });
});
