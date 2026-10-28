import {
  getIn,
  workspaceFields,
  formFromView,
  buildPatch,
  isEmptyPatch,
  fieldErrors,
  isConflict,
  isInvalid,
  isOwner,
  parseReason,
  parseReasons,
  inboxModes,
  anyLive,
  confirmName,
  confirmMatches,
  priceSourceForm,
  priceSourceProblems,
  priceSourceBody,
  sampleColumns,
  agentPrices,
  getWorkspaceSettings,
  saveWorkspaceSettings,
  goLive,
  killSwitch,
  getPriceSource,
  savePriceSource,
  testPriceSource,
} from '../tolzarWorkspace';

const view = () => ({
  version: 4,
  viewer_role: 'owner',
  account_name: 'Blue Reef',
  defaults: {
    timezone: 'UTC',
    languages: ['en'],
    working_hours: {
      start: '09:00:00',
      end: '18:00:00',
      closed_days: [],
      holidays: [],
    },
    bot: { display_name: 'Assistant' },
    budgets: { max_llm_calls_per_conversation: 6, max_llm_calls_per_day: 3000 },
    templates: { after_hours: { en: 'We are closed.' } },
    destinations: { north: { name: null, team: 'sales' } },
    categories: [{ key: 'sales_lead', description: 'Wants to buy' }],
    teams: { sales: 1 },
  },
  overrides: {
    timezone: 'Europe/Berlin',
    working_hours: { start: '08:00' },
    categories: { sales_lead: { description: 'Buyer' } },
  },
  merged: {
    timezone: 'Europe/Berlin',
    languages: ['en', 'de'],
    working_hours: {
      start: '08:00:00',
      end: '18:00:00',
      closed_days: [],
      holidays: [],
    },
    templates: { after_hours: { en: 'We are closed.' } },
    destinations: { north: { name: null, team: 'sales' } },
    categories: [{ key: 'sales_lead', description: 'Buyer' }],
    teams: { sales: 1 },
    skills: { triage: { mode: 'shadow', inbox_modes: { 7: 'eval' } } },
  },
  inbox_modes: {},
});
const field = (v, path) => workspaceFields(v).find(f => f.path === path);

describe('tolzarWorkspace settings', () => {
  it('reads dotted paths, categories by key in lists and objects', () => {
    const v = view();
    expect(getIn(v.defaults, 'working_hours.start')).toBe('09:00:00');
    expect(getIn(v.defaults, 'categories.sales_lead.description')).toBe(
      'Wants to buy'
    );
    expect(getIn(v.overrides, 'categories.sales_lead.description')).toBe(
      'Buyer'
    );
    expect(getIn(v.defaults, 'nope.deeper')).toBeUndefined();
  });

  it('lists the editable fields of this workspace', () => {
    const paths = workspaceFields(view()).map(f => f.path);
    expect(paths).toEqual(
      expect.arrayContaining([
        'working_hours.closed_days',
        'working_hours.holidays',
        'templates.after_hours.en',
        'templates.after_hours.de',
        'destinations.north.name',
        'categories.sales_lead.description',
        'team_descriptions.sales',
      ])
    );
  });

  it('fills the form with overrides over defaults, times as HH:MM', () => {
    const form = formFromView(view());
    expect(form['working_hours.start']).toBe('08:00');
    expect(form['working_hours.end']).toBe('18:00');
    expect(form.timezone).toBe('Europe/Berlin');
    expect(form['working_hours.holidays']).toBe('');
    expect(form.languages).toBe('en');
    expect(form['team_descriptions.sales']).toBe('');
  });

  it('sends only what changed; back to the default unsets', () => {
    const v = view();
    const form = formFromView(v);
    expect(isEmptyPatch(buildPatch(v, form))).toBe(true);

    form['working_hours.end'] = '17:30';
    form['working_hours.holidays'] = '2026-12-25\n 2026-12-31 \n';
    form['working_hours.closed_days'] = [6, 5, 6];
    form['working_hours.start'] = '09:00'; // the default again
    form['budgets.max_llm_calls_per_day'] = '500';
    form.languages = 'en, de';
    expect(buildPatch(v, form)).toEqual({
      version: 4,
      set: {
        'working_hours.end': '17:30',
        'working_hours.holidays': ['2026-12-25', '2026-12-31'],
        'working_hours.closed_days': [5, 6],
        'budgets.max_llm_calls_per_day': 500,
        languages: ['en', 'de'],
      },
      unset: ['working_hours.start'],
    });
  });

  it('"Reset to default" unsets an override and ignores a field without one', () => {
    const v = view();
    const p = buildPatch(v, formFromView(v), workspaceFields(v), [
      'timezone',
      'categories.sales_lead.description',
      'bot.display_name',
    ]);
    expect(p.set).toEqual({});
    expect(p.unset).toEqual(['timezone', 'categories.sales_lead.description']);
  });

  it('puts the 400 errors on their fields', () => {
    const fields = workspaceFields(view());
    const res = {
      ok: false,
      error: 'invalid_settings',
      errors: [
        { path: 'timezone', error: 'not an IANA timezone' },
        { path: 'working_hours', error: 'end before start' },
        { path: 'settings', error: 'too large' },
      ],
    };
    const { byPath, other } = fieldErrors(res, fields);
    expect(byPath.timezone).toBe('not an IANA timezone');
    expect(byPath['working_hours.end']).toBe('end before start');
    expect(other).toEqual(['settings: too large']);
    expect(isInvalid(res)).toBe(true);
    expect(isConflict({ error: 'version_conflict', version: 5 })).toBe(true);
    expect(isConflict(res)).toBe(false);
    expect(isOwner(view())).toBe(true);
    expect(isOwner({ viewer_role: 'manager' })).toBe(false);
    expect(field(view(), 'timezone').kind).toBe('select');
  });
});

