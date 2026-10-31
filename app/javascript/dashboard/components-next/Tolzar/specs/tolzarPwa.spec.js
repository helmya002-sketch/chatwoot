import { describe, it, expect, vi } from 'vitest';
import { clearTolzarCachesOnLogout, isInstalledApp } from '../tolzarPwa';

describe('tolzarPwa', () => {
  it('clears only Tolzar caches and tells the service worker', async () => {
    const deleted = [];
    const postMessage = vi.fn();
    const win = {
      caches: {
        keys: async () => ['tolzar-shell-v1', 'other-site', 'tolzar-old'],
        delete: async k => deleted.push(k),
      },
      navigator: { serviceWorker: { controller: { postMessage } } },
    };
    await clearTolzarCachesOnLogout(win);
    expect(deleted).toEqual(['tolzar-shell-v1', 'tolzar-old']);
    expect(postMessage).toHaveBeenCalledWith({ type: 'tz-clear-caches' });
  });

  it('never throws on a browser without caches or a service worker', async () => {
    await expect(clearTolzarCachesOnLogout({})).resolves.toBeUndefined();
    const broken = {
      caches: {
        keys: async () => {
          throw new Error('blocked');
        },
      },
    };
    await expect(clearTolzarCachesOnLogout(broken)).resolves.toBeUndefined();
  });

  it('knows when it runs as the installed app', () => {
    expect(isInstalledApp({ navigator: { standalone: true } })).toBe(true);
    expect(
      isInstalledApp({ navigator: {}, matchMedia: () => ({ matches: true }) })
    ).toBe(true);
    expect(
      isInstalledApp({ navigator: {}, matchMedia: () => ({ matches: false }) })
    ).toBe(false);
  });
});
