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
      expect(items[0].actionLabel, 'прошло 108ч | посеять 5 авг в 8ч');
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
    expect(early.single.actionLabel, 'прошло 0ч | посеять сегодня в 18ч');

    final later = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 8),
      now: DateTime(2026, 8, 8, 18, 0),
    );
    expect(later, hasLength(1));
    expect(later.single.title, 'Горох от 8 авг');
    expect(later.single.actionLabel, 'прошло 8ч | посеять сегодня в 18ч');

    expect(
      ReminderService.buildDailyDigestBody(
        plants: [garden],
        day: DateTime(2026, 8, 8),
        digestAt: DateTime(2026, 8, 8, 17, 59),
      ),
      isNull,
    );
    expect(
      ReminderService.buildDailyDigestBody(
        plants: [garden],
        day: DateTime(2026, 8, 8),
        digestAt: DateTime(2026, 8, 8, 18, 0),
      ),
      contains('посеять сегодня в 18ч'),
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
    expect(items.single.actionLabel, 'прошло 4ч | посеять сегодня в 16ч');
  });

  test('germinate reminder uses catalog hours, not calendar day', () {
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
    expect(arugula.germinateHoursForTiming, 48);
    expect(
      garden.germinateReminderAt(arugula),
      DateTime(2026, 8, 10, 10, 0),
    );

    final before = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 10),
      now: DateTime(2026, 8, 10, 9, 59),
    );
    expect(before, isEmpty);

    final after = ReminderService.buildTodayReminders(
      plants: [garden],
      day: DateTime(2026, 8, 10),
      now: DateTime(2026, 8, 10, 10, 0),
    );
    expect(after, hasLength(1));
    expect(after.single.actionLabel, 'раскрыть');
  });
}