describe('tolzarWorkspace go-live', () => {
  it('reads reason codes, team prefixes and unknown codes', () => {
    expect(parseReason('no_price_table')).toMatchObject({
      code: 'no_price_table',
      team: null,
      known: true,
    });
    expect(parseReason('team sales: no_price_table')).toMatchObject({
      code: 'no_price_table',
      team: 'sales',
      known: true,
    });
    expect(parseReason('team_agent:no_price_table')).toMatchObject({
      code: 'no_price_table',
      team: '',
      known: true,
    });
    expect(parseReason('something_new')).toMatchObject({
      code: 'something_new',
      known: false,
      raw: 'something_new',
    });
    expect(
      parseReasons({ reasons: ['legacy_path', 'mirror_inbox'] }).map(
        r => r.code
      )
    ).toEqual(['legacy_path', 'mirror_inbox']);
    expect(parseReasons(null)).toEqual([]);
  });

  it('shows every inbox in Shadow unless the brain says otherwise', () => {
    const v = view();
    const rows = inboxModes(v, [
      { id: 3, name: 'Web' },
      { id: 7, name: 'Mirror' },
    ]);
    expect(rows.map(r => r.mode)).toEqual(['shadow', 'eval']);
    expect(anyLive(rows)).toBe(false);
    v.inbox_modes = { 3: { mode: 'live', at: 'x', by: 'y' } };
    expect(anyLive(inboxModes(v, [{ id: 3, name: 'Web' }]))).toBe(true);
    expect(inboxModes({}, [{ id: 1, name: 'A' }])[0].mode).toBe('shadow');
  });

  it('needs the workspace name typed exactly', () => {
    const v = view();
    expect(confirmName(v)).toBe('Blue Reef');
    expect(confirmMatches(' Blue Reef ', v)).toBe(true);
    expect(confirmMatches('blue reef', v)).toBe(false);
    v.overrides.workspace_name = 'Reef Co';
    expect(confirmMatches('Blue Reef', v)).toBe(false);
    expect(confirmMatches('Reef Co', v)).toBe(true);
    expect(confirmMatches('', {})).toBe(false);
  });
});

