/* Agronizer PWA service worker: installability (fetch) + Web Push.
 * Copied over flutter_service_worker.js after `flutter build web`
 * because current Flutter emits an uninstall stub by default.
 *
 * Shell assets: stale-while-revalidate for offline open.
 * Update-critical files (index, pwa_update, version, bootstrap): network-first
 * so a waiting worker can offer the update dialog without a stale shell.
 * New builds wait for SKIP_WAITING before replacing the active worker.
 */
'use strict';

const CACHE = 'microgreens-shell-1.0.11+12-5c7b5b79';
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
    (async () => {
      const cache = await caches.open(CACHE);
      await cache.addAll(PRECACHE).catch(() => undefined);
      // First install: activate immediately. Updates wait for SKIP_WAITING.
      if (!self.registration.active) {
        await self.skipWaiting();
        return;
      }
      const list = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      for (const client of list) {
        client.postMessage({ type: 'AGRONIZER_UPDATE_READY' });
      }
    })(),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      await self.clients.claim();
      // Delay wiping old shell caches so the first paint after update can
      // still fall back to previous assets if the network is slow.
      setTimeout(() => {
        caches.keys().then((keys) => {
          for (const k of keys) {
            if (k.startsWith('microgreens-shell-') && k !== CACHE) {
              caches.delete(k);
            }
          }
        });
      }, 45000);
    })(),
  );
});

async function matchShellCaches(req) {
  const keys = await caches.keys();
  // Prefer current CACHE, then any older microgreens shell.
  const ordered = keys
    .filter((k) => k.startsWith('microgreens-shell-'))
    .sort((a, b) => {
      if (a === CACHE) return -1;
      if (b === CACHE) return 1;
      return b.localeCompare(a);
    });
  for (const k of ordered) {
    const hit = await caches.open(k).then((c) => c.match(req));
    if (hit) return hit;
  }
  return undefined;
}

async function staleWhileRevalidate(req, { fallbackToIndex }) {
  const cache = await caches.open(CACHE);
  const cached = (await cache.match(req)) || (await matchShellCaches(req));
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
    const shell =
      (await cache.match('./index.html')) ||
      (await matchShellCaches(new Request('./index.html')));
    if (shell) return shell;
  }
  return Response.error();
}

async function networkFirst(req, timeoutMs) {
  const cache = await caches.open(CACHE);
  const cachedPromise = matchShellCaches(req);
  try {
    const fresh = await Promise.race([
      fetch(req),
      new Promise((_, reject) => {
        setTimeout(() => reject(new Error('timeout')), timeoutMs);
      }),
    ]);
    if (fresh && fresh.ok && (fresh.type === 'basic' || fresh.type === 'cors')) {
      cache.put(req, fresh.clone()).catch(() => undefined);
      return fresh;
    }
  } catch (_) {}
  const fallback = await cachedPromise;
  if (fallback) return fallback;
  return fetch(req);
}

function isNetworkCritical(url, isDoc) {
  if (isDoc) return true;
  const path = url.pathname;
  return (
    path.endsWith('/version.json') ||
    path.endsWith('/pwa_update.js') ||
    path.endsWith('/flutter_bootstrap.js') ||
    path.endsWith('/flutter.js') ||
    path.endsWith('/index.html') ||
    /\/main\.dart\.js$/i.test(path)
  );
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

  if (isNetworkCritical(url, isDoc)) {
    event.respondWith(networkFirst(req, 4000));
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
