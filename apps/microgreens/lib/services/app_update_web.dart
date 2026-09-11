import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _dismissedKey = 'pwa_update_dismissed';
const _shownKey = 'pwa_update_prompt_shown';
const _applyingKey = 'pwa_applying_update';

void _showInstallingScreen() {
  try {
    final fn = web.window.getProperty('agronizerBeginPwaInstall'.toJS);
    if (fn == null || fn.isUndefinedOrNull) return;
    (fn as JSFunction).callAsFunction();
  } catch (_) {}
}

String? _readDismissed() {
  try {
    final local = web.window.localStorage.getItem(_dismissedKey);
    if (local != null && local.isNotEmpty) return local;
  } catch (_) {}
  try {
    final session = web.window.sessionStorage.getItem(_dismissedKey);
    if (session != null && session.isNotEmpty) return session;
  } catch (_) {}
  return null;
}

void _writeDismissed(String key) {
  try {
    web.window.localStorage.setItem(_dismissedKey, key);
  } catch (_) {}
  try {
    web.window.sessionStorage.setItem(_dismissedKey, key);
  } catch (_) {}
}

void _clearDismissed() {
  try {
    web.window.localStorage.removeItem(_dismissedKey);
  } catch (_) {}
  try {
    web.window.sessionStorage.removeItem(_dismissedKey);
  } catch (_) {}
}

bool _isDismissedWaiting(web.ServiceWorker? waiting) {
  if (waiting == null) return false;
  final dismissed = _readDismissed();
  if (dismissed == null || dismissed.isEmpty) return false;
  try {
    return dismissed == waiting.scriptURL;
  } catch (_) {
    return false;
  }
}

/// True when a newer service worker is waiting for SKIP_WAITING.
Future<bool> hasWaitingWebAppUpdateImpl() async {
  try {
    if (web.window.sessionStorage.getItem('agronizer_full_setup_v1') == '1') {
      return false;
    }
    if (web.document.getElementById('agronizer-gate') != null) {
      return false;
    }
    final sw = web.window.navigator.serviceWorker;
    final registration = await sw.getRegistration().toDart;
    if (registration == null) return false;
    try {
      await registration.update().toDart;
    } catch (_) {}
    final waiting = registration.waiting;
    if (waiting == null || sw.controller == null) return false;
    if (_isDismissedWaiting(waiting)) return false;
    return true;
  } catch (_) {
    return false;
  }
}

/// True when the HTML PWA prompt already handled this page load.
///
/// Does not treat a persisted «Позже» as "shown" — that would block unrelated
/// update offers. Waiting-worker dismiss is checked in [hasWaitingWebAppUpdateImpl].
bool htmlPwaUpdatePromptShownImpl() {
  try {
    if (web.window.sessionStorage.getItem(_shownKey) == '1') return true;
  } catch (_) {}
  try {
    final flagged = web.window.getProperty('__agronizerPwaUpdatePrompted'.toJS);
    if (flagged != null && !flagged.isUndefinedOrNull) {
      final asBool = flagged.dartify();
      if (asBool == true) return true;
    }
  } catch (_) {}
  return false;
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
    web.window.sessionStorage.setItem(_shownKey, '1');
  } catch (_) {}
  // Fallback when pwa_update.js is not loaded yet.
  () async {
    try {
      final sw = web.window.navigator.serviceWorker;
      final registration = await sw.getRegistration().toDart;
      final waiting = registration?.waiting;
      final url = waiting?.scriptURL;
      if (url != null && url.isNotEmpty) {
        _writeDismissed(url);
      }
    } catch (_) {}
  }();
}

/// Returns true if the page will reload to pick up the new PWA build.
Future<bool> applyWebAppUpdateImpl() async {
  try {
    final storage = web.window.sessionStorage;
    if (storage.getItem(_applyingKey) == '1') {
      storage.removeItem(_applyingKey);
      return false;
    }
    storage.setItem(_applyingKey, '1');
  } catch (_) {}

  _clearDismissed();
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