describe('tolzarWorkspace price source', () => {
  it('builds the form and the body, and checks it first', () => {
    expect(priceSourceForm({ source: { type: null } })).toEqual({
      type: 'url',
      url: '',
      refresh_hours: 24,
    });
    expect(
      priceSourceForm({
        source: { type: 'feed', url: 'https://f', refresh_hours: null },
      }).refresh_hours
    ).toBe(1);
    expect(
      priceSourceProblems({ type: 'url', url: '', refresh_hours: 24 })
    ).toEqual(['url_required']);
    expect(
      priceSourceProblems({
        type: 'table',
        url: 'http://x',
        refresh_hours: 200,
      })
    ).toEqual(['https_only', 'hours_range']);
    expect(priceSourceProblems({ type: 'commerce' })).toEqual([]);
    expect(priceSourceProblems({ type: 'ftp' })).toEqual(['type']);
    expect(
      priceSourceBody({
        type: 'table',
        url: ' https://x/p.csv ',
        refresh_hours: '6',
      })
    ).toEqual({ type: 'table', url: 'https://x/p.csv', refresh_hours: 6 });
    expect(priceSourceBody({ type: 'commerce', url: 'x' })).toEqual({
      type: 'commerce',
    });
    expect(
      sampleColumns([
        { item: 'A', price: 10, note: null },
        { item: 'B', price: 12, currency: 'EUR' },
      ])
    ).toEqual(['item', 'price', 'currency']);
  });
});

describe('tolzarWorkspace agent prices', () => {
  it('keeps the agent copy in the brain shape', () => {
    expect(
      agentPrices({ type: 'table', url: 'https://x/p.csv', refresh_hours: 6 })
    ).toEqual({
      type: 'csv',
      value: 'https://x/p.csv',
      refresh_hours: 6,
    });
    expect(
      agentPrices(
        { type: 'feed', url: 'https://f', refresh_hours: 1 },
        { key_env: 'K' }
      )
    ).toEqual({
      type: 'departures',
      value: 'https://f',
      refresh_hours: 1,
      key_env: 'K',
    });
    expect(agentPrices({ type: 'commerce' })).toEqual({ type: 'commerce' });
    expect(agentPrices({ type: null }, { type: 'csv' })).toEqual({
      type: 'csv',
    });
  });
});

describe('tolzarWorkspace API', () => {
  const b = '/api/v1/accounts/2/tolzar';
  beforeEach(() => {
    window.axios = {
      get: vi.fn().mockResolvedValue({ data: { ok: true } }),
      post: vi.fn().mockResolvedValue({ data: { ok: true } }),
    };
  });

  it('calls the proxy routes, never with a workspace id or name', async () => {
    await getWorkspaceSettings(2);
    expect(window.axios.get).toHaveBeenLastCalledWith(
      `${b}/workspace/settings`
    );
    await saveWorkspaceSettings(2, { version: 1, set: {}, unset: ['x'] });
    expect(window.axios.post).toHaveBeenLastCalledWith(
      `${b}/workspace/settings`,
      {
        version: 1,
        set: {},
        unset: ['x'],
      }
    );
    await goLive(2, '5', 'live', ' Blue Reef ');
    expect(window.axios.post).toHaveBeenLastCalledWith(
      `${b}/workspace/go_live`,
      {
        inbox_id: 5,
        mode: 'live',
        confirm: 'Blue Reef',
      }
    );
    await killSwitch(2);
    expect(window.axios.post).toHaveBeenLastCalledWith(
      `${b}/workspace/kill_switch`,
      {}
    );
    await getPriceSource(2, 'a1');
    expect(window.axios.get).toHaveBeenLastCalledWith(
      `${b}/agents/a1/price_source`
    );
    await savePriceSource(2, 'a1', { type: 'commerce' });
    expect(window.axios.post).toHaveBeenLastCalledWith(
      `${b}/agents/a1/price_source`,
      {
        type: 'commerce',
      }
    );
    await testPriceSource(2, 'a1', { type: 'commerce' });
    expect(window.axios.post).toHaveBeenLastCalledWith(
      `${b}/agents/a1/price_source/test`,
      { type: 'commerce' }
    );
  });

  it('returns a refusal as data (409, 422) and throws on a network failure', async () => {
    window.axios.post = vi.fn().mockRejectedValue({
      response: {
        status: 409,
        data: { ok: false, error: 'version_conflict', version: 9 },
      },
    });
    const r = await saveWorkspaceSettings(2, {
      version: 1,
      set: {},
      unset: [],
    });
    expect(isConflict(r)).toBe(true);
    window.axios.post = vi.fn().mockRejectedValue(new Error('offline'));
    await expect(killSwitch(2)).rejects.toThrow('offline');
  });
});
