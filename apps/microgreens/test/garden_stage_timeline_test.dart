import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/models/plant.dart';
import 'package:green_grow/services/garden_stage_timeline.dart';

void main() {
  test('builds soak, germinate and grow periods from log entries', () {
    final pea = Plant(
      id: 'pea',
      name: 'Горох',
      description: '',
      icon: '🫛',
      images: const [],
      seedGramsMin: 50,
      seedGramsMax: 60,
      soakHoursMin: 8,
      soakHoursMax: 12,
      germinateHoursMin: 48,
      germinateHoursMax: 72,
      growDaysMin: 7,
      growDays: 10,
      light: '',
      temperature: '',
      soil: '',
      tips: const [],
      tags: const [],
      taste: '',
      storage: '',
      tray: '',
      feature: '',
    );
    final garden = GardenPlant(
      id: 'g-pea',
      plantId: pea.id,
      startedAt: DateTime(2026, 8, 17, 8, 43),
      lastWateredAt: DateTime(2026, 8, 17, 8, 43),
      stage: GrowthStage.grow,
      stageChangedAt: DateTime(2026, 8, 20, 12, 36),
    );
    final entries = [
      PlantingLogEntry(
        at: DateTime(2026, 8, 17, 8, 43),
        cycleName: 'Горох от 17 авг',
        action: 'начать',
        stageOrComment: 'замачивание',
      ),
      PlantingLogEntry(
        at: DateTime(2026, 8, 17, 12, 36),
        cycleName: 'Горох от 17 авг',
        action: 'посеять',
        stageOrComment: 'проращивание',
      ),
      PlantingLogEntry(
        at: DateTime(2026, 8, 20, 12, 36),
        cycleName: 'Горох от 17 авг',
        action: 'раскрыть',
        stageOrComment: 'рост',
      ),
    ];
    final now = DateTime(2026, 8, 28, 10, 0);
    final periods = buildGardenStagePeriods(
      entries: entries,
      garden: garden,
      plant: pea,
      now: now,
    );

    expect(periods, hasLength(3));
    expect(periods[0].stage, GrowthStage.soak);
    expect(periods[0].durationLabel(now), '4ч');
    expect(periods[0].rangeLabel(now), '17 авг 8:43-17 авг 12:36');

    expect(periods[1].stage, GrowthStage.germinate);
    expect(periods[1].durationLabel(now), '3 дн');
    expect(periods[1].rangeLabel(now), '17 авг-20 авг');

    expect(periods[2].stage, GrowthStage.grow);
    expect(periods[2].end, isNull);
    expect(periods[2].rangeLabel(now), '20 авг-сегодня');
  });

  test('matches renamed trays by start date suffix', () {
    final garden = GardenPlant(
      id: 'g1',
      plantId: 'pea',
      startedAt: DateTime(2026, 8, 17),
      lastWateredAt: DateTime(2026, 8, 17),
      stage: GrowthStage.grow,
      stageChangedAt: DateTime(2026, 8, 20),
      customName: 'Новое имя',
    );
    final entry = PlantingLogEntry(
      at: DateTime(2026, 8, 17, 8, 43),
      cycleName: 'Горох от 17 авг',
      action: 'начать',
      stageOrComment: 'замачивание',
    );
    expect(matchesGardenCycle(entry, garden), isTrue);
  });
}
