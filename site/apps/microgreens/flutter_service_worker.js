/* Agronizer PWA service worker: installability (fetch) + Web Push.
 * Copied over flutter_service_worker.js after `flutter build web`
 * because current Flutter emits an uninstall stub by default.
 *
 * Cache-first (stale-while-revalidate) so the installed PWA opens from disk
 * instead of waiting on the network. Updates apply in the background.
 */
'use strict';

const CACHE = 'microgreens-shell-1.0.7+8-f9c38f78';
const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(PRECACHE).catch(() => undefined))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
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

async function staleWhileRevalidate(req, { fallbackToIndex }) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(req);
  const network = fetch(req)
    .then((res) => {
      if (res && res.ok && res.type === 'basic') {
        cache.put(req, res.clone()).catch(() => undefined);
      }
      return res;
    })
    .catch(() => undefined);
  if (cached) return cached;
  const fresh = await network;
  if (fresh) return fresh;
  if (fallbackToIndex) {
    const shell = await cache.match('./index.html');
    if (shell) return shell;
  }
  return Response.error();
}

async function networkFirst(req, timeoutMs) {
  const cache = await caches.open(CACHE);
  const cached = cache.match(req);
  try {
    const fresh = await Promise.race([
      fetch(req),
      new Promise((_, reject) => {
        setTimeout(() => reject(new Error('timeout')), timeoutMs);
      }),
    ]);
    if (fresh && fresh.ok && fresh.type === 'basic') {
      cache.put(req, fresh.clone()).catch(() => undefined);
      return fresh;
    }
  } catch (_) {}
  const fallback = await cached;
  if (fallback) return fallback;
  return fetch(req);
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  let url;
  try {
    url = new URL(req.url);
  } catch (_) {
    return;
  }
  if (url.origin !== self.location.origin) return;

  const isDoc =
    req.mode === 'navigate' ||
    (req.headers.get('accept') || '').includes('text/html');
  const isVersion = url.pathname.endsWith('/version.json');

  if (isVersion) {
    event.respondWith(networkFirst(req, 2500));
    return;
  }

  event.respondWith(staleWhileRevalidate(req, { fallbackToIndex: isDoc }));
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
