import {
  newStep,
  stepSummary,
  conditionText,
  stepMeta,
  textOf,
  uid,
  waitParts,
  waitMinutes,
  duplicateWorkflow,
  runTone,
  workspaceLanguages,
  pickLang,
  normaliseBranches,
  STEP_TYPES,
} from './tolzarWorkflows';

// Tolzar smoke tests (A2) for the Workflows builder helpers.
describe('tolzarWorkflows', () => {
  it('builds new steps the brain accepts', () => {
    const b = newStep('branch');
    expect(b.config.then).toEqual([]);
    expect(b.config.else).toEqual([]);
    expect(b.config.conditions).toEqual([{ kind: 'replied' }]);
    expect(newStep('wait').config.minutes).toBe(1440);
    expect(newStep('send_message').config.text).toEqual({ en: '' });
    expect(newStep('wait').id).not.toBe(newStep('wait').id);
    expect(newStep('nope').config).toEqual({});
  });

  it('gives ids that do not collide and keep the step prefix', () => {
    const ids = new Set(Array.from({ length: 200 }, uid));
    expect(ids.size).toBe(200);
    ids.forEach(id => expect(id.startsWith('s')).toBe(true));
  });

  it('summarises every step type for the canvas', () => {
    expect(stepSummary({ type: 'wait', config: { minutes: 4320, until_reply: true } })).toBe('3 d · or a reply');
    expect(stepSummary({ type: 'wait', config: { minutes: 90 } })).toBe('90 min');
    expect(stepSummary({ type: 'send_message', config: { text: { de: 'Hallo', en: 'Hi' } } })).toBe('Hi');
    expect(stepSummary({ type: 'comment', config: { text: 'note' } })).toBe('note');
    expect(
      stepSummary({
        type: 'branch',
        config: { match: 'any', conditions: [{ kind: 'replied' }, { kind: 'has_tag', tag: 'vip' }] },
      })
    ).toBe('replied or #vip');
    expect(stepSummary({ type: 'add_tag', config: { tag: 'hot' } })).toBe('hot');
    expect(stepSummary({ type: 'ai_tag', config: { tags: [{ tag: 'a' }, { tag: 'b' }] } })).toBe('a, b');
    expect(stepSummary({ type: 'update_field', config: { field: 'city', value: 'Rome' } })).toBe('city = Rome');
    expect(stepSummary({ type: 'update_stage', config: { stage: 'Active' } })).toBe('Active');
    expect(stepSummary({ type: 'assign_team', config: { team_id: 7 } })).toBe('7');
    expect(stepSummary({ type: 'assign_team', config: { team: 'Sales', team_id: 7 } })).toBe('Sales');
    expect(stepSummary({ type: 'record_score', config: {} })).toBe('nps');
    expect(stepSummary({ type: 'close', config: {} })).toBe('');
    expect(stepSummary({ type: 'unknown' })).toBe('');
    expect(conditionText({ kind: 'reply_number', min: 9, max: 10 })).toBe('reply 9–10');
    expect(conditionText({ kind: 'field_empty', field: 'email' })).toBe('email empty');
    expect(textOf('plain')).toBe('plain');
  });

  it('labels unknown steps safely and gives every type theme classes', () => {
    expect(stepMeta('nope').label).toBe('TOLZAR_WORKFLOWS.STEP.nope');
    expect(stepMeta('nope').text).toBe('text-n-slate-11');
    STEP_TYPES.forEach(s => {
      const m = stepMeta(s.type);
      expect(m.text).toMatch(/^text-n-/);
      expect(m.top).toMatch(/^border-t-n-/);
    });
  });

  it('round-trips wait values without flipping the unit', () => {
    expect(waitParts(1440)).toEqual({ n: 1, unit: 1440 });
    expect(waitParts(120)).toEqual({ n: 2, unit: 60 });
    expect(waitParts(90)).toEqual({ n: 90, unit: 1 });
    expect(waitParts(0)).toEqual({ n: 0, unit: 1 });
    expect(waitMinutes(2, 1440)).toBe(2880);
    expect(waitMinutes(1.5, 1440)).toBe(2880);
    expect(waitMinutes(0, 60)).toBe(60);
    expect(waitMinutes('', 1)).toBe(1);
    expect(waitMinutes(3, 999)).toBe(3);
    // the unit the user typed in survives a round trip through minutes
    const m = waitMinutes(36, 60);
    expect(waitParts(m)).toEqual({ n: 36, unit: 60 });
  });

  it('duplicates a workflow with a new id, copy suffix and fresh step ids', () => {
    const branch = newStep('branch');
    branch.config.then.push(newStep('close'));
    const original = {
      id: 'wf1',
      name: 'Welcome',
      status: 'shadow',
      updated_at: '2026-10-30T00:00:00Z',
      trigger: { type: 'first_message' },
      steps: [newStep('send_message'), branch],
      settings: { a: '1' },
    };
    const copy = duplicateWorkflow(original);
    expect(copy.id).not.toBe('wf1');
    expect(copy.name).toBe('Welcome (copy)');
    expect(copy.status).toBe('draft');
    expect(copy.updated_at).toBeUndefined();
    expect(copy.steps).toHaveLength(2);
    expect(copy.steps[0].id).not.toBe(original.steps[0].id);
    expect(copy.steps[1].config.then[0].id).not.toBe(branch.config.then[0].id);
    expect(copy.steps[1].config.else).toEqual([]);
    expect(copy.settings).toEqual({ a: '1' });
    // the original is untouched
    expect(original.name).toBe('Welcome');
    expect(original.status).toBe('shadow');
    expect(duplicateWorkflow({ name: '' }).name).toBe('(copy)');
  });

  it('normalises branches saved without arms', () => {
    const steps = [{ id: 'b', type: 'branch', config: { conditions: [] } }];
    normaliseBranches(steps);
    expect(steps[0].config.then).toEqual([]);
    expect(steps[0].config.else).toEqual([]);
  });

  it('maps run statuses to tones', () => {
    expect(runTone('done')).toBe('ok');
    expect(runTone('failed')).toBe('bad');
    expect(runTone('cancelled')).toBe('muted');
    expect(runTone('waiting_reply')).toBe('warn');
    expect(runTone(undefined)).toBe('warn');
  });

  it('reads the workspace languages as clean codes', () => {
    expect(workspaceLanguages({ merged: { languages: ['EN', ' de', 'pt-BR', 'nope!', 'en'] } })).toEqual([
      'en',
      'de',
      'pt-br',
    ]);
    expect(workspaceLanguages({ merged: { languages: 'en, ar\nfr' } })).toEqual(['en', 'ar', 'fr']);
    expect(workspaceLanguages(null)).toEqual([]);
    expect(pickLang(['en', 'de'], 'de')).toBe('de');
    expect(pickLang(['en', 'de'], 'fr')).toBe('en');
    expect(pickLang([], 'fr')).toBe('');
  });
});
