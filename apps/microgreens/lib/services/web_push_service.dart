import 'web_push_service_stub.dart'
    if (dart.library.html) 'web_push_service_web.dart';

/// Web Push via agronizer-push (no-op on non-web).
abstract final class WebPushService {
  static bool get isSupported => webPushIsSupported;

  static Future<String> deviceId() => webPushDeviceId();

  static Future<bool> ensureSubscribed() => webPushEnsureSubscribed();

  static Future<void> unsubscribe() => webPushUnsubscribe();

  /// Replace server-side schedule for this browser.
  /// [ackIds] marks soak-/germinate- items delivered without sending (overdue
  /// while the app is open).
  static Future<void> syncSchedule(
    List<WebPushScheduleItem> items, {
    List<String> ackIds = const [],
  }) =>
      webPushSyncSchedule(items, ackIds: ackIds);

  /// Show install + notifications onboarding overlay (web only).
  static void showSetup() => webPushShowSetup();

  /// Hide onboarding overlay so Flutter dialogs are on top.
  static void hideSetup() => webPushHideSetup();

  /// Tell PWA that Flutter is ready to own the notify confirm flow.
  static void markFlutterReady() => webPushMarkFlutterReady();

  /// After in-app confirm + browser prompt finished.
  static void signalNotifyFlowDone({required bool granted}) =>
      webPushSignalNotifyFlowDone(granted);

  static bool get permissionGranted => webPushPermissionGranted();

  /// `granted` | `denied` | `default` | `unsupported`
  static String get permissionStatus => webPushPermissionStatus();

  /// Fires when browser notifications were granted (onboarding / settings).
  static void onNotifyGranted(void Function() callback) =>
      webPushOnNotifyGranted(callback);

  /// PWA "Проверить снова" asks Flutter to show the confirm dialog.
  static void onAskNotify(void Function() callback) =>
      webPushOnAskNotify(callback);
}

class WebPushScheduleItem {
  const WebPushScheduleItem({
    required this.id,
    required this.at,
    required this.body,
    this.title = 'Микрозелень',
    this.url = '/apps/microgreens/',
  });

  final String id;
  final DateTime at;
  final String title;
  final String body;
  final String url;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'title': title,
        'body': body,
        'url': url,
      };
}
