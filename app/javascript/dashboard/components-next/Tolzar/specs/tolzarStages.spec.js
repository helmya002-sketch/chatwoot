import {
  STAGES,
  applyPipelineStages,
  parsePipelineStages,
  leadScore,
  scoreTone,
  stageClass,
  stageOf,
} from '../tolzarStages';

describe('tolzarStages', () => {
  it('keeps the five stored lifecycle values in funnel order', () => {
    expect(STAGES.map(s => s.key)).toEqual([
      'New Lead',
      'Active',
      'Offer Sent Follow up',
      'Customer Won',
      'Customer Lost',
    ]);
  });

  it('labels stored values for people', () => {
    expect(stageOf('Offer Sent Follow up').label).toBe('Offer Sent');
    expect(stageOf('Customer Won').label).toBe('Won');
  });

  it('defaults a missing stage to New Lead and keeps unknown ones readable', () => {
    expect(stageOf(undefined).key).toBe('New Lead');
    expect(stageOf('Qualified')).toEqual({
      key: 'Qualified',
      label: 'Qualified',
      tone: 'slate',
    });
    expect(stageClass('Qualified')).toBe(stageClass('New Lead'));
  });

  it('reads the brain lead score, or null when unscored', () => {
    expect(leadScore({ tolzar_lead_score: '86' })).toBe(86);
    expect(leadScore({ tolzar_lead_score: 71.6 })).toBe(72);
    expect(leadScore({})).toBeNull();
    expect(leadScore({ tolzar_lead_score: '' })).toBeNull();
    expect(leadScore({ tolzar_lead_score: 'n/a' })).toBeNull();
  });

  it('colours strong, warm and cool scores differently', () => {
    const tones = [scoreTone(90), scoreTone(60), scoreTone(20)];
    expect(new Set(tones).size).toBe(3);
  });

  it('reads the workspace pipeline_stages setting, else keeps the defaults', () => {
    applyPipelineStages({
      pipeline_stages: [
        'New Lead',
        { key: 'Qualified', label: 'Qual', tone: 'teal' },
        '',
        'New Lead',
      ],
    });
    expect(STAGES.map(s => s.key)).toEqual(['New Lead', 'Qualified']);
    expect(stageOf('Qualified')).toEqual({
      key: 'Qualified',
      label: 'Qual',
      tone: 'teal',
    });
    expect(parsePipelineStages('nope')).toBeNull();
    expect(parsePipelineStages([{ key: 'X', tone: 'neon' }])[0].tone).toBe(
      'slate'
    );
    applyPipelineStages({ pipeline_stages: [] });
    expect(STAGES.length).toBe(5);
    applyPipelineStages(undefined);
    expect(STAGES[0].key).toBe('New Lead');
  });
});
