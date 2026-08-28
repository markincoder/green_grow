import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const _waterTitle = 'Вся зелень';
  static const _waterAction = 'проверить воду';
  static const _deviceChannel = MethodChannel('com.agronizer.greengrow/device');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _firedPrefsKey = 'tray_push_fired_v1';

  bool _ready = false;
  Future<bool>? _permissionInFlight;
  Future<void> _syncTail = Future.value();
  final Set<String> _firedDue = {};

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

      await _loadFiredDue();
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
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_large'),
      color: const Color(0xFF40916C),
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

  /// Structured reminders for a calendar day.
  /// Active items first, then completed. Inside each group:
  /// soak → germinate → grow, water last.
  static List<TodayReminderItem> buildTodayReminders({
    required List<GardenPlant> plants,
    required DateTime day,
    Set<String> dismissedKeys = const {},
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final harvest = <TodayReminderItem>[];
    final toLight = <TodayReminderItem>[];
    final sow = <TodayReminderItem>[];
    var anyGrow = false;

    TodayReminderItem item({
      required String key,
      required String title,
      required String actionLabel,
      required DueActionKind? kind,
      required String? gardenId,
      DateTime? dueAt,
      DateTime? createdAt,
    }) =>
        TodayReminderItem(
          key: key,
          title: title,
          actionLabel: actionLabel,
          kind: kind,
          gardenId: gardenId,
          dueAt: dueAt,
          createdAt: createdAt,
          done: dismissedKeys.contains(key),
        );

    for (final garden in plants) {
      final plant = plantById(garden.plantId);
      if (plant == null) continue;

      if (garden.stage == GrowthStage.soak) {
        if (!plant.needsSoak) continue;
        final key = SettingsStore.gardenActionKey(
          garden.id,
          DueActionKind.sow,
          day,
        );
        sow.add(
          item(
            key: key,
            title: garden.titleWithDate(plant),
            actionLabel: garden.soakActionLabel(plant, at),
            kind: DueActionKind.sow,
            gardenId: garden.id,
            dueAt: garden.soakReminderAt(plant),
            createdAt: garden.createdAt,
          ),
        );
        continue;
      }

      if (garden.isInGerminateStage) {
        if (!plant.hasGerminateStage) continue;
        final when = garden.germinateReminderAt(plant);
        // Calendar day (same as status / harvest), not wall-clock hour.
        if (!_onOrBeforeDay(when, day)) continue;
        final key = SettingsStore.gardenActionKey(
          garden.id,
          DueActionKind.toLight,
          day,
        );
        final action = DueAction(kind: DueActionKind.toLight, at: when);
        toLight.add(
          item(
            key: key,
            title: garden.titleWithDate(plant),
            actionLabel: action.message,
            kind: DueActionKind.toLight,
            gardenId: garden.id,
            dueAt: when,
            createdAt: garden.createdAt,
          ),
        );
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
              title: garden.titleWithDate(plant),
              actionLabel: due.message,
            kind: DueActionKind.harvest,
            gardenId: garden.id,
            createdAt: garden.createdAt,
          ),
          );
        }
      }
    }

    for (final garden in plants) {
      final plant = plantById(garden.plantId);
      if (plant == null) continue;
      final title = garden.titleWithDate(plant);

      void keepCompleted(
        DueActionKind kind,
        String actionLabel,
        List<TodayReminderItem> bucket,
      ) {
        final key = SettingsStore.gardenActionKey(garden.id, kind, day);
        if (!dismissedKeys.contains(key)) return;
        if (bucket.any((e) => e.key == key)) return;
        bucket.add(
          item(
            key: key,
            title: title,
            actionLabel: actionLabel,
            kind: kind,
            gardenId: garden.id,
          ),
        );
      }

      keepCompleted(DueActionKind.sow, 'посеять', sow);
      keepCompleted(DueActionKind.toLight, 'раскрыть', toLight);
      keepCompleted(DueActionKind.harvest, 'собрать', harvest);
    }

    final items = <TodayReminderItem>[...sow, ...toLight, ...harvest];
    final waterKey = SettingsStore.waterKey(day);
    if (anyGrow) {
      items.add(
        item(
          key: waterKey,
          title: _waterTitle,
          actionLabel: _waterAction,
          kind: DueActionKind.water,
          gardenId: null,
        ),
      );
    }
    items.sort(_compareTodayReminders);
    return items;
  }

  static int _compareTodayReminders(TodayReminderItem a, TodayReminderItem b) {
    final byDone = (a.done ? 1 : 0).compareTo(b.done ? 1 : 0);
    if (byDone != 0) return byDone;
    return _stageRank(a.kind).compareTo(_stageRank(b.kind));
  }

  static int _stageRank(DueActionKind? kind) => switch (kind) {
        DueActionKind.sow => 0,
        DueActionKind.toLight => 1,
        DueActionKind.harvest => 2,
        DueActionKind.water || null => 3,
      };

  /// Daily digest lines, sorted: soak → germinate → grow → water.
  /// Matches undismissed home reminders for [day] (one combined push).
  /// Backdated soak/to-light still appear here; exact-hour tray pushes keep
  /// [skipMissedPhasePush] separately so adding an old tray does not spam.
  @visibleForTesting
  static String? buildDailyDigestBody({
    required List<GardenPlant> plants,
    required DateTime day,
    Set<String> dismissedKeys = const {},
    required DateTime digestAt,
  }) {
    final items = buildTodayReminders(
      plants: plants,
      day: day,
      dismissedKeys: dismissedKeys,
      now: digestAt,
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
    required bool soakSeparateEnabled,
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
        if (!soakSeparateEnabled) continue;
        if (garden.stage != GrowthStage.soak) continue;
        final plant = plantById(garden.plantId);
        if (plant == null || !plant.needsSoak) continue;
        final key = SettingsStore.gardenActionKey(
          garden.id,
          DueActionKind.sow,
          today,
        );
        if (dismissedKeys.contains(key)) continue;
        final when = garden.soakReminderAt(plant);
        if (skipMissedPhasePushFor(
          kind: DueActionKind.sow,
          dueAt: when,
          createdAt: garden.createdAt,
        )) {
          continue;
        }
        items.add(
          WebPushScheduleItem(
            id: 'soak-${garden.id}',
            at: when,
            body:
                '${garden.titleWithDate(plant)}\n${garden.soakActionLabel(plant, when)}',
          ),
        );
      }

      for (final garden in plants) {
        if (garden.stage != GrowthStage.germinate) continue;
        final plant = plantById(garden.plantId);
        if (plant == null || !plant.hasGerminateStage) continue;
        final key = SettingsStore.gardenActionKey(
          garden.id,
          DueActionKind.toLight,
          today,
        );
        if (dismissedKeys.contains(key)) continue;
        final when = garden.germinateReminderAt(plant);
        if (skipMissedPhasePushFor(
          kind: DueActionKind.toLight,
          dueAt: when,
          createdAt: garden.createdAt,
        )) {
          continue;
        }
        final action = DueAction(kind: DueActionKind.toLight, at: when);
        items.add(
          WebPushScheduleItem(
            id: 'germinate-${garden.id}',
            at: when,
            body: garden.pushLine(plant, action),
          ),
        );
      }

      for (var i = 0; i < _digestHorizonDays; i++) {
        final day = today.add(Duration(days: i));
        final dayDismissed = i == 0 ? dismissedKeys : const <String>{};
        final when = DateTime(
          day.year,
          day.month,
          day.day,
          reminderTime.hour,
          reminderTime.minute,
        );
        if (!when.isAfter(now)) continue;
        final body = buildDailyDigestBody(
          plants: plants,
          day: day,
          dismissedKeys: dayDismissed,
          digestAt: when,
        );
        if (body == null) continue;
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
    bool soakSeparateEnabled = true,
    Set<String> dismissedKeys = const {},
  }) {
    // Serialize: overlapping cancel/reschedule dropped soak alarms when the
    // app went to background (lifecycle inactive) or access rechecked.
    final job = _syncTail.then(
      (_) => _syncUnlocked(
        plants: plants,
        reminderTime: reminderTime,
        enabled: enabled,
        soakSeparateEnabled: soakSeparateEnabled,
        dismissedKeys: dismissedKeys,
      ),
    );
    _syncTail = job.catchError((_) {});
    return job;
  }

  Future<void> _syncUnlocked({
    required List<GardenPlant> plants,
    required TimeOfDay reminderTime,
    required bool enabled,
    required bool soakSeparateEnabled,
    required Set<String> dismissedKeys,
  }) async {
    if (kIsWeb) {
      await _syncWebPush(
        plants: plants,
        reminderTime: reminderTime,
        enabled: enabled,
        soakSeparateEnabled: soakSeparateEnabled,
        dismissedKeys: dismissedKeys,
      );
      return;
    }
    if (!_ready || !isSupportedPlatform) return;
    try {
      if (!enabled) {
        final pending = await _plugin.pendingNotificationRequests();
        for (final request in pending) {
          await _plugin.cancel(request.id);
        }
        return;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final keepIds = <int>{};

      for (final garden in plants) {
        if (!soakSeparateEnabled) continue;
        if (garden.stage != GrowthStage.soak) continue;
        final plant = plantById(garden.plantId);
        if (plant == null || !plant.needsSoak) continue;
        final key = SettingsStore.gardenActionKey(
          garden.id,
          DueActionKind.sow,
          today,
        );
        if (dismissedKeys.contains(key)) continue;
        final when = garden.soakReminderAt(plant);
        if (skipMissedPhasePushFor(
          kind: DueActionKind.sow,
          dueAt: when,
          createdAt: garden.createdAt,
        )) {
          continue;
        }
        final id = notificationIdFor(garden.id, DueActionKind.sow);
        keepIds.add(id);
        try {
          await _scheduleSoak(
            garden: garden,
            plant: plant,
            now: now,
            id: id,
          );
        } catch (e, st) {
          debugPrint('ReminderService: soak ${garden.id}: $e\n$st');
        }
      }

      for (final garden in plants) {
        if (garden.stage != GrowthStage.germinate) continue;
        final plant = plantById(garden.plantId);
        if (plant == null || !plant.hasGerminateStage) continue;
        final key = SettingsStore.gardenActionKey(
          garden.id,
          DueActionKind.toLight,
          today,
        );
        if (dismissedKeys.contains(key)) continue;
        final when = garden.germinateReminderAt(plant);
        if (skipMissedPhasePushFor(
          kind: DueActionKind.toLight,
          dueAt: when,
          createdAt: garden.createdAt,
        )) {
          continue;
        }
        final id = notificationIdFor(garden.id, DueActionKind.toLight);
        keepIds.add(id);
        try {
          await _scheduleGerminate(
            garden: garden,
            plant: plant,
            now: now,
            id: id,
          );
        } catch (e, st) {
          debugPrint('ReminderService: germinate ${garden.id}: $e\n$st');
        }
      }

      for (var i = 0; i < _digestHorizonDays; i++) {
        final day = today.add(Duration(days: i));
        // Day-scoped dismissals: only today's checks silence today's digest.
        final dayDismissed = i == 0 ? dismissedKeys : const <String>{};
        final when = DateTime(
          day.year,
          day.month,
          day.day,
          reminderTime.hour,
          reminderTime.minute,
        );
        if (!when.isAfter(now)) continue;
        final body = buildDailyDigestBody(
          plants: plants,
          day: day,
          dismissedKeys: dayDismissed,
          digestAt: when,
        );
        if (body == null) continue;
        final id = digestIdFor(day);
        keepIds.add(id);
        try {
          await _scheduleAt(
            id: id,
            body: body,
            when: _toTz(when),
          );
        } catch (e, st) {
          debugPrint('ReminderService: digest $day: $e\n$st');
        }
      }

      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (keepIds.contains(request.id)) continue;
        await _plugin.cancel(request.id);
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
    required int id,
  }) async {
    final when = garden.soakReminderAt(plant);
    final text =
        '${garden.titleWithDate(plant)}\n${garden.soakActionLabel(plant, when)}';
    debugPrint('ReminderService: soak ${garden.id} at $when (now=$now)');
    await _deliverTrayPush(
      id: id,
      body: text,
      when: when,
      now: now,
    );
  }

  Future<void> _scheduleGerminate({
    required GardenPlant garden,
    required Plant plant,
    required DateTime now,
    required int id,
  }) async {
    final when = garden.germinateReminderAt(plant);
    final action = DueAction(kind: DueActionKind.toLight, at: when);
    final text = garden.pushLine(plant, action);
    await _deliverTrayPush(
      id: id,
      body: text,
      when: when,
      now: now,
    );
  }

  /// Same clock as the home-page reminder: catalog min hours, ceiled to the hour.
  /// If that instant is already now (clock jumped / missed alarm), show once.
  Future<void> _deliverTrayPush({
    required int id,
    required String body,
    required DateTime when,
    required DateTime now,
  }) async {
    final sent = traySentToken(id);
    if (_firedDue.contains(sent)) return;

    if (when.isAfter(now)) {
      await _scheduleAt(
        id: id,
        body: body,
        when: _toTz(when),
      );
      _firedDue.add(traySchedToken(id, when));
      await _persistFiredDue();
      return;
    }

    final sched = traySchedToken(id, when);
    if (_firedDue.contains(sched)) {
      try {
        final pending = await _plugin.pendingNotificationRequests();
        if (pending.any((p) => p.id == id)) return;
      } catch (_) {}
      _firedDue
        ..remove(sched)
        ..add(sent);
      await _persistFiredDue();
      debugPrint('ReminderService: skip overdue id=$id (already scheduled)');
      return;
    }

    try {
      await _plugin.cancel(id);
      await _plugin.show(
        id,
        'Микрозелень',
        body,
        _pushDetailsWithBody(body),
      );
      _firedDue.add(sent);
      await _persistFiredDue();
      debugPrint('ReminderService: showed overdue id=$id at $when');
    } catch (e, st) {
      debugPrint('ReminderService: overdue id=$id: $e\n$st');
    }
  }

  /// Tray push already delivered — id-only so re-sync does not re-notify.
  @visibleForTesting
  static String traySentToken(int id) => 'tray:$id';

  @visibleForTesting
  static String traySchedToken(int id, DateTime when) =>
      'sched:$id@${when.millisecondsSinceEpoch}';

  /// Web push server: tray phase pushes dedupe by schedule item id only.
  @visibleForTesting
  static String webTrayDeliveryKey(String itemId, String at) {
    if (itemId.startsWith('soak-') || itemId.startsWith('germinate-')) {
      return itemId;
    }
    return '$itemId|$at';
  }

  Future<void> _loadFiredDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _firedDue
        ..clear()
        ..addAll(prefs.getStringList(_firedPrefsKey) ?? const []);
    } catch (_) {}
  }

  Future<void> _persistFiredDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = _firedDue.toList();
      if (list.length > 80) list = list.sublist(list.length - 80);
      await prefs.setStringList(_firedPrefsKey, list);
    } catch (_) {}
  }

  /// True when soak/to-light was already due before the tray was added
  /// (backdated start). Those phases must not send push.
  @visibleForTesting
  static bool skipMissedPhasePushFor({
    required DueActionKind kind,
    required DateTime dueAt,
    required DateTime createdAt,
  }) {
    if (kind != DueActionKind.sow && kind != DueActionKind.toLight) {
      return false;
    }
    return !dueAt.isAfter(createdAt);
  }

  static bool skipMissedPhasePush(TodayReminderItem item) {
    final dueAt = item.dueAt;
    final createdAt = item.createdAt;
    final kind = item.kind;
    if (dueAt == null || createdAt == null || kind == null) return false;
    return skipMissedPhasePushFor(
      kind: kind,
      dueAt: dueAt,
      createdAt: createdAt,
    );
  }

  /// True when the home-page soak/germinate time has been reached.
  @visibleForTesting
  static bool isTrayPushDue(DateTime reminderAt, DateTime now) =>
      !reminderAt.isAfter(now);

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

  /// Tray action alarms: 0x1xxxxxxx. Must not overlap digest ids.
  @visibleForTesting
  static int notificationIdFor(String gardenId, DueActionKind kind) {
    return 0x10000000 | (Object.hash(gardenId, kind.index) & 0x0fffffff);
  }

  /// Daily digest alarms: 0x2xxxxxxx.
  @visibleForTesting
  static int digestIdFor(DateTime day) {
    return 0x20000000 |
        (Object.hash(day.year, day.month, day.day) & 0x0fffffff);
  }
}

class TodayReminderItem {
  const TodayReminderItem({
    required this.key,
    required this.title,
    required this.actionLabel,
    required this.kind,
    required this.gardenId,
    this.dueAt,
    this.createdAt,
    this.done = false,
  });

  final String key;
  final String title;
  final String actionLabel;

  String get text => '$title\n$actionLabel';
  String get pushText => text;

  /// Shared watering reminder when [DueActionKind.water].
  final DueActionKind? kind;
  final String? gardenId;

  /// When set, daily digest waits until this moment (catalog min hours).
  final DateTime? dueAt;

  /// Tray add time — missed soak/to-light before this is not pushed.
  final DateTime? createdAt;

  /// Checked off on the home list; still shown, not sent in push.
  final bool done;
}
