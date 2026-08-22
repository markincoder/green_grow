import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Returns true if the page will reload to pick up the new PWA build.
Future<bool> applyWebAppUpdateImpl() async {
  const flag = 'pwa_applying_update';
  try {
    final storage = web.window.sessionStorage;
    if (storage.getItem(flag) == '1') {
      storage.removeItem(flag);
      return false;
    }
    storage.setItem(flag, '1');
  } catch (_) {}
  try {
    final sw = web.window.navigator.serviceWorker;
    final registration = await sw.getRegistration().toDart;
    if (registration != null) {
      await registration.update().toDart;
      final waiting = registration.waiting;
      waiting?.postMessage('SKIP_WAITING'.toJS);
    }
  } catch (_) {}
  web.window.location.reload();
  return true;
}
