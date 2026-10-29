import Cookies from 'js-cookie';
import { IFrameHelper } from '../IFrameHelper';
import '../../entrypoints/sdk';

vi.mock('../IFrameHelper', () => ({
  IFrameHelper: {
    createFrame: vi.fn(),
    sendMessage: vi.fn(),
  },
}));

describe('$chatwoot.setUser', () => {
  beforeEach(() => {
    delete window.$chatwoot;
    window.chatwootSettings = {};
    vi.spyOn(Cookies, 'get').mockReturnValue(undefined);
    vi.spyOn(Cookies, 'set').mockImplementation(() => {});

    window.chatwootSDK.run({
      baseUrl: 'https://chat.example.com',
      websiteToken: 'website-token',
    });
  });

  afterEach(() => {
    delete window.$chatwoot;
    delete window.chatwootSettings;
    vi.restoreAllMocks();
  });

  it('updates the SDK identity synchronously', () => {
    const user = { name: 'Pranav' };

    const result = window.$chatwoot.setUser('first-user', user);

    expect(result).toBeUndefined();
    expect(window.$chatwoot.identifier).toBe('first-user');
    expect(window.$chatwoot.user).toBe(user);
    expect(IFrameHelper.sendMessage).toHaveBeenCalledWith('set-user', {
      identifier: 'first-user',
      user,
    });
  });

  it('keeps the latest identity after consecutive calls', () => {
    const firstUser = { name: 'First user' };
    const secondUser = { name: 'Second user' };

    window.$chatwoot.setUser('first-user', firstUser);
    window.$chatwoot.setUser('second-user', secondUser);

    expect(window.$chatwoot.identifier).toBe('second-user');
    expect(window.$chatwoot.user).toBe(secondUser);
    expect(IFrameHelper.sendMessage).toHaveBeenLastCalledWith('set-user', {
      identifier: 'second-user',
      user: secondUser,
    });
  });
});

describe('Tolzar SDK names', () => {
  afterEach(() => {
    delete window.$chatwoot;
    delete window.$tolzar;
    delete window.tolzarSettings;
    vi.restoreAllMocks();
  });

  it('runs as window.tolzarSDK, exposes $tolzar as $chatwoot and reads tolzarSettings', () => {
    vi.spyOn(Cookies, 'get').mockReturnValue(undefined);
    vi.spyOn(Cookies, 'set').mockImplementation(() => {});
    window.tolzarSettings = { position: 'left' };

    window.tolzarSDK.run({ baseUrl: 'https://chat.example.test', websiteToken: 'website-token' });

    expect(window.tolzarSDK).toBe(window.chatwootSDK);
    expect(window.$tolzar).toBe(window.$chatwoot);
    expect(window.$tolzar.position).toBe('left');
    expect(IFrameHelper.createFrame).toHaveBeenCalled();
  });
});
