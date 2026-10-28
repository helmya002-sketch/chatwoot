import {
  credentialBody,
  credentialStatus,
  getPriceKey,
  savePriceKey,
  clearPriceKey,
} from '../tolzarCredentials';

const url = f => `/api/v1/accounts/2/tolzar/brain/${f}`;

describe('tolzarCredentials', () => {
  beforeEach(() => {
    window.axios = {
      get: vi.fn().mockResolvedValue({ data: { ok: true } }),
      post: vi.fn().mockResolvedValue({ data: { ok: true } }),
    };
  });

  it('sends typed keys only, and clears only fields not being replaced', () => {
    expect(
      credentialBody({ api_key: '', api_secret: '  ' }, [
        'api_key',
        'api_secret',
      ])
    ).toEqual({});
    expect(credentialBody({ api_key: 'k', other: 'x' }, ['api_key'])).toEqual({
      api_key: 'k',
    });
    expect(
      credentialBody(
        { api_key: 'new' },
        ['api_key', 'api_secret'],
        ['api_key', 'api_secret', 'nope']
      )
    ).toEqual({ api_key: 'new', clear_credentials: ['api_secret'] });
    expect(credentialBody(null, ['api_key'], ['api_key'])).toEqual({
      clear_credentials: ['api_key'],
    });
  });

  it('reads the status, never a value', () => {
    const data = {
      credentials: { api_key: { set: true, last4: '1234', source: 'stored' } },
    };
    expect(credentialStatus(data, 'api_key')).toEqual({
      set: true,
      last4: '1234',
      source: 'stored',
    });
    expect(credentialStatus(data, 'api_secret')).toEqual({
      set: false,
      last4: '',
      source: null,
    });
    expect(credentialStatus(null, 'api_key').set).toBe(false);
  });

  it('reads, sets and removes an agent price-feed key', async () => {
    await getPriceKey(2, 'a1');
    expect(window.axios.get).toHaveBeenLastCalledWith(
      url('credentials_prices'),
      {
        params: { agent_id: 'a1' },
      }
    );
    await savePriceKey(2, 'a1', ' secret ');
    expect(window.axios.post).toHaveBeenLastCalledWith(
      url('credentials_prices'),
      {
        agent_id: 'a1',
        api_key: 'secret',
      }
    );
    await clearPriceKey(2, 'a1');
    expect(window.axios.post).toHaveBeenLastCalledWith(
      url('credentials_prices'),
      {
        agent_id: 'a1',
        clear_credentials: ['api_key'],
      }
    );
  });
});
