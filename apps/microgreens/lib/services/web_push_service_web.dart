import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'web_push_service.dart';

JSObject? get _api {
  final push = web.window.getProperty('AgronizerPush'.toJS);
  if (push == null || push.isUndefinedOrNull) return null;
  return push as JSObject;
}

bool get webPushIsSupported {
  final api = _api;
  if (api == null) return false;
  try {
    final result = api.callMethod('isSupported'.toJS);
    return result != null && (result as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}

Future<String> webPushDeviceId() async {
  const key = 'web_push_device_id';
  const lsKey = 'agronizer_web_push_device_id';
  try {
    final fromLs = web.window.localStorage.getItem(lsKey);
    if (fromLs != null && fromLs.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, fromLs);
      return fromLs;
    }
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(key);
  if (existing != null && existing.isNotEmpty) {
    try {
      web.window.localStorage.setItem(lsKey, existing);
    } catch (_) {}
    return existing;
  }
  final id =
      'web-${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch}';
  await prefs.setString(key, id);
  try {
    web.window.localStorage.setItem(lsKey, id);
  } catch (_) {}
  return id;
}

Future<JSAny?> _awaitMaybe(JSAny? result) async {
  if (result == null) return null;
  try {
    return await (result as JSPromise<JSAny?>).toDart;
  } catch (_) {
    return result;
  }
}

Future<bool> webPushEnsureSubscribed() async {
  if (!webPushIsSupported) {
    web.console.warn('AgronizerPush.isSupported=false'.toJS);
    return false;
  }
  final deviceId = await webPushDeviceId();
  try {
    final result = await _awaitMaybe(
      _api!.callMethod('subscribe'.toJS, deviceId.toJS),
    );
    if (result == null) return false;
    if (result is JSBoolean) return result.toDart;
    // Some browsers/interop paths return a non-JSBoolean truthy.
    final raw = result.dartify();
    if (raw is bool) return raw;
    return raw == true || raw?.toString() == 'true';
  } catch (e) {
    web.console.warn('AgronizerPush.subscribe failed: $e'.toJS);
    return false;
  }
}

Future<void> webPushUnsubscribe() async {
  final api = _api;
  if (api == null) return;
  final deviceId = await webPushDeviceId();
  try {
    await _awaitMaybe(api.callMethod('unsubscribe'.toJS, deviceId.toJS));
  } catch (_) {}
}

Future<void> webPushSyncSchedule(
  List<dynamic> items, {
  List<String> ackIds = const [],
}) async {
  if (!webPushIsSupported) return;
  final deviceId = await webPushDeviceId();
  final typed =
      items.whereType<WebPushScheduleItem>().map((e) => e.toJson()).toList();
  final jsItems = typed.jsify();
  final jsOpts = {'ackIds': ackIds}.jsify();
  Future<void> put() async {
    await _awaitMaybe(
      _api!.callMethod(
        'syncSchedule'.toJS,
        deviceId.toJS,
        jsItems,
        jsOpts,
      ),
    );
  }

  try {
    await put();
  } catch (e) {
    if (e.toString().contains('subscribe_required')) {
      final ok = await webPushEnsureSubscribed();
      if (ok) await put();
      return;
    }
    web.console.warn('AgronizerPush.syncSchedule failed: $e'.toJS);
  }
}

/// Open notification setup. iOS Home Screen PWA stays on this page.
void webPushShowSetup() {
  try {
    web.window.localStorage.removeItem('agronizer_gate_done_v1');
    web.window.localStorage.removeItem('agronizer_gate_skip_push_v1');
  } catch (_) {}
  try {
    final push = _api;
    if (push != null) {
      push.callMethod('openSetupGate'.toJS);
      return;
    }
  } catch (_) {}
  try {
    final pwa = web.window.getProperty('AgronizerPwa'.toJS);
    if (pwa != null && !pwa.isUndefinedOrNull) {
      (pwa as JSObject).callMethod('openNotificationSettings'.toJS);
      return;
    }
  } catch (_) {}
  try {
    web.window.location.href = '/apps/microgreens/?from=app&notify=1';
  } catch (_) {}
}

void webPushHideSetup() {
  // No in-app overlay.
}

void webPushMarkFlutterReady() {
  try {
    web.window.dispatchEvent(web.Event('agronizer-flutter-ready'));
  } catch (_) {}
}

void webPushSignalNotifyFlowDone(bool granted) {
  try {
    web.window.dispatchEvent(web.Event('agronizer-notify-flow-done'));
    if (granted) {
      web.window.dispatchEvent(web.Event('agronizer-notify-granted'));
    }
  } catch (_) {}
}

bool webPushPermissionGranted() {
  return webPushPermissionStatus() == 'granted';
}

String webPushPermissionStatus() {
  try {
    final n = web.window.getProperty('Notification'.toJS);
    if (n == null || n.isUndefinedOrNull) return 'unsupported';
    final perm = (n as JSObject).getProperty('permission'.toJS);
    final s = perm == null ? '' : (perm as JSString).toDart;
    if (s == 'granted' || s == 'denied' || s == 'default') return s;
  } catch (_) {}
  return 'denied';
}

/// Listen for gate/onboarding "notifications granted" / enable-reminders flag.
void webPushOnNotifyGranted(void Function() callback) {
  web.window.addEventListener(
    'agronizer-notify-granted',
    ((web.Event _) {
      callback();
    }).toJS,
  );

  try {
    final flag = web.window.localStorage.getItem('agronizer_enable_reminders');
    if (flag == '1' || webPushPermissionGranted()) {
      Future.microtask(callback);
    }
  } catch (_) {}
}

/// Legacy hook from old PWA sheet — unused; kept for API compatibility.
void webPushOnAskNotify(void Function() callback) {
  web.window.addEventListener(
    'agronizer-ask-notify',
    ((web.Event _) {
      callback();
    }).toJS,
  );
}
