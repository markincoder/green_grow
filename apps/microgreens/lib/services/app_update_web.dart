import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

void _showInstallingScreen() {
  try {
    final fn = web.window.getProperty('agronizerBeginPwaInstall'.toJS);
    if (fn == null || fn.isUndefinedOrNull) return;
    (fn as JSFunction).callAsFunction();
  } catch (_) {}
}

/// True when a newer service worker is waiting for SKIP_WAITING.
Future<bool> hasWaitingWebAppUpdateImpl() async {
  try {
    final dismissed = web.window.sessionStorage.getItem('pwa_update_dismissed');
    if (dismissed != null && dismissed.isNotEmpty) return false;
    final sw = web.window.navigator.serviceWorker;
    final registration = await sw.getRegistration().toDart;
    if (registration == null) return false;
    try {
      await registration.update().toDart;
    } catch (_) {}
    return registration.waiting != null && sw.controller != null;
  } catch (_) {
    return false;
  }
}

/// True when the HTML PWA prompt already handled this update (shown or dismissed).
bool htmlPwaUpdatePromptShownImpl() {
  try {
    final storage = web.window.sessionStorage;
    if (storage.getItem('pwa_update_prompt_shown') == '1') return true;
    final dismissed = storage.getItem('pwa_update_dismissed');
    return dismissed != null && dismissed.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Remember that the user chose «Позже» for the waiting PWA update.
void dismissWebAppUpdatePromptImpl() {
  try {
    final fn = web.window.getProperty('agronizerDismissPwaUpdate'.toJS);
    if (fn != null && !fn.isUndefinedOrNull) {
      (fn as JSFunction).callAsFunction();
      return;
    }
  } catch (_) {}
  try {
    web.window.sessionStorage.setItem('pwa_update_prompt_shown', '1');
  } catch (_) {}
}

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

  _showInstallingScreen();

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
