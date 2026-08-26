import 'app_update_stub.dart'
    if (dart.library.html) 'app_update_web.dart';

/// Reload the PWA so the service worker can pick up the published build.
/// Returns true if a reload was started.
Future<bool> applyWebAppUpdate() => applyWebAppUpdateImpl();

/// Whether a newer service worker is installed and waiting.
Future<bool> hasWaitingWebAppUpdate() => hasWaitingWebAppUpdateImpl();

/// Whether the HTML overlay already offered the PWA update.
bool htmlPwaUpdatePromptShown() => htmlPwaUpdatePromptShownImpl();

/// User chose «Позже» — do not auto-apply or re-prompt this waiting build.
void dismissWebAppUpdatePrompt() => dismissWebAppUpdatePromptImpl();
