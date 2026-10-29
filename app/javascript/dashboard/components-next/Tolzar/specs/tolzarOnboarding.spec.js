import {
  NONE_PACK,
  emptyForm,
  parseLanguages,
  bootstrapBody,
  formProblems,
  bootstrapOutcome,
  checklistLink,
  checklistItems,
  checklistProgress,
  bootstrapWorkspace,
  getChecklist,
} from '../tolzarOnboarding';

const form = over => ({
  ...emptyForm(),
  workspaceName: ' Blue Reef ',
  timezone: 'Africa/Cairo',
  closedDays: [6, 4],
  languages: 'EN, de ,en',
  ...over,
});

describe('tolzarOnboarding bootstrap body', () => {
  it('parses language codes', () => {
    expect(parseLanguages('EN, de ,en  ar')).toEqual(['en', 'de', 'ar']);
    expect(parseLanguages('')).toEqual([]);
  });

  it('builds exactly the brain fields, without account or owner', () => {
    const body = bootstrapBody(
      form({ template: 'tpl-support', agentName: ' Mia ' })
    );
    expect(body).toEqual({
      workspace_name: 'Blue Reef',
      timezone: 'Africa/Cairo',
      working_hours: { start: '09:00', end: '18:00', closed_days: [4, 6] },
      languages: ['en', 'de'],
      pack: NONE_PACK,
      template: 'tpl-support',
      agent_name: 'Mia',
    });
    expect(body).not.toHaveProperty('account_id');
    expect(body).not.toHaveProperty('owner_user_id');
    expect(body).not.toHaveProperty('status');
  });

  it('leaves out an empty template and empty languages', () => {
    const body = bootstrapBody(
      form({ template: '', languages: ' ', agentName: '' })
    );
    expect(body).not.toHaveProperty('template');
    expect(body).not.toHaveProperty('languages');
    expect(body.agent_name).toBe('Assistant');
    expect(bootstrapBody(form({ pack: '' })).pack).toBe('none');
  });

  it('says what is missing before sending', () => {
    expect(formProblems(form())).toEqual([]);
    expect(
      formProblems(form({ workspaceName: ' ', timezone: '', start: '9' }))
    ).toEqual([
      { path: 'workspace_name', error: 'required' },
      { path: 'timezone', error: 'required' },
      { path: 'working_hours', error: 'hours' },
    ]);
  });
});

describe('tolzarOnboarding outcomes', () => {
  it('maps the brain answers', () => {
    expect(bootstrapOutcome({ ok: true })).toBe('done');
    [
      'already_bootstrapped',
      'settings_exist',
      'workspace_has_config_file',
    ].forEach(error =>
      expect(bootstrapOutcome({ ok: false, error })).toBe('already')
    );
    expect(bootstrapOutcome({ ok: false, error: 'invalid_settings' })).toBe(
      'invalid'
    );
    expect(bootstrapOutcome({ ok: false, error: 'owner_only' })).toBe(
      'owner_only'
    );
    expect(bootstrapOutcome({ ok: false, error: 'brain_unreachable' })).toBe(
      'error'
    );
    expect(bootstrapOutcome(undefined)).toBe('error');
  });
});

describe('tolzarOnboarding checklist', () => {
  it('links every action hint to its screen', () => {
    expect(checklistLink('workspace_settings', 7)).toEqual({
      name: 'tolzar_settings',
      query: { section: 'workspace_settings' },
    });
    expect(checklistLink('choose_pack', 7).query.section).toBe(
      'workspace_settings'
    );
    expect(checklistLink('agents', 7)).toEqual({ name: 'tolzar_ai_agents' });
    expect(checklistLink('knowledge_refresh', 7)).toEqual({
      name: 'tolzar_ai_agents',
    });
    expect(checklistLink('price_source', 7)).toEqual({
      name: 'tolzar_ai_agents',
    });
    expect(checklistLink('add_inbox', 7)).toBe(
      '/app/accounts/7/settings/inboxes/new'
    );
    expect(checklistLink('compliance', 7).query.section).toBe('disclosure');
    expect(checklistLink('owner', 7).query.section).toBe('roles');
    expect(checklistLink('go_live_review', 7).query.section).toBe('go_live');
    expect(checklistLink('unknown', 7)).toBeNull();
  });

  it('orders required items first and counts only them', () => {
    const data = {
      items: [
        { key: 'live_ready', done: false, required: false },
        { key: 'settings', done: true, required: true },
        { key: 'agent', done: false, required: true },
        null,
      ],
    };
    expect(checklistItems(data).map(i => i.key)).toEqual([
      'settings',
      'agent',
      'live_ready',
    ]);
    expect(checklistProgress(data)).toEqual({ done: 1, total: 2 });
    expect(checklistItems({})).toEqual([]);
  });
});

describe('tolzarOnboarding API', () => {
  beforeEach(() => {
    window.axios = { get: vi.fn(), post: vi.fn() };
  });

  it('posts the bootstrap to the proxy and returns a refusal as data', async () => {
    window.axios.post.mockRejectedValue({
      response: {
        status: 409,
        data: { ok: false, error: 'already_bootstrapped' },
      },
    });
    const res = await bootstrapWorkspace(3, { workspace_name: 'x' });
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/3/tolzar/workspace/bootstrap',
      { workspace_name: 'x' }
    );
    expect(res.error).toBe('already_bootstrapped');
  });

  it('reads the checklist', async () => {
    window.axios.get.mockResolvedValue({ data: { ok: true, items: [] } });
    expect(await getChecklist(3)).toEqual({ ok: true, items: [] });
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/3/tolzar/workspace/checklist'
    );
  });

  it('throws on a network failure', async () => {
    window.axios.get.mockRejectedValue(new Error('offline'));
    await expect(getChecklist(3)).rejects.toThrow('offline');
  });
});
