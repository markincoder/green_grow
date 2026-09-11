import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/data/plants_data.dart';
import 'package:green_grow/models/plant.dart';
import 'package:green_grow/services/reminder_service.dart';
import 'package:green_grow/state/settings_store.dart';

void main() {
  group('ReminderService.scheduleDateTime', () {
    const time = TimeOfDay(hour: 9, minute: 0);

    test('schedules future day at reminder clock time', () {
      final now = DateTime(2026, 8, 8, 10, 0);
      final when = ReminderService.scheduleDateTime(
        actionAt: DateTime(2026, 8, 10, 15, 30),
        reminderTime: time,
        now: now,
      );
      expect(when, DateTime(2026, 8, 10, 9, 0));
    });

    test('schedules today if reminder time is still ahead', () {
      final now = DateTime(2026, 8, 8, 8, 0);
      final when = ReminderService.scheduleDateTime(
        actionAt: DateTime(2026, 8, 8, 18, 0),
        reminderTime: time,
        now: now,
      );
      expect(when, DateTime(2026, 8, 8, 9, 0));
    });

    test('skips today when reminder time already passed', () {
      final now = DateTime(2026, 8, 8, 10, 0);
      final when = ReminderService.scheduleDateTime(
        actionAt: DateTime(2026, 8, 8, 18, 0),
        reminderTime: time,
        now: now,
      );
      expect(when, isNull);
    });

    test('skips past days', () {
      final now = DateTime(2026, 8, 8, 10, 0);
      final when = ReminderService.scheduleDateTime(
        actionAt: DateTime(2026, 8, 7, 9, 0),
        reminderTime: time,
        now: now,
      );
      expect(when, isNull);
    });
  });

  group('ReminderService.buildTodayReminders', () {
    test('orders soak, germinate, grow, then water; done items after active', () {
      final radish = plantById('radish')!;
      final mustard = plantById('mustard')!;
      final pea = plantById('pea')!;
      final day = DateTime(2026, 8, 9);

      final plants = [
        GardenPlant(
          id: 'g-radish',
          plantId: radish.id,
          startedAt: DateTime(2026, 8, 2),
          lastWateredAt: day,
          stage: GrowthStage.grow,
          stageChangedAt: DateTime(2026, 7, 28),
        ),
        GardenPlant(
          id: 'g-mustard',
          plantId: mustard.id,
          startedAt: DateTime(2026, 8, 1),
          lastWateredAt: day,
          stage: GrowthStage.germinate,
          stageChangedAt: DateTime(2026, 8, 1),
        ),
        GardenPlant(
          id: 'g-pea',
          plantId: pea.id,
          startedAt: DateTime(2026, 8, 5),
          lastWateredAt: day,
          stage: GrowthStage.soak,
          stageChangedAt: DateTime(2026, 8, 5, 0, 0),
        ),
      ];

      final items = ReminderService.buildTodayReminders(
        plants: plants,
        day: day,
        now: DateTime(2026, 8, 9, 12),
      );

      expect(items.length, 4);
      expect(items[0].title, contains('Горох'));
      expect(items[0].title, 'Горох от 5 авг');
      expect(items[0].actionLabel, 'посеять');
      expect(items[1].title, contains('Горчица'));
      expect(items[1].actionLabel, 'раскрыть');
      expect(items[2].title, contains('Редис'));
      expect(items[2].actionLabel, 'собрать');
      expect(items[3].title, 'Вся зелень');
      expect(items[3].actionLabel, 'проверить воду');

      final mustardKey = SettingsStore.gardenActionKey(
        'g-mustard',
        DueActionKind.toLight,
        day,
      );
      final harvestKey = SettingsStore.gardenActionKey(
        'g-radish',
        DueActionKind.harvest,
        day,
      );
      final mixed = ReminderService.buildTodayReminders(
        plants: plants,
        day: day,
        now: DateTime(2026, 8, 9, 12),
        dismissedKeys: {mustardKey, harvestKey},
      );
      expect(mixed.map((e) => e.kind).toList(), [
        DueActionKind.sow,
        DueActionKind.water,
        DueActionKind.toLight,
        DueActionKind.harvest,
      ]);
      expect(mixed.map((e) => e.done).toList(), [false, false, true, true]);
    });

    test('keeps dismissed actions on the list as done; they return active the next day', () {
      final mustard = plantById('mustard')!;
      final day = DateTime(2026, 8, 9);
      final plants = [
        GardenPlant(
          id: 'g-mustard',
          plantId: mustard.id,
          startedAt: DateTime(2026, 8, 1),
          lastWateredAt: day,
          stage: GrowthStage.germinate,
          stageChangedAt: DateTime(2026, 8, 1),
        ),
      ];

      final key = SettingsStore.gardenActionKey(
        'g-mustard',
        DueActionKind.toLight,
        day,
      );
      final items = ReminderService.buildTodayReminders(
        plants: plants,
        day: day,
        dismissedKeys: {key},
        now: DateTime(2026, 8, 9, 12),
      );
      expect(items, hasLength(1));
      expect(items.single.done, isTrue);

      final digest = ReminderService.buildDailyDigestBody(
        plants: plants,
        day: day,
        dismissedKeys: {key},
        digestAt: DateTime(day.year, day.month, day.day, 9, 0),
      );
      expect(digest, isNull);

      // Next day: same overdue action is active again (new day key).
      final nextDay = day.add(const Duration(days: 1));
      final nextItems = ReminderService.buildTodayReminders(
        plants: plants,
        day: nextDay,
        dismissedKeys: {key},
        now: DateTime(2026, 8, 10, 12),
      );
      expect(nextItems, hasLength(1));
      expect(nextItems.single.done, isFalse);
      expect(nextItems.single.actionLabel, 'раскрыть');
      expect(
        ReminderService.buildDailyDigestBody(
          plants: plants,
          day: nextDay,
          dismissedKeys: {key},
          digestAt: DateTime(nextDay.year, nextDay.month, nextDay.day, 9, 0),
        ),
        isNotNull,
      );
    });

    test('keeps a completed soak reminder after the tray moved to germinate', () {
      final pea = plantById('pea')!;
      final day = DateTime(2026, 8, 9);
      final key = SettingsStore.gardenActionKey(
        'g-pea',
        DueActionKind.sow,
        day,
      );
      final plants = [
        GardenPlant(
          id: 'g-pea',
          plantId: pea.id,
          startedAt: DateTime(2026, 8, 8, 10),
          lastWateredAt: day,
          stage: GrowthStage.germinate,
          stageChangedAt: DateTime(2026, 8, 9, 12),
        ),
      ];
      final items = ReminderService.buildTodayReminders(
        plants: plants,
        day: day,
        dismissedKeys: {key},
        now: DateTime(2026, 8, 9, 12, 5),
      );
      final sow = items.where((e) => e.kind == DueActionKind.sow);
      expect(sow, hasLength(1));
      expect(sow.single.done, isTrue);
      expect(sow.single.actionLabel, 'посеять');
    });

    test('water stays on the list after it was checked today', () {
      final radish = plantById('radish')!;
      final day = DateTime(2026, 8, 9);
      final plants = [
        GardenPlant(
          id: 'g-radish',
          plantId: radish.id,
          startedAt: DateTime(2026, 8, 2),
          lastWateredAt: day,
          stage: GrowthStage.grow,
          stageChangedAt: DateTime(2026, 7, 28),
        ),
      ];
      final waterKey = SettingsStore.waterKey(day);
      final items = ReminderService.buildTodayReminders(
        plants: plants,
        day: day,
        dismissedKeys: {waterKey},
      );
      final water = items.where((e) => e.actionLabel == 'проверить воду');
      expect(water, hasLength(1));
      expect(water.single.done, isTrue);
    });

    test('water only when at least one grow tray', () {
      final arugula = plantById('arugula_mg')!;
      final day = DateTime(2026, 8, 9);
      final plants = [
        GardenPlant(
          id: 'g1',
          plantId: arugula.id,
          startedAt: DateTime(2026, 8, 5),
          lastWateredAt: day,
          stage: GrowthStage.germinate,
          stageChangedAt: DateTime(2026, 8, 5),
        ),
      ];

      final body = ReminderService.buildDailyDigestBody(
        plants: plants,
        day: day,
        digestAt: DateTime(day.year, day.month, day.day, 9, 0),
      );
      expect(body, isNotNull);
      expect(body!.contains('проверить воду'), isFalse);
    });
  });

  test('soak reminder is listed for every soaking tray with elapsed hours', () {
    final pea = plantById('pea')!;
    final started = DateTime(2026, 8, 8, 10, 0);
    final garden = GardenPlant(
      id: 'g-pea',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.soak,
      stageChangedAt: started,
    );
    expect(pea.soakHoursForTiming, 8);
    expect(
      garden.soakReminderAt(pea),
      DateTime(2026, 8, 8, 18, 0),
    );

    final early = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 8),
      now: DateTime(2026, 8, 8, 10, 0),
    );
    expect(early, hasLength(1));
    expect(early.single.title, 'Горох от 8 авг');
    expect(early.single.actionLabel, 'посеять сегодня с 18:00');

    final later = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 8),
      now: DateTime(2026, 8, 8, 18, 0),
    );
    expect(later, hasLength(1));
    expect(later.single.title, 'Горох от 8 авг');
    expect(later.single.actionLabel, 'прошло 8ч - посеять сегодня с 18:00');

    expect(
      ReminderService.buildDailyDigestBody(
        plants: [garden],
        day: DateTime(2026, 8, 8),
        digestAt: DateTime(2026, 8, 8, 17, 59),
      ),
      contains('посеять сегодня с 18:00'),
    );
    expect(
      ReminderService.buildDailyDigestBody(
        plants: [garden],
        day: DateTime(2026, 8, 8),
        digestAt: DateTime(2026, 8, 8, 18, 0),
      ),
      contains('посеять сегодня с 18:00'),
    );
  });

  test('soak sow time rounds start forward to full hour then adds catalog min', () {
    final pea = plantById('pea')!;
    final started = DateTime(2026, 8, 17, 7, 33);
    final garden = GardenPlant(
      id: 'g-pea',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.soak,
      stageChangedAt: started,
    );
    expect(GardenPlant.ceilToHour(started), DateTime(2026, 8, 17, 8, 0));
    expect(garden.soakReminderAt(pea), DateTime(2026, 8, 17, 16, 0));

    final items = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 17),
      now: DateTime(2026, 8, 17, 11, 33),
    );
    expect(items, hasLength(1));
    expect(items.single.title, 'Горох от 17 авг');
    expect(items.single.actionLabel, 'прошло 4ч - посеять сегодня с 16:00');
  });

  test('soak push time is catalog hours, not the daily reminder clock', () {
    final pea = plantById('pea')!;
    final started = DateTime(2026, 8, 20, 11, 33);
    final garden = GardenPlant(
      id: 'g-pea',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.soak,
      stageChangedAt: started,
    );
    expect(garden.soakReminderAt(pea), DateTime(2026, 8, 20, 20, 0));
    expect(
      ReminderService.buildDailyDigestBody(
        plants: [garden],
        day: DateTime(2026, 8, 20),
        digestAt: DateTime(2026, 8, 20, 18, 16),
      ),
      contains('посеять сегодня с 20:00'),
    );
    expect(
      ReminderService.scheduleDateTime(
        actionAt: garden.soakReminderAt(pea),
        reminderTime: const TimeOfDay(hour: 18, minute: 16),
        now: DateTime(2026, 8, 20, 15, 1),
      ),
      DateTime(2026, 8, 20, 18, 16),
      reason: 'daily clock would fire too early — soak must use soakReminderAt',
    );
  });

  test('soak push time matches home reminder: ceil hour + catalog min', () {
    final cilantro = plantById('cilantro')!;
    final started = DateTime(2026, 8, 21, 18, 22);
    final garden = GardenPlant(
      id: 'g-cil',
      plantId: cilantro.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.soak,
      stageChangedAt: started,
    );
    final due = garden.soakReminderAt(cilantro);
    expect(cilantro.soakHoursForTiming, cilantro.soakHoursMin);
    expect(due, DateTime(2026, 8, 21, 19, 0).add(
      Duration(hours: cilantro.soakHoursForTiming),
    ));
    final items = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 21),
      now: started,
    );
    expect(items.single.dueAt, due);
    expect(items.single.actionLabel, contains('с ${due.hour}:00'));
    expect(
      ReminderService.isTrayPushDue(due, DateTime(2026, 8, 21, 18, 50)),
      isFalse,
    );
    expect(
      ReminderService.isTrayPushDue(due, due),
      isTrue,
    );
  });

  test('tray and digest notification ids never overlap', () {
    final soakId = ReminderService.notificationIdFor('gp-1', DueActionKind.sow);
    final germId =
        ReminderService.notificationIdFor('gp-1', DueActionKind.toLight);
    final digestId = ReminderService.digestIdFor(DateTime(2026, 8, 20));
    expect(soakId & 0x10000000, 0x10000000);
    expect(germId & 0x10000000, 0x10000000);
    expect(digestId & 0x20000000, 0x20000000);
    expect(soakId, isNot(digestId));
    expect(germId, isNot(digestId));
    expect(soakId, isNot(germId));
  });

  test('germinate reminder appears on due calendar day before the exact hour', () {
    final arugula = plantById('arugula_mg')!;
    final started = DateTime(2026, 8, 8, 10, 0);
    final garden = GardenPlant(
      id: 'g-arugula',
      plantId: arugula.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.germinate,
      stageChangedAt: started,
    );
    expect(arugula.germinateHoursForTiming, 72);
    expect(
      garden.germinateReminderAt(arugula),
      DateTime(2026, 8, 11, 10, 0),
    );

    final beforeHour = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 11),
      now: DateTime(2026, 8, 11, 9, 59),
    );
    expect(beforeHour, hasLength(1));
    expect(beforeHour.single.actionLabel, 'раскрыть');

    final dayBefore = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 10),
      now: DateTime(2026, 8, 10, 23, 0),
    );
    expect(dayBefore, isEmpty);

    final afterHour = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 11),
      now: DateTime(2026, 8, 11, 10, 0),
    );
    expect(afterHour, hasLength(1));
    expect(afterHour.single.actionLabel, 'раскрыть');
  });

  test('digest keeps uncover after harvest sibling is dismissed', () {
    final onion = plantById('10016')!; // Лук
    final cress = plantById('cress')!;
    final day = DateTime(2026, 8, 25);
    final digestAt = DateTime(2026, 8, 25, 20, 25);

    // Backdated uncover: due long before tray was added — home still lists it.
    final luk = GardenPlant(
      id: 'g-luk',
      plantId: onion.id,
      startedAt: DateTime(2026, 8, 14, 12),
      lastWateredAt: DateTime(2026, 8, 14, 12),
      stage: GrowthStage.germinate,
      stageChangedAt: DateTime(2026, 8, 14, 12),
      createdAt: DateTime(2026, 8, 22, 15),
      customName: 'Лук-шнитт',
    );
    final kress = GardenPlant(
      id: 'g-cress',
      plantId: cress.id,
      startedAt: DateTime(2026, 8, 14, 12),
      lastWateredAt: DateTime(2026, 8, 14, 12),
      stage: GrowthStage.grow,
      stageChangedAt: DateTime(2026, 8, 18, 12),
      createdAt: DateTime(2026, 8, 14, 12),
      customName: 'Кресс-салат',
    );

    expect(ReminderService.skipMissedPhasePushFor(
      kind: DueActionKind.toLight,
      dueAt: luk.germinateReminderAt(onion),
      createdAt: luk.createdAt,
    ), isTrue);

    final both = ReminderService.buildDailyDigestBody(
      plants: [luk, kress],
      day: day,
      digestAt: digestAt,
    );
    expect(both, contains('Лук-шнитт от 14 авг'));
    expect(both, contains('раскрыть'));
    expect(both, contains('Кресс-салат от 14 авг'));
    expect(both, contains('собрать'));

    final afterDismiss = ReminderService.buildDailyDigestBody(
      plants: [luk, kress],
      day: day,
      dismissedKeys: {
        SettingsStore.gardenActionKey(kress.id, DueActionKind.harvest, day),
      },
      digestAt: digestAt,
    );
    expect(afterDismiss, contains('Лук-шнитт от 14 авг'));
    expect(afterDismiss, contains('раскрыть'));
    expect(afterDismiss, isNot(contains('Кресс-салат')));
  });

  test('backdated tray does not push soak/to-light that were due before it was added', () {
    final pea = plantById('pea')!;
    final arugula = plantById('arugula_mg')!;
    final added = DateTime(2026, 8, 22, 15, 0);
    final started = DateTime(2026, 8, 18, 15, 0);

    final soaking = GardenPlant(
      id: 'g-pea-back',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: added,
      stage: GrowthStage.soak,
      stageChangedAt: started,
      createdAt: added,
    );
    final sowDue = soaking.soakReminderAt(pea);
    expect(sowDue.isBefore(added), isTrue);
    expect(
      ReminderService.skipMissedPhasePushFor(
        kind: DueActionKind.sow,
        dueAt: sowDue,
        createdAt: added,
      ),
      isTrue,
    );

    final home = ReminderService.buildTodayReminders(
      plants: [soaking],
      day: DateTime(2026, 8, 22),
      now: added,
    );
    expect(home, hasLength(1));
    expect(home.single.kind, DueActionKind.sow);

    // Digest mirrors home; exact-hour tray push still skips missed phases.
    expect(
      ReminderService.buildDailyDigestBody(
        plants: [soaking],
        day: DateTime(2026, 8, 22),
        digestAt: added,
      ),
      contains('Горох от 18 авг'),
    );

    final germinating = GardenPlant(
      id: 'g-arugula-back',
      plantId: arugula.id,
      startedAt: started,
      lastWateredAt: added,
      stage: GrowthStage.germinate,
      stageChangedAt: started,
      createdAt: added,
    );
    final lightDue = germinating.germinateReminderAt(arugula);
    expect(lightDue.isBefore(added), isTrue);
    expect(
      ReminderService.buildDailyDigestBody(
        plants: [germinating],
        day: DateTime(2026, 8, 22),
        digestAt: added,
      ),
      contains('Рукола от 18 авг'),
    );
  });

  test('same-day overdue soak still goes into the digest', () {
    final pea = plantById('pea')!;
    final started = DateTime(2026, 8, 22, 8, 0);
    final garden = GardenPlant(
      id: 'g-pea-today',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.soak,
      stageChangedAt: started,
      createdAt: started,
    );
    final due = garden.soakReminderAt(pea);
    expect(due, DateTime(2026, 8, 22, 16, 0));
    expect(
      ReminderService.skipMissedPhasePushFor(
        kind: DueActionKind.sow,
        dueAt: due,
        createdAt: started,
      ),
      isFalse,
    );
    expect(
      ReminderService.buildDailyDigestBody(
        plants: [garden],
        day: DateTime(2026, 8, 22),
        digestAt: DateTime(2026, 8, 22, 16, 0),
      ),
      contains('посеять'),
    );
  });

  test('backdated grow tray still notifies harvest, not skipped soak', () {
    final radish = plantById('radish')!;
    final added = DateTime(2026, 8, 22, 15, 0);
    final garden = GardenPlant(
      id: 'g-radish-back',
      plantId: radish.id,
      startedAt: DateTime(2026, 8, 10),
      lastWateredAt: added,
      stage: GrowthStage.grow,
      stageChangedAt: DateTime(2026, 8, 12),
      createdAt: added,
    );
    final body = ReminderService.buildDailyDigestBody(
      plants: [garden],
      day: DateTime(2026, 8, 22),
      digestAt: added,
    );
    expect(body, isNotNull);
    expect(body, contains('собрать'));
    expect(body, isNot(contains('посеять')));
    expect(body, isNot(contains('раскрыть')));
  });

  test('web schedule skips past-due soak/germinate tray phases', () {
    final now = DateTime(2026, 9, 5, 12, 0);
    expect(
      ReminderService.shouldUploadWebTrayPhase(
        DateTime(2026, 9, 5, 12, 1),
        now,
      ),
      isTrue,
    );
    expect(
      ReminderService.shouldUploadWebTrayPhase(
        DateTime(2026, 9, 5, 12, 0),
        now,
      ),
      isFalse,
    );
    expect(
      ReminderService.shouldUploadWebTrayPhase(
        DateTime(2026, 8, 28, 9, 0),
        now,
      ),
      isFalse,
    );
  });

  test('web tray delivery key is id-only for soak and germinate', () {
    expect(
      ReminderService.webTrayDeliveryKey(
        'soak-g1',
        '2026-08-20T13:00:00.000Z',
      ),
      'soak-g1',
    );
    expect(
      ReminderService.webTrayDeliveryKey(
        'germinate-g-luk',
        '2026-08-18T09:00:00.000Z',
      ),
      'germinate-g-luk',
    );
    expect(
      ReminderService.webTrayDeliveryKey(
        'digest-2026820',
        '2026-08-20T06:00:00.000Z',
      ),
      'digest-2026820|2026-08-20T06:00:00.000Z',
    );
  });

  test('tray sent token is stable per garden phase', () {
    final soak = ReminderService.trayPhaseDedupeKey('g-pea', DueActionKind.sow);
    final light =
        ReminderService.trayPhaseDedupeKey('g-pea', DueActionKind.toLight);
    expect(ReminderService.traySentToken(soak), ReminderService.traySentToken(soak));
    expect(
      ReminderService.traySentToken(soak),
      isNot(ReminderService.traySentToken(light)),
    );
  });

  test('notification ids are stable across repeated calls', () {
    final a = ReminderService.notificationIdFor('g-pea', DueActionKind.sow);
    final b = ReminderService.notificationIdFor('g-pea', DueActionKind.sow);
    expect(a, b);
    expect(
      a,
      isNot(ReminderService.notificationIdFor('g-pea', DueActionKind.toLight)),
    );
    expect(
      ReminderService.stableStringHash('g-pea|0'),
      ReminderService.stableStringHash('g-pea|0'),
    );
  });

  test('digest still lists soak when separate soak push is disabled', () {
    final pea = plantById('pea')!;
    final garden = GardenPlant(
      id: 'g-pea-digest',
      plantId: pea.id,
      startedAt: DateTime(2026, 8, 20, 8),
      lastWateredAt: DateTime(2026, 8, 20, 8),
      stage: GrowthStage.soak,
      stageChangedAt: DateTime(2026, 8, 20, 8),
    );
    final digestAt = DateTime(2026, 8, 20, 9, 0);
    final body = ReminderService.buildDailyDigestBody(
      plants: [garden],
      day: DateTime(2026, 8, 20),
      digestAt: digestAt,
    );
    expect(body, isNotNull);
    expect(body, contains('Горох'));
  });
}
