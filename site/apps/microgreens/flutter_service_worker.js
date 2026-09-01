/* Agronizer PWA service worker: installability (fetch) + Web Push.
 * Copied over flutter_service_worker.js after `flutter build web`
 * because current Flutter emits an uninstall stub by default.
 *
 * Offline: patch_pwa_sw.ps1 injects PRECACHE_OFFLINE (main.dart.js, CanvasKit, assets).
 * Install precaches the full app shell while the user is online during setup.
 *
 * Update-critical (version.json, pwa_update.js): stale-while-revalidate (cache first).
 * Boot assets: cache-first. Everything else: cache-first, then network.
 */
'use strict';

const CACHE = 'microgreens-shell-1.0.16+20-a74d541a';
const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './favicon.png',
  './favicon.svg',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
];

/** Filled by scripts/patch_pwa_sw.ps1 after flutter build web. */
const PRECACHE_OFFLINE = [
  './assets/AssetManifest.bin',
  './assets/AssetManifest.bin.json',
  './assets/assets/app_icon.png',
  './assets/assets/celebrate.json',
  './assets/assets/logo_agronizer.png',
  './assets/assets/logo_agronizer_word.png',
  './assets/assets/logo_microgreens.png',
  './assets/assets/plants/amarant1.jpg',
  './assets/assets/plants/amarant2.jpg',
  './assets/assets/plants/amarant3.jpg',
  './assets/assets/plants/bazilik1.jpg',
  './assets/assets/plants/bazilik2.jpg',
  './assets/assets/plants/bazilik3.jpg',
  './assets/assets/plants/borago1.jpg',
  './assets/assets/plants/borago2.jpg',
  './assets/assets/plants/borago3.jpg',
  './assets/assets/plants/brokkoli1.jpg',
  './assets/assets/plants/daikon1.jpg',
  './assets/assets/plants/gorchitsa1.jpg',
  './assets/assets/plants/goroh1.jpg',
  './assets/assets/plants/goroh2.jpg',
  './assets/assets/plants/goroh3.jpg',
  './assets/assets/plants/kale1.jpg',
  './assets/assets/plants/kervel1.jpg',
  './assets/assets/plants/kinza1.jpg',
  './assets/assets/plants/kinza2.jpg',
  './assets/assets/plants/kinza3.jpg',
  './assets/assets/plants/klever1.jpg',
  './assets/assets/plants/klever2.jpg',
  './assets/assets/plants/klever3.jpg',
  './assets/assets/plants/kolrabi1.jpg',
  './assets/assets/plants/komatsuna1.jpg',
  './assets/assets/plants/kress1.jpg',
  './assets/assets/plants/kress2.jpg',
  './assets/assets/plants/kress3.jpg',
  './assets/assets/plants/kukuruza1.jpg',
  './assets/assets/plants/kukuruza2.jpg',
  './assets/assets/plants/kukuruza3.jpg',
  './assets/assets/plants/luk1.jpg',
  './assets/assets/plants/luk2.jpg',
  './assets/assets/plants/luk3.jpg',
  './assets/assets/plants/mangold1.jpg',
  './assets/assets/plants/mangold2.jpg',
  './assets/assets/plants/mangold3.jpg',
  './assets/assets/plants/melissa1.jpg',
  './assets/assets/plants/mizuna1.jpg',
  './assets/assets/plants/mizuna2.jpg',
  './assets/assets/plants/nophoto2.jpg',
  './assets/assets/plants/pakchoi1.jpg',
  './assets/assets/plants/pazhitnik1.jpg',
  './assets/assets/plants/perilla1.jpg',
  './assets/assets/plants/podsolnechnik1.jpg',
  './assets/assets/plants/podsolnechnik2.jpg',
  './assets/assets/plants/podsolnechnik3.jpg',
  './assets/assets/plants/redis1.jpg',
  './assets/assets/plants/redis2.jpg',
  './assets/assets/plants/redis3.jpg',
  './assets/assets/plants/redka1.jpg',
  './assets/assets/plants/repa1.jpg',
  './assets/assets/plants/rukola1.jpg',
  './assets/assets/plants/rukola2.jpg',
  './assets/assets/plants/rukola3.jpg',
  './assets/assets/plants/salat1.jpg',
  './assets/assets/plants/shpinat1.jpg',
  './assets/assets/plants/svekla1.jpg',
  './assets/assets/plants/tatsoi1.jpg',
  './assets/assets/plants/tshavel1.jpg',
  './assets/assets/plants/tshavel2.jpg',
  './assets/assets/plants/tshavel3.jpg',
  './assets/FontManifest.json',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/NOTICES',
  './assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  './assets/shaders/ink_sparkle.frag',
  './assets/shaders/stretch_effect.frag',
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
  './flutter.js',
  './flutter_bootstrap.js',
  './main.dart.js',
  './push_client.js',
  './pwa_update.js',
  './setup_gate.js',
  './version.json',
];

