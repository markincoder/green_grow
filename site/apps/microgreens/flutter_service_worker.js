/* Agronizer PWA service worker: installability (fetch) + Web Push.
 * Copied over flutter_service_worker.js after `flutter build web`
 * because current Flutter emits an uninstall stub by default.
 *
 * Shell assets: stale-while-revalidate for offline open.
 * Update-critical files (index, pwa_update, version, bootstrap): network-first
 * so a waiting worker can offer the update dialog without a stale shell.
 * Icons / plant images / Flutter assets: network-first + no-cache fetch so
 * same-URL files refresh after an update (SWR + old shells caused stale media).
 * New builds wait for SKIP_WAITING before replacing the active worker.
 */
'use strict';

const CACHE = 'microgreens-shell-1.0.14+15-swfix';
const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
];

async function precacheShell() {
  const cache = await caches.open(CACHE);
  await Promise.all(
    PRECACHE.map(async (path) => {
      try {
        // Bypass HTTP cache so install does not store a previous build's icons.
        const res = await fetch(path, { cache: 'reload' });
        if (res && res.ok) {
          await cache.put(path, res.clone());
        }
      } catch (_) {}
    }),
  );
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      await precacheShell();
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
      // Drop previous shells right away so post-update reloads do not keep
      // serving same-URL icons/images from the old cache.
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((k) => k.startsWith('microgreens-shell-') && k !== CACHE)
          .map((k) => caches.delete(k)),
      );
    })(),
  );
});

async function matchOldShellCaches(req) {
  const keys = await caches.keys();
  const ordered = keys
    .filter((k) => k.startsWith('microgreens-shell-') && k !== CACHE)
    .sort((a, b) => b.localeCompare(a));
  for (const k of ordered) {
    const hit = await caches.open(k).then((c) => c.match(req));
    if (hit) return hit;
  }
  return undefined;
}

async function staleWhileRevalidate(req, { fallbackToIndex }) {
  const cache = await caches.open(CACHE);
  // Only the current shell for the fast path â€” never prefer an older build.
  const cached = await cache.match(req);
  const network = fetch(req, { cache: 'no-cache' })
    .then((res) => {
      if (res && res.ok && (res.type === 'basic' || res.type === 'cors')) {
        cache.put(req, res.clone()).catch(() => undefined);
      }
      return res;
    })
    .catch(() => undefined);
  if (cached) return cached;
  const fresh = await network;
  if (fresh) return fresh;
  const old = await matchOldShellCaches(req);
  if (old) return old;
  if (fallbackToIndex) {
    const shell =
      (await cache.match('./index.html')) ||
      (await matchOldShellCaches(new Request('./index.html')));
    if (shell) return shell;
  }
  return Response.error();
}

async function networkFirst(req, timeoutMs) {
  const cache = await caches.open(CACHE);
  try {
    const fresh = await Promise.race([
      fetch(req, { cache: 'no-cache' }),
      new Promise((_, reject) => {
        setTimeout(() => reject(new Error('timeout')), timeoutMs);
      }),
    ]);
    if (fresh && fresh.ok && (fresh.type === 'basic' || fresh.type === 'cors')) {
      cache.put(req, fresh.clone()).catch(() => undefined);
      return fresh;
    }
  } catch (_) {}
  const local = await cache.match(req);
  if (local) return local;
  const old = await matchOldShellCaches(req);
  if (old) return old;
  return fetch(req, { cache: 'no-cache' });
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

/** Same URL across builds â€” must not stay on stale-while-revalidate. */
function isMutableStatic(url) {
  const path = url.pathname;
  if (path.includes('/icons/')) return true;
  if (path.endsWith('/favicon.png') || path.endsWith('/favicon.ico')) return true;
  if (path.endsWith('/manifest.json')) return true;
  if (path.includes('/assets/')) return true;
  return /\.(png|jpe?g|webp|gif|svg|ico|bin)$/i.test(path);
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

  if (isNetworkCritical(url, isDoc) || isMutableStatic(url)) {
    event.respondWith(networkFirst(req, 5000));
    return;
  }

  event.respondWith(staleWhileRevalidate(req, { fallbackToIndex: isDoc }));
});

/** iOS adds "from {PWA name}" to the title â€” don't repeat Â«ÐœÐ¸ÐºÑ€Ð¾Ð·ÐµÐ»ÐµÐ½ÑŒÂ». */
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
  if (!isIosServiceWorker()) return title || 'ÐÐ³Ñ€Ð¾Ð½Ð°Ð¹Ð·ÐµÑ€';
  var app = 'ÐœÐ¸ÐºÑ€Ð¾Ð·ÐµÐ»ÐµÐ½ÑŒ';
  if (!title || title === app || title === 'ÐÐ³Ñ€Ð¾Ð½Ð°Ð¹Ð·ÐµÑ€') return 'ÐÐ°Ð¿Ð¾Ð¼Ð¸Ð½Ð°Ð½Ð¸Ðµ';
  var prefix = app + ' â€” ';
  if (title.indexOf(prefix) === 0) return title.slice(prefix.length) || 'ÐÐ°Ð¿Ð¾Ð¼Ð¸Ð½Ð°Ð½Ð¸Ðµ';
  return title;
}

self.addEventListener('push', (event) => {
  let payload = { title: 'ÐÐ³Ñ€Ð¾Ð½Ð°Ð¹Ð·ÐµÑ€', body: '', data: {} };
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
