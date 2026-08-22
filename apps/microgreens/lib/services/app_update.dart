import 'app_update_stub.dart'
    if (dart.library.html) 'app_update_web.dart';

/// Reload the PWA so the service worker can pick up the published build.
/// Returns true if a reload was started.
Future<bool> applyWebAppUpdate() => applyWebAppUpdateImpl();
