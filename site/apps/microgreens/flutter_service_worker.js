/* Agronizer PWA service worker: installability (fetch) + Web Push.
 * Copied over flutter_service_worker.js after `flutter build web`
 * because current Flutter emits an uninstall stub by default.
 */
'use strict';

const CACHE = 'microgreens-shell-v14';
const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './flutter_bootstrap.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(PRECACHE).catch(() => undefined))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)),
      );
      await self.clients.claim();
    })(),
  );
});

// Required for Chrome "Install app" / Add to Home Screen.
// Network-first for HTML/JS so setup_gate + manifest updates are not stuck.
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  const isDoc =
    req.mode === 'navigate' ||
    (req.headers.get('accept') || '').includes('text/html');
  const isSetupJs =
    url.pathname.endsWith('/setup_gate.js') ||
    url.pathname.endsWith('/push_client.js') ||
    url.pathname.endsWith('/manifest.json') ||
    url.pathname.endsWith('/index.html');

  if (isDoc || isSetupJs) {
    event.respondWith(
      (async () => {
        try {
          const fresh = await fetch(req);
          return fresh;
        } catch (_) {
          const cached = await caches.match(req);
          if (cached) return cached;
          if (isDoc) {
            const shell = await caches.match('./index.html');
            if (shell) return shell;
          }
          throw _;
        }
      })(),
    );
    return;
  }

  event.respondWith(
    (async () => {
      try {
        const fresh = await fetch(req);
        if (
          fresh.ok &&
          url.origin === self.location.origin &&
          (url.pathname.endsWith('.js') ||
            url.pathname.endsWith('.wasm') ||
            url.pathname.endsWith('.png') ||
            url.pathname.endsWith('.json'))
        ) {
          const cache = await caches.open(CACHE);
          cache.put(req, fresh.clone()).catch(() => undefined);
        }
        return fresh;
      } catch (_) {
        const cached = await caches.match(req);
        if (cached) return cached;
        throw _;
      }
    })(),
  );
});

/** iOS adds "from {PWA name}" to the title — don't repeat «Микрозелень». */
function isIosServiceWorker() {
  var ua = (self.navigator && self.navigator.userAgent) || '';
  if (/iPad|iPhone|iPod/.test(ua)) return true;
  return (
    self.navigator &&
    self.navigator.platform === 'MacIntel' &&
    self.navigator.maxTouchPoints > 1
  );
}

function iosSafeNotificationTitle(raw) {
  var title = (raw || '').trim();
  if (!isIosServiceWorker()) return title || 'Агронайзер';
  var app = 'Микрозелень';
  if (!title || title === app || title === 'Агронайзер') return 'Напоминание';
  var prefix = app + ' — ';
  if (title.indexOf(prefix) === 0) return title.slice(prefix.length) || 'Напоминание';
  return title;
}

self.addEventListener('push', (event) => {
  let payload = { title: 'Агронайзер', body: '', data: {} };
  try {
    if (event.data) {
      payload = { ...payload, ...event.data.json() };
    }
  } catch (_) {
    try {
      payload.body = event.data ? event.data.text() : '';
    } catch (_) {}
  }
  event.waitUntil(
    self.registration.showNotification(iosSafeNotificationTitle(payload.title), {
      body: payload.body || '',
      data: payload.data || {},
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || './';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(url);
    }),
  );
});
