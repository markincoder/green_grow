import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/models/plant.dart';
import 'package:green_grow/services/tray_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Plant pea;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TrayHistoryStore.instance.prefsOverride = null;
    pea = Plant(
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
  });

  test('stores events bound to garden id and keeps metadata after close', () async {
    final garden = GardenPlant(
      id: 'gp-1',
      plantId: pea.id,
      startedAt: DateTime(2026, 8, 20, 18, 20),
      lastWateredAt: DateTime(2026, 8, 20, 18, 20),
      stage: GrowthStage.soak,
      stageChangedAt: DateTime(2026, 8, 20, 18, 20),
      trayCount: 2,
      customName: 'Горох тест',
    );

    await TrayHistoryStore.instance.recordStart(
      garden: garden,
      plant: pea,
      stage: GrowthStage.soak,
      at: DateTime(2026, 8, 20, 18, 20),
    );
    garden.stage = GrowthStage.germinate;
    await TrayHistoryStore.instance.recordAdvance(
      garden: garden,
      plant: pea,
      action: 'посеять',
      stage: GrowthStage.germinate,
      at: DateTime(2026, 8, 21, 8, 5),
    );
    await TrayHistoryStore.instance.recordClose(
      garden: garden,
      plant: pea,
      action: 'собрать',
      at: DateTime(2026, 8, 24, 17, 47),
    );

    final events = await TrayHistoryStore.instance.eventsFor('gp-1');
    expect(events, hasLength(3));
    expect(
      trayHistoryLineLabel(events[0]),
      '20.08.2026 18:20 старт → замачивание',
    );
    expect(
      trayHistoryLineLabel(events[1]),
      '21.08.2026 08:05 посеять → проращивание',
    );
    expect(trayHistoryLineLabel(events[2]), '24.08.2026 17:47 собрать');

    final record = await TrayHistoryStore.instance.recordFor('gp-1');
    expect(record, isNotNull);
    expect(record!.displayName, 'Горох тест');
    expect(record.trayCount, 2);
    expect(record.startedAt, DateTime(2026, 8, 20, 18, 20));
  });

  test('rename updates metadata without a new event', () async {
    final garden = GardenPlant(
      id: 'gp-2',
      plantId: pea.id,
      startedAt: DateTime(2026, 8, 20),
      lastWateredAt: DateTime(2026, 8, 20),
      stage: GrowthStage.soak,
      customName: 'A',
    );
    await TrayHistoryStore.instance.recordStart(
      garden: garden,
      plant: pea,
      stage: GrowthStage.soak,
      at: DateTime(2026, 8, 20, 10),
    );
    garden.customName = 'B';
    await TrayHistoryStore.instance.syncMetadata(garden: garden, plant: pea);

    final events = await TrayHistoryStore.instance.eventsFor('gp-2');
    expect(events, hasLength(1));
    final record = await TrayHistoryStore.instance.recordFor('gp-2');
    expect(record!.displayName, 'B');
  });

  test('undoLastEvent removes the last action', () async {
    final garden = GardenPlant(
      id: 'gp-3',
      plantId: pea.id,
      startedAt: DateTime(2026, 8, 20),
      lastWateredAt: DateTime(2026, 8, 20),
      stage: GrowthStage.soak,
    );
    await TrayHistoryStore.instance.recordStart(
      garden: garden,
      plant: pea,
      stage: GrowthStage.soak,
      at: DateTime(2026, 8, 20, 10),
    );
    await TrayHistoryStore.instance.recordAdvance(
      garden: garden,
      plant: pea,
      action: 'посеять',
      stage: GrowthStage.germinate,
      at: DateTime(2026, 8, 21, 8),
    );
    await TrayHistoryStore.instance.undoLastEvent('gp-3');
    final events = await TrayHistoryStore.instance.eventsFor('gp-3');
    expect(events, hasLength(1));
    expect(events.single.action, 'старт');
  });
}
