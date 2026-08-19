import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> applyWebAppUpdateImpl() async {
  try {
    final sw = web.window.navigator.serviceWorker;
    final registration = await sw.getRegistration().toDart;
    if (registration != null) {
      await registration.update().toDart;
    }
  } catch (_) {}
  web.window.location.reload();
}
