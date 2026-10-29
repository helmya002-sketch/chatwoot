import {
  SKILL_TYPES,
  MAX_LIST,
  MAX_WHEN,
  skillType,
  skillFromSaved,
  skillsFromAgent,
  skillsToAgent,
  newSkill,
  parseTags,
  skillProblems,
  blocksSave,
  toggleValue,
} from '../tolzarSkills';

describe('tolzarSkills shape mapping', () => {
  it('maps the old type names like the brain', () => {
    expect(skillType('tags')).toBe('add_tag');
    expect(skillType('update_lifecycle')).toBe('change_stage');
    expect(skillType('workflow')).toBe('trigger_workflow');
    expect(skillType('assign')).toBe('assign');
  });

  it('loads the old {type, config: "text"} shape: the text becomes when', () => {
    expect(skillFromSaved({ type: 'tags', config: 'Tag VIP buyers' })).toEqual({
      type: 'add_tag',
      enabled: true,
      when: 'Tag VIP buyers',
      config: { tags: [] },
    });
    expect(skillFromSaved({ type: 'close', config: '' })).toEqual({
      type: 'close',
      enabled: true,
      when: '',
      config: {},
    });
  });

  it('drops comment and unknown types, keeps one skill per type', () => {
    expect(skillFromSaved({ type: 'comment', config: 'x' })).toBeNull();
    expect(skillFromSaved(null)).toBeNull();
    const form = skillsFromAgent({
      skills: [
        { type: 'tags', config: 'first' },
        { type: 'add_tag', when: 'second', config: { tags: ['vip'] } },
        { type: 'comment', config: 'note' },
      ],
    });
    expect(form.skills).toHaveLength(1);
    expect(form.skills[0].when).toBe('first');
  });

  it('defaults: skills off, workflow dry run on', () => {
    expect(skillsFromAgent({})).toEqual({
      skills_enabled: false,
      skills_dry_run_workflows: true,
      skills: [],
    });
    const f = skillsFromAgent({
      skills_enabled: true,
      skills_dry_run_workflows: false,
    });
    expect(f.skills_enabled).toBe(true);
    expect(f.skills_dry_run_workflows).toBe(false);
  });

  it('loads the new shape and keeps team ids numeric', () => {
    const s = skillFromSaved({
      type: 'assign',
      enabled: false,
      when: 'A group booking',
      config: { team_ids: ['3', 4, 4], agent_names: [' Reham ', ''] },
    });
    expect(s).toEqual({
      type: 'assign',
      enabled: false,
      when: 'A group booking',
      config: { team_ids: [3, 4], agent_names: ['Reham'] },
    });
  });

  it('saves exactly the brain shape for every type', () => {
    const form = {
      skills_enabled: true,
      skills_dry_run_workflows: true,
      skills: SKILL_TYPES.map(t => ({
        ...newSkill(t),
        when: `  when   ${t} `,
      })),
    };
    form.skills[0].config.team_ids = [3];
    form.skills[1].config.contact_fields = ['hotel'];
    form.skills[2].config.stages = ['Customer Won'];
    form.skills[4].config.tags = ['vip'];
    form.skills[5].config.workflow_ids = ['wf-1'];
    const out = skillsToAgent(form);
    expect(out.skills_enabled).toBe(true);
    expect(out.skills_dry_run_workflows).toBe(true);
    expect(out.skills.map(s => s.type)).toEqual(SKILL_TYPES);
    expect(out.skills[0]).toEqual({
      type: 'assign',
      enabled: true,
      when: 'when assign',
      config: { team_ids: [3], agent_names: [] },
    });
    expect(out.skills[1].config).toEqual({
      contact_fields: ['hotel'],
      conversation_fields: [],
    });
    expect(out.skills[3].config).toEqual({});
    expect(out.skills[5].config).toEqual({ workflow_ids: ['wf-1'] });
  });

  it('round-trips an old draft into the new shape', () => {
    const out = skillsToAgent(
      skillsFromAgent({
        skills: [{ type: 'workflow', config: 'After a sale' }],
      })
    );
    expect(out).toEqual({
      skills_enabled: false,
      skills_dry_run_workflows: true,
      skills: [
        {
          type: 'trigger_workflow',
          enabled: true,
          when: 'After a sale',
          config: { workflow_ids: [] },
        },
      ],
    });
  });

  it('parses free-text tags and toggles picker values', () => {
    expect(parseTags('vip, follow-up ,vip,, ')).toEqual(['vip', 'follow-up']);
    expect(toggleValue([1, 2], 2)).toEqual([1]);
    expect(toggleValue([1], 3)).toEqual([1, 3]);
    expect(toggleValue(undefined, 'a')).toEqual(['a']);
  });
});

describe('tolzarSkills validation', () => {
  const form = skills => ({ skills_enabled: true, skills });

  it('an enabled skill needs allowed values, except close', () => {
    expect(skillProblems(form([newSkill('add_tag')]))).toEqual([
      { index: 0, type: 'add_tag', error: 'needs_values' },
    ]);
    expect(skillProblems(form([newSkill('close')]))).toEqual([]);
    const off = { ...newSkill('assign'), enabled: false };
    expect(skillProblems(form([off]))).toEqual([]);
    const ok = newSkill('update_fields');
    ok.config.conversation_fields = ['arrival_date'];
    expect(skillProblems(form([ok]))).toEqual([]);
  });

  it('limits when, list sizes, duplicates and the skill count', () => {
    const long = { ...newSkill('close'), when: 'x'.repeat(MAX_WHEN + 1) };
    expect(skillProblems(form([long]))[0].error).toBe('when_too_long');
    const many = newSkill('add_tag');
    many.config.tags = Array.from({ length: MAX_LIST + 1 }, (_, i) => `t${i}`);
    expect(skillProblems(form([many]))[0].error).toBe('too_many_values');
    const dup = skillProblems(form([newSkill('close'), newSkill('close')]));
    expect(dup).toEqual([{ index: 1, type: 'close', error: 'duplicate' }]);
    const nine = Array.from({ length: 9 }, () => newSkill('close'));
    expect(skillProblems(form(nine))[0]).toEqual({
      index: -1,
      type: '',
      error: 'too_many_skills',
    });
  });

  it('blocks saving only while skills are switched on', () => {
    const draft = [newSkill('add_tag')];
    expect(blocksSave(form(draft))).toBe(true);
    expect(blocksSave({ skills_enabled: false, skills: draft })).toBe(false);
    expect(blocksSave(form([newSkill('close')]))).toBe(false);
  });
});
