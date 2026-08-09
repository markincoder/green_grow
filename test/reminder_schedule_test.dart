import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/data/plants_data.dart';
import 'package:green_grow/models/plant.dart';
import 'package:green_grow/services/reminder_service.dart';

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

  group('ReminderService.buildDailyDigestBody', () {
    test('orders harvest, to light, then water', () {
      final basil = plantById('basil_mg')!;
      final arugula = plantById('arugula_mg')!;
      final day = DateTime(2026, 8, 9);

      final plants = [
        GardenPlant(
          id: 'g-basil',
          plantId: basil.id,
          startedAt: DateTime(2026, 8, 1),
          lastWateredAt: day,
          stage: GrowthStage.grow,
          // growDays max 12 → due on/before Aug 9
          stageChangedAt: DateTime(2026, 7, 28),
        ),
        GardenPlant(
          id: 'g-arugula',
          plantId: arugula.id,
          startedAt: DateTime(2026, 8, 5),
          lastWateredAt: day,
          stage: GrowthStage.germinate,
          // germinate max 3 days → due on/before Aug 9
          stageChangedAt: DateTime(2026, 8, 5),
        ),
      ];

      final body = ReminderService.buildDailyDigestBody(
        plants: plants,
        day: day,
      );

      expect(body, isNotNull);
      final lines = body!.split('\n');
      expect(lines.first, contains('Время собирать урожай'));
      expect(lines.first, contains('Базилик от 1авг.'));
      expect(lines[1], contains('Пора на свет'));
      expect(lines[1], contains('Рукола от 5авг.'));
      expect(lines.last, 'Все лотки роста. Проверьте уровень воды');
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

    test('soak trays are not in daily digest', () {
      final pea = plantById('pea')!;
      final day = DateTime(2026, 8, 9);
      final plants = [
        GardenPlant(
          id: 'g-pea',
          plantId: pea.id,
          startedAt: day,
          lastWateredAt: day,
          stage: GrowthStage.soak,
          stageChangedAt: day,
        ),
      ];

      expect(
        ReminderService.buildDailyDigestBody(plants: plants, day: day),
        isNull,
      );
    });
  });

  test('soak reminder uses culture soak hours', () {
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
    expect(pea.soakHoursForTiming, 12);
    expect(
      garden.soakReminderAt(pea),
      DateTime(2026, 8, 8, 22, 0),
    );
  });
}