let shellCachePromise = null;
let scopePathCache = null;

function getShellCache() {
  if (!shellCachePromise) {
    shellCachePromise = caches.open(CACHE);
  }
  return shellCachePromise;
}

function scopePathname() {
  if (scopePathCache) return scopePathCache;
  try {
    scopePathCache = new URL(self.registration.scope).pathname;
  } catch (_) {
    scopePathCache = '/';
  }
  return scopePathCache;
}

async function precacheShell() {
  const cache = await getShellCache();
  const paths = [...new Set([...PRECACHE, ...PRECACHE_OFFLINE])];
  await Promise.all(
    paths.map(async (path) => {
      try {
        if (await cache.match(path)) return;
        const res = await fetch(path);
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
      const isFirst = !self.registration.active;
      await precacheShell();
      if (isFirst) {
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
      shellCachePromise = caches.open(CACHE);
      await self.clients.claim();
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((k) => k.startsWith('microgreens-shell-') && k !== CACHE)
          .map((k) => caches.delete(k)),
      );
    })(),
  );
});

/** Cache keys ignore ?v= bust params — index.html loads scripts with query strings. */
function normalizedCacheKey(req) {
  try {
    const url = new URL(req.url);
    if (url.origin !== self.location.origin) return null;
    const scopePath = scopePathname();
    let path = url.pathname;
    if (path.startsWith(scopePath)) {
      path = path.slice(scopePath.length);
    }
    if (!path || path === '/') return './';
    if (!path.startsWith('./')) path = './' + path.replace(/^\//, '');
    return path;
  } catch (_) {
    return null;
  }
}

async function matchInCache(cache, req) {
  const key = normalizedCacheKey(req);
  if (key) {
    const byKey = await cache.match(key);
    if (byKey) return byKey;
  }
  return cache.match(req);
}

async function putInCache(cache, req, res) {
  const key = normalizedCacheKey(req);
  if (key) {
    await cache.put(key, res.clone());
    return;
  }
  await cache.put(req, res.clone());
}

async function matchCached(req) {
  const cache = await getShellCache();
  return matchInCache(cache, req);
}

async function cacheFirst(req, { store = true } = {}) {
  const cached = await matchCached(req);
  if (cached) return cached;
  try {
    const fresh = await fetch(req);
    if (fresh && fresh.ok && (fresh.type === 'basic' || fresh.type === 'cors')) {
      if (store) {
        putInCache(await getShellCache(), req, fresh).catch(() => undefined);
      }
      return fresh;
    }
  } catch (_) {}
  return Response.error();
}

async function navigate(req) {
  const cached = await matchCached(req);
  if (cached) return cached;
  try {
    const fresh = await fetch(req);
    if (fresh && fresh.ok) {
      const cache = await getShellCache();
      cache.put('./index.html', fresh.clone()).catch(() => undefined);
      return fresh;
    }
  } catch (_) {}
  const cache = await getShellCache();
  const shell =
    (await matchInCache(cache, new Request('./index.html'))) ||
    (await matchInCache(cache, new Request('./')));
  if (shell) return shell;
  return Response.error();
}

/** Serve cached copy immediately; refresh in background for update checks. */
async function staleWhileRevalidate(req, event, timeoutMs) {
  const cache = await getShellCache();
  const cached = await matchInCache(cache, req);
  const refresh = fetch(req)
    .then(async (fresh) => {
      if (fresh && fresh.ok) await putInCache(cache, req, fresh);
    })
    .catch(() => undefined);
  if (event) event.waitUntil(refresh);
  if (cached) return cached;
  try {
    const fresh = await Promise.race([
      fetch(req),
      new Promise((_, reject) => {
        setTimeout(() => reject(new Error('timeout')), timeoutMs);
      }),
    ]);
    if (fresh && fresh.ok) {
      await putInCache(cache, req, fresh);
      return fresh;
    }
  } catch (_) {}
  return Response.error();
}

function isUpdateChecker(url) {
  const path = url.pathname;
  return path.endsWith('/version.json') || path.endsWith('/pwa_update.js');
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

  if (isDoc) {
    event.respondWith(navigate(req));
    return;
  }
  if (isUpdateChecker(url)) {
    event.respondWith(staleWhileRevalidate(req, event, 800));
    return;
  }
  event.respondWith(cacheFirst(req));
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
