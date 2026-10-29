import {
  STAGES,
  applyPipelineStages,
  parsePipelineStages,
  leadScore,
  scoreTone,
  stageClass,
  stageOf,
  contactStage,
  stageConditions,
  stageOfConditions,
  STAGE_ATTRIBUTES,
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

describe('stage attributes', () => {
  afterEach(() => applyPipelineStages({}));

  it('reads the Tolzar stage first, then the imported one', () => {
    expect(
      contactStage({ lifecycle_stage: 'Active', rio_lifecycle: 'Customer Won' })
    ).toBe('Active');
    expect(contactStage({ rio_lifecycle: 'Customer Won' })).toBe(
      'Customer Won'
    );
    expect(contactStage({ lifecycle_stage: '' })).toBe('');
    expect(contactStage(undefined)).toBe('');
  });

  it('builds conditions where AND binds tighter than OR, last operator null', () => {
    const c = stageConditions('Active');
    expect(
      c.map(x => [x.attribute_key, x.filter_operator, x.query_operator])
    ).toEqual([
      ['lifecycle_stage', 'equal_to', 'or'],
      ['lifecycle_stage', 'is_not_present', 'and'],
      ['rio_lifecycle', 'equal_to', null],
    ]);
    expect(stageOfConditions(c)).toBe('Active');
  });

  it('lets the default stage take contacts with no stage at all', () => {
    const c = stageConditions('New Lead');
    expect(
      c
        .slice(-3)
        .map(x => [x.attribute_key, x.filter_operator, x.query_operator])
    ).toEqual([
      ['rio_lifecycle', 'equal_to', 'or'],
      ['lifecycle_stage', 'is_not_present', 'and'],
      ['rio_lifecycle', 'is_not_present', null],
    ]);
  });

  it('follows the stage_attributes setting and ignores bad keys', () => {
    applyPipelineStages({ stage_attributes: ['deal_stage', 'Bad Key!'] });
    expect([...STAGE_ATTRIBUTES]).toEqual(['deal_stage']);
    expect(stageConditions('Active')).toHaveLength(1);
    expect(
      stageOfConditions([
        { attribute_key: 'email', filter_operator: 'equal_to', values: ['x'] },
      ])
    ).toBe('');
  });
});
