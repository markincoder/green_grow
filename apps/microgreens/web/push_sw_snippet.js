// Appended to flutter_service_worker.js after `flutter build web`
// (see scripts/patch_pwa_sw.ps1). Handles Web Push from agronizer-push.

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
  var title = (payload.title || '').trim();
  var ua = (self.navigator && self.navigator.userAgent) || '';
  var ios = /iPad|iPhone|iPod/.test(ua);
  if (ios && (!title || title === 'Микрозелень' || title === 'Агронайзер')) {
    title = 'Напоминание';
  } else if (ios && title.indexOf('Микрозелень — ') === 0) {
    title = title.slice('Микрозелень — '.length) || 'Напоминание';
  }
  event.waitUntil(
    self.registration.showNotification(title || 'Агронайзер', {
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
