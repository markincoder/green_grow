import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';
import '../state/settings_store.dart';
import 'web_push_service.dart';

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const _channelId = 'microgreens_reminders_v2';
  static const _channelName = 'Напоминания о лотках';
  static const _channelDescription =
      'Push о посеве, свете, сборе и поливе микрозелени';

  static const _digestHorizonDays = 21;
  static const _waterLine = 'Вся зелень. Проверьте уровень воды';
  static const _deviceChannel = MethodChannel('com.greengrow.green_grow/device');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  Future<bool>? _permissionInFlight;

  bool get isReady => _ready;

  /// Local notifications work on Android / iOS / macOS / Linux — not Windows/Web.
  /// Web uses [WebPushService] + agronizer-push instead.
  bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  bool get usesWebPush => kIsWeb && WebPushService.isSupported;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Plugin + channel only. Do NOT request runtime permissions here —
  /// Activity is not attached before [runApp], and early requests break init.
  Future<void> init() async {
    if (!isSupportedPlatform) {
      debugPrint(
        'ReminderService: push not supported on $defaultTargetPlatform',
      );
      _ready = false;
      return;
    }
    try {
      await _configureLocalTimezone();

      // Drawable resource name (no @mipmap/ prefix) — required by the plugin.
      const android = AndroidInitializationSettings('ic_notification');
      const ios = DarwinInitializationSettings(
        // Ask only from our in-app dialog / Settings toggle.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(android: android, iOS: ios);
      await _plugin.initialize(settings);

      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

      _ready = true;
    } catch (e, st) {
      debugPrint('ReminderService.init failed: $e\n$st');
      _ready = false;
    }
  }

  /// Call after the Flutter Activity is up (post-[runApp]).
  Future<bool> ensurePermissions() async {
    if (usesWebPush) {
      return WebPushService.ensureSubscribed();
    }
    if (!isSupportedPlatform) return false;
    if (!_ready) {
      await init();
      if (!_ready) return false;
    }

    // Serialize permission prompts — concurrent calls fail with
    // permission_request_in_progress and confuse the user.
    final inFlight = _permissionInFlight;
    if (inFlight != null) return inFlight;

    final future = _ensurePermissionsImpl();
    _permissionInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_permissionInFlight, future)) {
        _permissionInFlight = null;
      }
    }
  }

  Future<bool> _ensurePermissionsImpl() async {
    try {
      var notificationsOk = true;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final enabled = await _android?.areNotificationsEnabled();
        if (enabled != true) {
          notificationsOk =
              await _android?.requestNotificationsPermission() ?? true;
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        notificationsOk = await ios?.requestPermissions(
              alert: true,
              badge: false,
              sound: true,
            ) ??
            false;
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final mac = _plugin.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        notificationsOk = await mac?.requestPermissions(
              alert: true,
              badge: false,
              sound: true,
            ) ??
            false;
      }

      // With USE_EXACT_ALARM this is usually already true after install.
      // Only open the system screen when still blocked (SCHEDULE_EXACT_ALARM path).
      var exactOk = await canScheduleExactAlarms();
      if (!exactOk) {
        exactOk = await _android?.requestExactAlarmsPermission() ?? true;
      }

      debugPrint(
        'ReminderService.permissions: notifications=$notificationsOk '
        'exactAlarms=$exactOk',
      );
      return (notificationsOk != false) && exactOk;
    } catch (e, st) {
      debugPrint('ReminderService.ensurePermissions failed: $e\n$st');
      return false;
    }
  }

  Future<bool> canScheduleExactAlarms() async {
    if (!isSupportedPlatform || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      return await _android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return WebPushService.permissionGranted;
    if (!isSupportedPlatform) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _android?.areNotificationsEnabled() ?? true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final options = await ios?.checkPermissions();
        return options?.isEnabled ?? options?.isAlertEnabled ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final mac = _plugin.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        final options = await mac?.checkPermissions();
        return options?.isEnabled ?? options?.isAlertEnabled ?? false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the system screen where the user can enable notifications for this app.
  Future<void> openNotificationSettings() async {
    if (usesWebPush) {
      WebPushService.showSetup();
      return;
    }
    if (!isSupportedPlatform) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _deviceChannel.invokeMethod<void>('openNotificationSettings');
        return;
      }
      // iOS / macOS: open this app's page in system Settings.
      final uri = Uri.parse('app-settings:');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('ReminderService.openNotificationSettings failed: $e');
    }
  }

  Future<bool> isBatteryUnrestricted() async {
    if (!isSupportedPlatform || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final value =
          await _deviceChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return value ?? true;
    } catch (e) {
      debugPrint('ReminderService.isBatteryUnrestricted failed: $e');
      return true;
    }
  }

  /// Opens the system dialog to exempt the app from battery optimizations.
  Future<void> requestBatteryUnrestricted() async {
    if (!isSupportedPlatform || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _deviceChannel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('ReminderService.requestBatteryUnrestricted failed: $e');
    }
  }

  Future<void> _configureLocalTimezone() async {
    tz_data.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      debugPrint('ReminderService: timezone=$name');
    } catch (e) {
      // Match device wall-clock offset so scheduled local times stay correct.
      final offset = DateTime.now().timeZoneOffset;
      final location = tz.timeZoneDatabase.locations.values.firstWhere(
        (loc) {
          try {
            return tz.TZDateTime.now(loc).timeZoneOffset == offset;
          } catch (_) {
            return false;
          }
        },
        orElse: () => tz.UTC,
      );
      tz.setLocalLocation(location);
      debugPrint(
        'ReminderService: timezone fallback to ${location.name} ($e)',
      );
    }
  }

  NotificationDetails _pushDetailsWithBody(String body) {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: 'Напоминание о лотке',
      styleInformation: BigTextStyleInformation(body),
      fullScreenIntent: false,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
    );
    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  /// Wall-clock time for a calendar-day reminder, or null if it should not fire.
  @visibleForTesting
  static DateTime? scheduleDateTime({
    required DateTime actionAt,
    required TimeOfDay reminderTime,
    required DateTime now,
  }) {
    final day = DateTime(actionAt.year, actionAt.month, actionAt.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day.isBefore(today)) return null;

    final when = DateTime(
      day.year,
      day.month,
      day.day,
      reminderTime.hour,
      reminderTime.minute,
    );
    if (!when.isAfter(now)) return null;
    return when;
  }

  static bool _onOrBeforeDay(DateTime actionAt, DateTime day) {
    final a = DateTime(actionAt.year, actionAt.month, actionAt.day);
    final d = DateTime(day.year, day.month, day.day);
    return !a.isAfter(d);
  }

  /// Structured reminders for a calendar day: harvest → to light → sow → water.
  /// Dismissed items stay in the list with [TodayReminderItem.done] = true.
  static List<TodayReminderItem> buildTodayReminders({
    required List<GardenPlant> plants,
    required DateTime day,
    required int soakReminderHours,
    Set<String> dismissedKeys = const {},
  }) {
    final harvest = <TodayReminderItem>[];
    final toLight = <TodayReminderItem>[];
    final sow = <TodayReminderItem>[];
    var anyGrow = false;

    TodayReminderItem item({
      required String key,
      required String text,
      required String pushText,
      required DueActionKind? kind,
      required String? gardenId,
    }) =>
        TodayReminderItem(
          key: key,
          text: text,
          pushText: pushText,
          kind: kind,
          gardenId: gardenId,
          done: dismissedKeys.contains(key),
        );

    for (final garden in plants) {
      final plant = plantById(garden.plantId);
      if (plant == null) continue;

      if (garden.stage == GrowthStage.soak) {
        if (!plant.needsSoak) continue;
        final when = garden.soakReminderAt(hoursAfterStart: soakReminderHours);
        if (_onOrBeforeDay(when, day)) {
          final key = SettingsStore.gardenActionKey(
            garden.id,
            DueActionKind.sow,
            day,
          );
          final action = DueAction(kind: DueActionKind.sow, at: when);
          sow.add(
            item(
              key: key,
              text: garden.reminderLine(plant, action, day),
              pushText: garden.pushLine(plant, action),
              kind: DueActionKind.sow,
              gardenId: garden.id,
            ),
          );
        }
        continue;
      }

      if (garden.isInGerminateStage) {
        final due = garden.dueActions(plant).single;
        if (_onOrBeforeDay(due.at, day)) {
          final key = SettingsStore.gardenActionKey(
            garden.id,
            DueActionKind.toLight,
            day,
          );
          toLight.add(
            item(
              key: key,
              text: garden.reminderLine(plant, due, day),
              pushText: garden.pushLine(plant, due),
              kind: DueActionKind.toLight,
              gardenId: garden.id,
            ),
          );
        }
        continue;
      }

      if (garden.isReadyToHarvestStage) {
        if (garden.isInGrowStage) anyGrow = true;
        final due = garden.dueActions(plant).single;
        if (_onOrBeforeDay(due.at, day) ||
            garden.stage == GrowthStage.harvest) {
          final key = SettingsStore.gardenActionKey(
            garden.id,
            DueActionKind.harvest,
            day,
          );
          harvest.add(
            item(
              key: key,
              text: garden.reminderLine(plant, due, day),
              pushText: garden.pushLine(plant, due),
              kind: DueActionKind.harvest,
              gardenId: garden.id,
            ),
          );
        }
      }
    }

    final items = <TodayReminderItem>[...harvest, ...toLight, ...sow];
    if (anyGrow) {
      final key = SettingsStore.waterKey(day);
      items.add(
        item(
          key: key,
          text: _waterLine,
          pushText: _waterLine,
          kind: null,
          gardenId: null,
        ),
      );
    }
    return items;
  }

  /// Daily digest lines, sorted: harvest → to light → sow → water.
  /// Completed (dismissed) items are omitted from push text.
  @visibleForTesting
  static String? buildDailyDigestBody({
    required List<GardenPlant> plants,
    required DateTime day,
    int soakReminderHours = 8,
    Set<String> dismissedKeys = const {},
  }) {
    final items = buildTodayReminders(
      plants: plants,
      day: day,
      soakReminderHours: soakReminderHours,
      dismissedKeys: dismissedKeys,
    ).where((e) => !e.done);
    if (items.isEmpty) return null;
    return items.map((e) => e.pushText).join('\n');
  }

  Future<int> pendingCount() async {
    if (!_ready) return 0;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.length;
    } catch (_) {
      return 0;
    }
  }

  /// Web: subscribe + upload digest/soak schedule to agronizer-push.
  Future<void> _syncWebPush({
    required List<GardenPlant> plants,
    required TimeOfDay reminderTime,
    required bool enabled,
    required int soakReminderHours,
    required Set<String> dismissedKeys,
  }) async {
    if (!WebPushService.isSupported) {
      debugPrint('ReminderService: AgronizerPush JS not available');
      return;
    }
    try {
      if (!enabled) {
        await WebPushService.syncSchedule(const []);
        return;
      }
      final subscribed = await WebPushService.ensureSubscribed();
      if (!subscribed) {
        debugPrint('ReminderService: web push subscribe failed');
        return;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final items = <WebPushScheduleItem>[];

      for (final garden in plants) {
        if (garden.stage != GrowthStage.soak) continue;
        final plant = plantById(garden.plantId);
        if (plant == null || !plant.needsSoak) continue;
        final key = SettingsStore.gardenActionKey(
          garden.id,
          DueActionKind.sow,
          today,
        );
        if (dismissedKeys.contains(key)) continue;
        final when =
            garden.soakReminderAt(hoursAfterStart: soakReminderHours);
        if (!when.isAfter(now)) continue;
        final action = DueAction(kind: DueActionKind.sow, at: when);
        items.add(
          WebPushScheduleItem(
            id: 'soak-${garden.id}',
            at: when,
            body: garden.pushLine(plant, action),
          ),
        );
      }

      for (var i = 0; i < _digestHorizonDays; i++) {
        final day = today.add(Duration(days: i));
        final dayDismissed = i == 0 ? dismissedKeys : const <String>{};
        final body = buildDailyDigestBody(
          plants: plants,
          day: day,
          soakReminderHours: soakReminderHours,
          dismissedKeys: dayDismissed,
        );
        if (body == null) continue;
        final when = DateTime(
          day.year,
          day.month,
          day.day,
          reminderTime.hour,
          reminderTime.minute,
        );
        if (!when.isAfter(now)) continue;
        items.add(
          WebPushScheduleItem(
            id: 'digest-${day.year}${day.month}${day.day}',
            at: when,
            body: body,
          ),
        );
      }

      await WebPushService.syncSchedule(items);
      debugPrint('ReminderService: web push schedule=${items.length}');
    } catch (e, st) {
      debugPrint('ReminderService._syncWebPush failed: $e\n$st');
    }
  }

  Future<void> sync({
    required List<GardenPlant> plants,
    required TimeOfDay reminderTime,
    required bool enabled,
    required int soakReminderHours,
    Set<String> dismissedKeys = const {},
  }) async {
    if (kIsWeb) {
      await _syncWebPush(
        plants: plants,
        reminderTime: reminderTime,
        enabled: enabled,
        soakReminderHours: soakReminderHours,
        dismissedKeys: dismissedKeys,
      );
      return;
    }
    if (!_ready || !isSupportedPlatform) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        await _plugin.cancel(request.id);
      }
      if (!enabled) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (final garden in plants) {
        if (garden.stage != GrowthStage.soak) continue;
        final plant = plantById(garden.plantId);
        if (plant == null || !plant.needsSoak) continue;
        final key = SettingsStore.gardenActionKey(
          garden.id,
          DueActionKind.sow,
          today,
        );
        if (dismissedKeys.contains(key)) continue;
        try {
          await _scheduleSoak(
            garden: garden,
            plant: plant,
            now: now,
            soakReminderHours: soakReminderHours,
          );
        } catch (e, st) {
          debugPrint('ReminderService: soak ${garden.id}: $e\n$st');
        }
      }

      for (var i = 0; i < _digestHorizonDays; i++) {
        final day = today.add(Duration(days: i));
        // Day-scoped dismissals: only today's checks silence today's digest.
        final dayDismissed = i == 0 ? dismissedKeys : const <String>{};
        final body = buildDailyDigestBody(
          plants: plants,
          day: day,
          soakReminderHours: soakReminderHours,
          dismissedKeys: dayDismissed,
        );
        if (body == null) continue;
        final when = DateTime(
          day.year,
          day.month,
          day.day,
          reminderTime.hour,
          reminderTime.minute,
        );
        if (!when.isAfter(now)) continue;
        try {
          await _scheduleAt(
            id: _digestId(day),
            body: body,
            when: _toTz(when),
          );
        } catch (e, st) {
          debugPrint('ReminderService: digest $day: $e\n$st');
        }
      }

      final count = await pendingCount();
      debugPrint('ReminderService.sync: scheduled=$count enabled=$enabled');
    } catch (e, st) {
      debugPrint('ReminderService.sync failed: $e\n$st');
    }
  }

  Future<void> _scheduleSoak({
    required GardenPlant garden,
    required Plant plant,
    required DateTime now,
    required int soakReminderHours,
  }) async {
    final when =
        garden.soakReminderAt(hoursAfterStart: soakReminderHours);
    if (!when.isAfter(now)) return;
    final action = DueAction(kind: DueActionKind.sow, at: when);
    final text = garden.pushLine(plant, action);
    await _scheduleAt(
      id: _notificationId(garden.id, DueActionKind.sow),
      body: text,
      when: _toTz(when),
    );
  }

  tz.TZDateTime _toTz(DateTime when) {
    // Interpret wall-clock components in the configured local location.
    return tz.TZDateTime(
      tz.local,
      when.year,
      when.month,
      when.day,
      when.hour,
      when.minute,
      when.second,
    );
  }

  /// Returns whether an exact schedule mode was used.
  Future<bool> _scheduleAt({
    required int id,
    required String body,
    required tz.TZDateTime when,
  }) async {
    // Guard: plugin rejects non-future dates before hitting AlarmManager.
    final now = tz.TZDateTime.now(tz.local);
    if (!when.isAfter(now)) {
      throw StateError(
        'Время в прошлом: when=$when now=$now tz=${tz.local.name}',
      );
    }

    final details = _pushDetailsWithBody(body);
    final exactOk = await canScheduleExactAlarms();

    // Prefer exact/alarmClock when allowed; otherwise go straight to inexact
    // so we don't spam exact_alarms_not_permitted errors.
    final modes = exactOk
        ? const <AndroidScheduleMode>[
            AndroidScheduleMode.alarmClock,
            AndroidScheduleMode.exactAllowWhileIdle,
            AndroidScheduleMode.inexactAllowWhileIdle,
          ]
        : const <AndroidScheduleMode>[
            AndroidScheduleMode.inexactAllowWhileIdle,
            AndroidScheduleMode.inexact,
          ];

    Object? lastError;
    for (final mode in modes) {
      try {
        await _plugin.zonedSchedule(
          id,
          'Микрозелень',
          body,
          when,
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        final usedExact = mode == AndroidScheduleMode.alarmClock ||
            mode == AndroidScheduleMode.exactAllowWhileIdle ||
            mode == AndroidScheduleMode.exact;
        if (!usedExact) {
          debugPrint(
            'ReminderService: id=$id scheduled with fallback mode=$mode',
          );
        }
        return usedExact;
      } catch (e) {
        lastError = e;
        debugPrint('ReminderService: id=$id mode=$mode failed: $e');
      }
    }
    throw StateError('Не удалось запланировать id=$id: $lastError');
  }

  int _notificationId(String gardenId, DueActionKind kind) {
    return Object.hash(gardenId, kind.index) & 0x7fffffff;
  }

  int _digestId(DateTime day) {
    return Object.hash('digest', day.year, day.month, day.day) & 0x7fffffff;
  }
}

class TodayReminderItem {
  const TodayReminderItem({
    required this.key,
    required this.text,
    required this.pushText,
    required this.kind,
    required this.gardenId,
    this.done = false,
  });

  final String key;
  final String text;
  final String pushText;

  /// Null means the shared watering reminder.
  final DueActionKind? kind;
  final String? gardenId;
  final bool done;

  IconData get typeIcon => switch (kind) {
        DueActionKind.sow => Icons.grass_rounded,
        DueActionKind.toLight => Icons.wb_sunny_rounded,
        DueActionKind.harvest => Icons.content_cut_rounded,
        null => Icons.water_drop_rounded,
      };
}
