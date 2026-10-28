import { newStep, stepSummary, conditionText, stepMeta, textOf } from './tolzarWorkflows';

// Tolzar smoke tests (A2) for the Workflows builder helpers.
describe('tolzarWorkflows', () => {
  it('builds new steps the brain accepts', () => {
    const b = newStep('branch');
    expect(b.config.then).toEqual([]);
    expect(b.config.else).toEqual([]);
    expect(newStep('wait').config.minutes).toBe(1440);
    expect(newStep('send_message').config.text).toEqual({ en: '' });
    expect(newStep('wait').id).not.toBe(newStep('wait').id);
  });

  it('summarises steps for the canvas', () => {
    expect(stepSummary({ type: 'wait', config: { minutes: 4320, until_reply: true } })).toBe('3 d · or a reply');
    expect(stepSummary({ type: 'send_message', config: { text: { de: 'Hallo', en: 'Hi' } } })).toBe('Hi');
    expect(conditionText({ kind: 'reply_number', min: 9, max: 10 })).toBe('reply 9–10');
    expect(textOf('plain')).toBe('plain');
  });

  it('labels unknown steps safely', () => {
    expect(stepMeta('nope').label).toBe('TOLZAR_WORKFLOWS.STEP.nope');
  });
});
