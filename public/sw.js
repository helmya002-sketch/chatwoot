/* eslint-disable no-restricted-globals, no-console */
/* globals clients */
// Tolzar service worker (round 4, c63: the installable app). Push as before, plus a small, safe cache:
// - pages are always fetched from the network; only when the network fails is the offline screen shown;
// - only fingerprinted build files (/vite/assets/…, immutable) and the app icons are cached;
// - nothing from /api, /cable, auth or any other request is ever cached, so no conversation or other
//   person's data is kept on the phone;
// - a "tz-clear-caches" message (sent on sign-out) empties every Tolzar cache.
const CACHE = 'tolzar-shell-v1';
const OFFLINE_URL = '/offline.html';
const PRECACHE = [
  OFFLINE_URL,
  '/apple-icon-180x180.png',
  '/android-icon-192x192.png',
];
const CACHEABLE =
  /^\/(vite\/assets\/.+-[A-Za-z0-9_-]{8,}\.(js|css|woff2?|png|svg|jpg)|apple-icon-[0-9x]+\.png|android-icon-[0-9x]+\.png|favicon-[0-9x]+\.png)$/;

self.addEventListener('install', event => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then(cache => cache.addAll(PRECACHE))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches
      .keys()
      .then(keys =>
        Promise.all(
          keys
            .filter(k => k.startsWith('tolzar-') && k !== CACHE)
            .map(k => caches.delete(k))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    // Network first, never stored; the offline screen only when the network fails.
    event.respondWith(
      fetch(request).catch(() =>
        caches.match(OFFLINE_URL).then(r => r || Response.error())
      )
    );
    return;
  }

  if (!CACHEABLE.test(url.pathname)) return;
  event.respondWith(
    caches.open(CACHE).then(cache =>
      cache.match(request).then(
        hit =>
          hit ||
          fetch(request).then(response => {
            if (response.ok && response.type === 'basic')
              cache.put(request, response.clone());
            return response;
          })
      )
    )
  );
});

self.addEventListener('message', event => {
  if (!event.data || event.data.type !== 'tz-clear-caches') return;
  event.waitUntil(
    caches
      .keys()
      .then(keys =>
        Promise.all(
          keys.filter(k => k.startsWith('tolzar-')).map(k => caches.delete(k))
        )
      )
  );
});

self.addEventListener('push', event => {
  let notification = event.data && event.data.json();

  event.waitUntil(
    self.registration.showNotification(notification.title, {
      tag: notification.tag,
      body: notification.body || undefined,
      icon: '/android-icon-192x192.png',
      badge: '/favicon-badge-96x96.png',
      data: {
        url: notification.url,
      },
    })
  );
});

self.addEventListener('notificationclick', event => {
  let notification = event.notification;
  notification.close();

  event.waitUntil(
    clients.matchAll({ type: 'window' }).then(windowClients => {
      let matchingWindowClients = windowClients.filter(
        client => client.url === notification.data.url
      );

      if (matchingWindowClients.length) {
        let firstWindow = matchingWindowClients[0];
        if (firstWindow && 'focus' in firstWindow) {
          firstWindow.focus();
          return;
        }
      }
      if (clients.openWindow) {
        clients.openWindow(notification.data.url);
      }
    })
  );
});
