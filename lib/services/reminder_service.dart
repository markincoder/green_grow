import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/plants_data.dart';
import '../models/plant.dart';

class ScheduleResult {
  const ScheduleResult({
    required this.ok,
    this.error,
    this.usedExact = false,
    this.batteryUnrestricted = true,
    this.pendingOk = false,
    this.fireAtLabel,
  });

  final bool ok;
  final String? error;
  final bool usedExact;
  final bool batteryUnrestricted;
  final bool pendingOk;
  final String? fireAtLabel;
}

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const _channelId = 'microgreens_reminders_v2';
  static const _channelName = 'Напоминания о лотках';
  static const _channelDescription =
      'Push о посеве, свете, сборе и поливе микрозелени';

  static const _digestHorizonDays = 21;
  static const _waterLine = 'Все лотки роста. Проверьте уровень воды';
  static const _smokeTestId = 0x7f000001;
  static const _deviceChannel = MethodChannel('com.greengrow.green_grow/device');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  Future<bool>? _permissionInFlight;

  bool get isReady => _ready;

  /// Local notifications work on Android / iOS / macOS / Linux — not Windows/Web.
  bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

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
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: true,
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
    if (!isSupportedPlatform) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
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

  /// Daily digest lines, sorted: harvest → to light → water.
  @visibleForTesting
  static String? buildDailyDigestBody({
    required List<GardenPlant> plants,
    required DateTime day,
  }) {
    final harvest = <String>[];
    final toLight = <String>[];
    var anyGrow = false;

    for (final garden in plants) {
      final plant = plantById(garden.plantId);
      if (plant == null) continue;
      final title = garden.titleCompact(plant);

      if (garden.stage == GrowthStage.soak) continue;

      if (garden.isInGerminateStage) {
        final due = garden.dueActions(plant).single;
        if (_onOrBeforeDay(due.at, day)) {
          toLight.add('$title ${due.message}');
        }
        continue;
      }

      if (garden.isReadyToHarvestStage) {
        if (garden.isInGrowStage) anyGrow = true;
        final due = garden.dueActions(plant).single;
        if (_onOrBeforeDay(due.at, day) ||
            garden.stage == GrowthStage.harvest) {
          harvest.add('$title ${due.message}');
        }
      }
    }

    final lines = <String>[...harvest, ...toLight];
    if (anyGrow) lines.add(_waterLine);
    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  /// Immediate Push to verify permissions and channel.
  Future<bool> showTestPush() async {
    if (!isSupportedPlatform) return false;
    if (!_ready) {
      await init();
      if (!_ready) return false;
    }
    try {
      await ensurePermissions();

      const body =
          'Базилик от 1авг. Время собирать урожай!\n'
          'Рукола от 5авг. Пора на свет.\n'
          'Все лотки роста. Проверьте уровень воды';

      await _plugin.show(
        999001,
        'Микрозелень',
        body,
        _pushDetailsWithBody(body),
      );
      return true;
    } catch (e, st) {
      debugPrint('ReminderService.showTestPush failed: $e\n$st');
      return false;
    }
  }

  /// Schedules a notification after [delay] so delivery can be checked
  /// with the app in background. Prefer Home (not force-stop / OEM swipe-kill).
  Future<ScheduleResult> scheduleSmokeTest({
    Duration delay = const Duration(seconds: 45),
  }) async {
    if (!isSupportedPlatform) {
      return const ScheduleResult(ok: false, error: 'Платформа не поддерживает Push');
    }
    if (!_ready) {
      await init();
      if (!_ready) {
        return const ScheduleResult(
          ok: false,
          error: 'Сервис уведомлений не инициализирован',
        );
      }
    }
    try {
      await ensurePermissions();
      final notificationsOk = await areNotificationsEnabled();
      if (!notificationsOk) {
        return const ScheduleResult(
          ok: false,
          error: 'Уведомления выключены в настройках системы',
        );
      }

      var batteryOk = await isBatteryUnrestricted();
      if (!batteryOk) {
        await requestBatteryUnrestricted();
        // User may still be on the system dialog; re-check after a beat.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        batteryOk = await isBatteryUnrestricted();
      }

      await _plugin.cancel(_smokeTestId);

      final when = tz.TZDateTime.now(tz.local).add(delay);
      final fireLabel =
          '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}:${when.second.toString().padLeft(2, '0')}';
      final body =
          'Проверка фоновых напоминаний ($fireLabel). '
          'Если видите это на экране «Домой» — всё работает.';
      final usedExact = await _scheduleAt(
        id: _smokeTestId,
        body: body,
        when: when,
      );

      final pending = await _plugin.pendingNotificationRequests();
      final pendingOk = pending.any((p) => p.id == _smokeTestId);
      debugPrint(
        'ReminderService.smokeTest: exact=$usedExact battery=$batteryOk '
        'pending=$pendingOk when=$when tz=${tz.local.name}',
      );

      if (!pendingOk) {
        return ScheduleResult(
          ok: false,
          error: 'Система не сохранила будильник (pending пуст)',
          usedExact: usedExact,
          batteryUnrestricted: batteryOk,
          fireAtLabel: fireLabel,
        );
      }

      return ScheduleResult(
        ok: true,
        usedExact: usedExact,
        batteryUnrestricted: batteryOk,
        pendingOk: pendingOk,
        fireAtLabel: fireLabel,
      );
    } catch (e, st) {
      debugPrint('ReminderService.scheduleSmokeTest failed: $e\n$st');
      return ScheduleResult(ok: false, error: e.toString());
    }
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

  Future<void> sync({
    required List<GardenPlant> plants,
    required TimeOfDay reminderTime,
    required bool enabled,
  }) async {
    if (!_ready || !isSupportedPlatform) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.id == _smokeTestId) continue;
        await _plugin.cancel(request.id);
      }
      if (!enabled) return;

      final now = DateTime.now();

      for (final garden in plants) {
        if (garden.stage != GrowthStage.soak) continue;
        final plant = plantById(garden.plantId);
        if (plant == null || !plant.needsSoak) continue;
        try {
          await _scheduleSoak(
            garden: garden,
            plant: plant,
            now: now,
          );
        } catch (e, st) {
          debugPrint('ReminderService: soak ${garden.id}: $e\n$st');
        }
      }

      final today = DateTime(now.year, now.month, now.day);
      for (var i = 0; i < _digestHorizonDays; i++) {
        final day = today.add(Duration(days: i));
        final body = buildDailyDigestBody(plants: plants, day: day);
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
  }) async {
    final when = garden.soakReminderAt(plant);
    if (!when.isAfter(now)) return;
    final text = '${garden.titleCompact(plant)} Пора посеять.';
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
