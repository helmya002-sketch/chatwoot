// Tolzar installable app (round 4, c63): on sign-out, empty every Tolzar cache on this device and tell the service
// worker to do the same (public/sw.js caches only build files and icons, never data; this is the belt to that).
// Never throws: a browser without caches or a service worker simply has nothing to clear.
export async function clearTolzarCachesOnLogout(win = window) {
  try {
    if (win.caches && win.caches.keys) {
      const keys = await win.caches.keys();
      await Promise.all(
        keys.filter(k => k.startsWith('tolzar-')).map(k => win.caches.delete(k))
      );
    }
    const controller = win.navigator?.serviceWorker?.controller;
    if (controller) controller.postMessage({ type: 'tz-clear-caches' });
  } catch (e) {
    // Nothing to clear on this browser.
  }
}

// True when Tolzar runs as the installed app (Home Screen), not in a browser tab.
export function isInstalledApp(win = window) {
  try {
    return (
      win.navigator?.standalone === true ||
      (win.matchMedia && win.matchMedia('(display-mode: standalone)').matches)
    );
  } catch (e) {
    return false;
  }
}
