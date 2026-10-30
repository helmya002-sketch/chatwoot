import {
  HOT_SCORE,
  attentionCounts,
  attentionRows,
  reasonsFor,
} from '../tolzarAttention';

const conv = (id, over = {}) => ({
  id,
  status: 'open',
  first_reply_created_at: 1700000000,
  waiting_since: 1700000000 + id,
  created_at: 1700000000,
  meta: {
    sender: { name: `C${id}`, custom_attributes: {} },
    assignee: { name: 'Ana' },
  },
  ...over,
});

describe('tolzarAttention', () => {
  it('names every reason a conversation needs a person, hot first', () => {
    expect(reasonsFor(conv(1))).toEqual([]);
    expect(
      reasonsFor(
        conv(2, {
          first_reply_created_at: 0,
          meta: {
            sender: { custom_attributes: { tolzar_lead_score: HOT_SCORE } },
          },
        })
      )
    ).toEqual(['hot', 'waiting', 'unassigned']);
    expect(reasonsFor(conv(3, { meta: { sender: {} } }))).toEqual([
      'unassigned',
    ]);
  });

  it('ignores resolved conversations and unscored contacts', () => {
    expect(reasonsFor(conv(1, { status: 'resolved', meta: {} }))).toEqual([]);
    expect(
      reasonsFor(
        conv(1, {
          meta: {
            sender: { custom_attributes: { tolzar_lead_score: '' } },
            assignee: { name: 'x' },
          },
        })
      )
    ).toEqual([]);
    expect(
      reasonsFor(
        conv(1, {
          meta: {
            sender: { custom_attributes: { tolzar_lead_score: 69.4 } },
            assignee: { name: 'x' },
          },
        })
      )
    ).toEqual([]);
    expect(reasonsFor(null)).toEqual([]);
  });

  it('orders rows hot by score, then the longest waiting, and caps them', () => {
    const list = [
      conv(1, { first_reply_created_at: 0, waiting_since: 50 }),
      conv(2, { first_reply_created_at: 0, waiting_since: 10 }),
      conv(3, {
        meta: {
          sender: {
            name: 'Hot 80',
            custom_attributes: { tolzar_lead_score: 80 },
          },
          assignee: { name: 'A' },
        },
      }),
      conv(4, {
        meta: {
          sender: {
            name: 'Hot 95',
            custom_attributes: { tolzar_lead_score: 95 },
          },
          assignee: { name: 'A' },
        },
      }),
      conv(5, { meta: { sender: { name: 'Nobody' } } }),
      conv(6),
    ];
    const rows = attentionRows(list);
    expect(rows.map(r => r.id)).toEqual([4, 3, 2, 1, 5]);
    expect(rows[0]).toMatchObject({
      name: 'Hot 95',
      score: 95,
      reasons: ['hot'],
    });
    expect(rows[4].reasons).toEqual(['unassigned']);
    expect(attentionRows(list, { limit: 2 }).map(r => r.id)).toEqual([4, 3]);
    expect(attentionRows(undefined)).toEqual([]);
  });

  it('counts each reason across the list', () => {
    const list = [
      conv(1, { first_reply_created_at: 0, meta: { sender: {} } }),
      conv(2, {
        meta: {
          sender: { custom_attributes: { tolzar_lead_score: 71 } },
          assignee: { name: 'A' },
        },
      }),
      conv(3),
    ];
    expect(attentionCounts(list)).toEqual({
      hot: 1,
      waiting: 1,
      unassigned: 1,
    });
    expect(attentionCounts([])).toEqual({ hot: 0, waiting: 0, unassigned: 0 });
  });
});
