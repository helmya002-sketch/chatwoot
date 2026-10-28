import {
  brainUrl,
  brainGet,
  brainPost,
  brainErrors,
  isOwnerOnly,
} from '../tolzarBrainApi';

describe('tolzarBrainApi', () => {
  beforeEach(() => {
    window.axios = { get: vi.fn(), post: vi.fn() };
  });

  it('goes through the allow-listed proxy path and never sends an account id', async () => {
    window.axios.get.mockResolvedValue({ data: { ok: true } });
    window.axios.post.mockResolvedValue({ data: { ok: true } });
    expect(brainUrl(3, 'roi')).toBe('/api/v1/accounts/3/tolzar/brain/roi');
    await brainGet(3, 'roi', { days: 30 });
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/3/tolzar/brain/roi',
      { params: { days: 30 } }
    );
    await brainPost(3, 'quotas', { daily_calls: 5 });
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/3/tolzar/brain/quotas',
      { daily_calls: 5 }
    );
    expect(window.axios.post.mock.calls[0][1]).not.toHaveProperty('account_id');
  });

  it('returns a refusal as data so the page can say why', async () => {
    window.axios.post.mockRejectedValue({
      response: { status: 403, data: { ok: false, error: 'owner_only' } },
    });
    const r = await brainPost(3, 'quotas');
    expect(isOwnerOnly(r)).toBe(true);
    expect(brainErrors(r)).toEqual(['owner_only']);
  });

  it('still throws on a network failure', async () => {
    window.axios.get.mockRejectedValue(new Error('offline'));
    await expect(brainGet(3, 'roi')).rejects.toThrow('offline');
  });

  it('reads the brain errors in every shape', () => {
    expect(brainErrors({ ok: true })).toEqual([]);
    expect(brainErrors(null)).toEqual([]);
    expect(brainErrors({ detail: 'set up SMS first' })).toEqual([
      'set up SMS first',
    ]);
    expect(brainErrors({ detail: ['a', { msg: 'b' }] })).toEqual(['a', 'b']);
  });
});
