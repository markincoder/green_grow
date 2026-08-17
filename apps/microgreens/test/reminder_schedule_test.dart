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
    test('orders harvest, to light, sow, then water from multiple crops', () {
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
        soakReminderHours: 8,
      );

      expect(items.length, 4);
      expect(items[0].text, contains('Собрать урожай'));
      expect(items[0].text, contains('Редис'));
      expect(items[1].text, contains('Пора на свет'));
      expect(items[1].text, contains('Горчица'));
      expect(items[2].text, contains('Пора посеять'));
      expect(items[2].text, contains('Горох'));
      expect(items[3].text, 'Вся зелень. Проверьте уровень воды');
    });

    test('keeps dismissed items marked done for that day only', () {
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
        soakReminderHours: 8,
        dismissedKeys: {key},
      );
      expect(items, hasLength(1));
      expect(items.single.done, isTrue);
      expect(items.single.key, key);
      expect(items.single.text, contains('Пора на свет'));

      final digest = ReminderService.buildDailyDigestBody(
        plants: plants,
        day: day,
        dismissedKeys: {key},
      );
      expect(digest, isNull);

      // Next day: same overdue action is active again (new day key).
      final nextDay = day.add(const Duration(days: 1));
      final nextItems = ReminderService.buildTodayReminders(
        plants: plants,
        day: nextDay,
        soakReminderHours: 8,
        dismissedKeys: {key},
      );
      expect(nextItems, hasLength(1));
      expect(nextItems.single.done, isFalse);
      expect(
        ReminderService.buildDailyDigestBody(
          plants: plants,
          day: nextDay,
          dismissedKeys: {key},
        ),
        isNotNull,
      );
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
      );
      expect(body, isNotNull);
      expect(body!.contains('Проверьте уровень воды'), isFalse);
    });
  });

  test('soak reminder uses manual hours setting, not culture table', () {
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
      garden.soakReminderAt(hoursAfterStart: 8),
      DateTime(2026, 8, 8, 18, 0),
    );
  });
}
