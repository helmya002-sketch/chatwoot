import { reasonKey, reasonLabels, parseAgentTest } from '../tolzarAgentTest';

describe('tolzarAgentTest', () => {
  it('maps the common reason codes to labels and keeps the rest raw', () => {
    expect(reasonKey('negotiation:semantic_offer')).toBe(
      'TOLZAR_AGENT_TEST.REASON.SEMANTIC_OFFER'
    );
    expect(reasonKey('negotiation:check_unavailable')).toBe(
      'TOLZAR_AGENT_TEST.REASON.CHECK_UNAVAILABLE'
    );
    expect(reasonKey('output_policy:link')).toBe(
      'TOLZAR_AGENT_TEST.REASON.LINK'
    );
    expect(reasonKey('output_policy:commitment')).toBe(
      'TOLZAR_AGENT_TEST.REASON.COMMITMENT'
    );
    expect(reasonKey('price_guard:unsupported:120')).toBe(
      'TOLZAR_AGENT_TEST.REASON.PRICE'
    );
    expect(reasonKey('output_policy:leak')).toBeNull();
    expect(reasonKey(null)).toBeNull();
    const t = k => `T(${k})`;
    expect(
      reasonLabels(
        [
          'price_guard:unsupported:120',
          'price_guard:replaced_model_reply',
          'reply_filter:replaced',
        ],
        t
      )
    ).toEqual(['T(TOLZAR_AGENT_TEST.REASON.PRICE)', 'reply_filter:replaced']);
    expect(reasonLabels(undefined, t)).toEqual([]);
  });

  it('shows the final reply and keeps the draft and reasons only when replaced', () => {
    const m = parseAgentTest({
      ok: true,
      reply: 'A colleague will confirm the price.',
      draft: 'For you 20% off!',
      replaced: true,
      reasons: ['negotiation:semantic_offer'],
      model: 'qwen2.5:7b',
      latency_ms: 31240,
    });
    expect(m).toEqual({
      who: 'agent',
      text: 'A colleague will confirm the price.',
      meta: 'qwen2.5:7b · 31.2s',
      replaced: true,
      draft: 'For you 20% off!',
      reasons: ['negotiation:semantic_offer'],
    });
    const same = parseAgentTest({
      ok: true,
      reply: 'Hi!',
      draft: 'Hi!',
      replaced: false,
      reasons: [],
      model: 'qwen2.5:7b',
    });
    expect(same).toMatchObject({
      text: 'Hi!',
      meta: 'qwen2.5:7b',
      replaced: false,
      draft: '',
      reasons: [],
    });
  });

  it('never marks an error answer as replaced', () => {
    expect(
      parseAgentTest({ ok: false, reply: 'model off', replaced: true })
    ).toMatchObject({
      text: 'model off',
      meta: '',
      replaced: false,
      reasons: [],
    });
    expect(parseAgentTest(null)).toMatchObject({ text: '', replaced: false });
  });
});
