import { describe, it, expect } from 'vitest';
import { firstReplySeries, niceMax, liveStatus } from '../tolzarDashboardData';

const DAY = 86400;
const NOW = 20000 * DAY + 3600;

describe('tolzarDashboardData', () => {
  it('makes one bar per day, oldest first, with gaps for days without replies', () => {
    const s = firstReplySeries(
      [
        { timestamp: 20000 * DAY, value: 300 },
        { timestamp: 19998 * DAY, value: 90 },
      ],
      3,
      NOW
    );
    expect(s.map(p => p.minutes)).toEqual([1.5, null, 5]);
    expect(s[2].day).toBe(20000 * DAY);
  });

  it('rounds the axis maximum up', () => {
    expect(niceMax([3.2, null, 7.9])).toBe(8);
    expect(niceMax([42])).toBe(50);
    expect(niceMax([null])).toBe(1);
  });

  it('labels a conversation by person, team or waiting', () => {
    expect(liveStatus({ meta: { assignee: { name: 'Mona' } } })).toEqual({
      key: 'assigned',
      who: 'Mona',
    });
    expect(liveStatus({ meta: { team: { name: 'Sales' } } })).toEqual({
      key: 'team',
      who: 'Sales',
    });
    expect(liveStatus({})).toEqual({ key: 'waiting', who: '' });
  });
});
