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

// Quiet hours (Tolzar::PushPrivacy.quiet?): what Profile > Notifications saves in ui_settings.tolzar_quiet_hours.
export const QUIET_DEFAULT = { on: false, from: '22:00', to: '07:00', tz: '' };
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;
export function quietHours(saved, browserZone = '') {
  const q = {
    ...QUIET_DEFAULT,
    ...(saved && typeof saved === 'object' ? saved : {}),
  };
  return {
    on: q.on === true,
    from: HHMM.test(q.from) ? q.from : QUIET_DEFAULT.from,
    to: HHMM.test(q.to) ? q.to : QUIET_DEFAULT.to,
    tz: q.tz || browserZone || '',
  };
}

// The "Turn on notifications" prompt: only inside the installed app, only while the phone has not been asked.
export function shouldOfferPush(win = window, { dismissed = false } = {}) {
  if (dismissed || !isInstalledApp(win)) return false;
  const N = win.Notification;
  return (
    !!N && N.permission === 'default' && !!win.chatwootConfig?.vapidPublicKey
  );
}
