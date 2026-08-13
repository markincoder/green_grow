import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/data/plants_data.dart';
import 'package:green_grow/models/plant.dart';

void main() {
  test('catalog has microgreens from cultivation table', () {
    expect(plantsCatalog.length, greaterThanOrEqualTo(20));
    final radish = plantById('radish')!;
    expect(radish.needsSoak, isFalse);
    expect(radish.seedGrams, 6);
    expect(radish.germinateHoursMax, 72);
    expect(radish.growDays, 5);
    expect(radish.cycleDaysLabel, '5–8 дн.');

    final pea = plantById('pea')!;
    expect(pea.needsSoak, isTrue);
    expect(pea.soakHoursMin, 8);
    expect(pea.pressKgMin, 1.5);
    expect(pea.seedGrams, 35);

    final sunflower = plantById('sunflower')!;
    expect(sunflower.needsPress, isTrue);
    expect(sunflower.pressKgMin, 1.5);

    final amaranth = plantById('amaranth')!;
    expect(amaranth.hasGerminateStage, isFalse);
    expect(amaranth.hasGrowStage, isTrue);
    expect(GardenPlant.initialStageFor(amaranth), GrowthStage.grow);

    final corn = plantById('corn')!;
    expect(corn.hasGrowStage, isFalse);
    expect(corn.feature, contains('темноте'));
  });

  test('status line follows manual stage, not elapsed time', () {
    final arugula = plantById('arugula_mg')!;
    final pea = plantById('pea')!;
    final now = DateTime(2026, 8, 7, 15);

    final ready = GardenPlant(
      id: '1',
      plantId: arugula.id,
      startedAt: now.subtract(arugula.cycleDuration),
      lastWateredAt: now.subtract(const Duration(days: 1)),
      stage: GrowthStage.harvest,
    );
    expect(ready.titleWithDate(arugula), startsWith('Рукола от '));
    expect(ready.titleWithDate(arugula), isNot(contains('.')));
    expect(ready.statusLine(arugula, now), 'К срезке');
    expect(ready.nextActionLabel(arugula), 'Собрать');

    final dated = GardenPlant(
      id: '1a',
      plantId: arugula.id,
      startedAt: DateTime(2026, 8, 4),
      lastWateredAt: DateTime(2026, 8, 6),
      stage: GrowthStage.germinate,
    );
    expect(dated.titleWithDate(arugula), 'Рукола от 4 авг');

    final fresh = GardenPlant(
      id: '2',
      plantId: arugula.id,
      startedAt: now,
      lastWateredAt: now,
      stage: GrowthStage.germinate,
    );
    expect(fresh.titleWithDate(arugula), 'Рукола от 7 авг');
    expect(fresh.stageVerb(arugula, now), 'Прорастает');
    expect(fresh.statusLine(arugula, now), 'Прорастает. На свет 9 авг');
    expect(fresh.nextActionLabel(arugula), 'На свет');

    final soaking = GardenPlant(
      id: '3',
      plantId: pea.id,
      startedAt: now,
      lastWateredAt: now,
      stage: GrowthStage.soak,
    );
    expect(soaking.stageVerb(pea, now), 'Замачивается');
    expect(soaking.statusLine(pea, now), 'Замачивается. Посеять сегодня');
    expect(soaking.nextActionLabel(pea), 'Посеять');

    final growing = GardenPlant(
      id: '4',
      plantId: arugula.id,
      startedAt: now.subtract(const Duration(days: 3)),
      lastWateredAt: now.subtract(const Duration(days: 1)),
      stage: GrowthStage.grow,
      stageChangedAt: now,
    );
    expect(growing.stageVerb(arugula, now), 'Растет');
    expect(
      growing.statusLine(arugula, now),
      'Растет. Собрать 11 авг. Проверить воду',
    );
    expect(growing.nextActionLabel(arugula), 'Собрать');

    final growingWatered = GardenPlant(
      id: '4b',
      plantId: arugula.id,
      startedAt: now.subtract(const Duration(days: 3)),
      lastWateredAt: now,
      stage: GrowthStage.grow,
      stageChangedAt: now,
    );
    expect(growingWatered.statusLine(arugula, now), 'Растет. Собрать 11 авг');
  });

  test('whenPhrase сегодня/завтра/дата', () {
    final now = DateTime(2026, 8, 11);
    expect(GardenPlant.whenPhrase(0, now), 'сегодня');
    expect(GardenPlant.whenPhrase(1, now), 'завтра');
    expect(GardenPlant.whenPhrase(2, now), '13 авг');
    expect(GardenPlant.whenPhrase(5, now), '16 авг');
    expect(GardenPlant.daysRangePhrase(0, 1, now), 'сегодня–завтра');
    expect(GardenPlant.daysRangePhrase(0, 2, now), 'сегодня–13 авг');
    expect(GardenPlant.daysRangePhrase(5, 8, now), '16 авг–19 авг');
  });

  test('manual advance soak → germinate → grow → harvest', () {
    final plant = plantById('pea')!;
    final start = DateTime(2026, 8, 1);
    final garden = GardenPlant(
      id: 'p',
      plantId: plant.id,
      startedAt: start,
      lastWateredAt: start,
      stage: GrowthStage.soak,
    );

    expect(garden.stageFor(plant, start), GrowthStage.soak);
    expect(garden.nextActionLabel(plant), 'Посеять');

    garden.advanceStage(plant);
    expect(garden.stage, GrowthStage.germinate);
    expect(garden.nextActionLabel(plant), 'На свет');

    garden.advanceStage(plant);
    expect(garden.stage, GrowthStage.grow);
    expect(garden.nextActionLabel(plant), 'Собрать');
    expect(garden.completesNext(plant), isTrue);

    garden.advanceStage(plant);
    expect(garden.stage, GrowthStage.harvest);
  });

  test('stage does not auto-change with time', () {
    final plant = plantById('pea')!;
    final start = DateTime(2026, 8, 1);
    final garden = GardenPlant(
      id: 'p',
      plantId: plant.id,
      startedAt: start,
      lastWateredAt: start,
      stage: GrowthStage.soak,
    );

    expect(
      garden.stageFor(plant, start.add(plant.cycleDuration)),
      GrowthStage.soak,
    );
  });

  test('notification text for today actions', () {
    final arugula = plantById('arugula_mg')!;
    final started = DateTime(2026, 8, 4, 10);
    final garden = GardenPlant(
      id: 'n1',
      plantId: arugula.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.germinate,
      stageChangedAt: started,
    );

    expect(garden.titleCompact(arugula), 'Рукола от 4авг.');

    final toLight = garden.dueActions(arugula).single;
    expect(toLight.kind, DueActionKind.toLight);
    expect(toLight.at, started.add(const Duration(hours: 48)));
    final lightDay =
        DateTime(toLight.at.year, toLight.at.month, toLight.at.day);
    expect(
      garden.notificationIfDueToday(arugula, toLight, lightDay),
      'Рукола от 4 авг Пора на свет',
    );

    final growing = GardenPlant(
      id: 'n2',
      plantId: arugula.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.grow,
      stageChangedAt: started,
    );
    final harvest = growing.dueActions(arugula).single;
    expect(harvest.kind, DueActionKind.harvest);
    expect(harvest.at, started.add(const Duration(days: 4)));
    final harvestDay =
        DateTime(harvest.at.year, harvest.at.month, harvest.at.day);
    expect(
      growing.notificationIfDueToday(arugula, harvest, harvestDay),
      'Рукола от 4 авг Собрать урожай',
    );

    expect(
      growing.notificationIfDueToday(
        arugula,
        harvest,
        harvestDay.subtract(const Duration(days: 1)),
      ),
      isNull,
    );
  });

  test('initial stage depends on soak and dark need', () {
    final pea = plantById('pea')!;
    expect(GardenPlant.initialStageFor(pea), GrowthStage.soak);

    final radish = plantById('radish')!;
    expect(GardenPlant.initialStageFor(radish), GrowthStage.germinate);

    final celery = plantById('celery')!;
    expect(GardenPlant.initialStageFor(celery), GrowthStage.grow);
  });

  test('startable stages depend on soak and dark need', () {
    final pea = plantById('pea')!;
    expect(
      pea.startableStages,
      [GrowthStage.soak, GrowthStage.germinate, GrowthStage.grow],
    );

    final radish = plantById('radish')!;
    expect(
      radish.startableStages,
      [GrowthStage.germinate, GrowthStage.grow],
    );

    final corn = plantById('corn')!;
    expect(corn.startableStages, [GrowthStage.germinate]);
  });

  test('progress weights stages by real duration', () {
    final radish = plantById('radish')!;
    // germinate 72h + grow 5d = 192h total
    expect(radish.cycleDuration.inHours, 192);

    final now = DateTime(2026, 8, 11, 12);
    final justPlanted = GardenPlant(
      id: 'r1',
      plantId: radish.id,
      startedAt: now,
      lastWateredAt: now,
      stage: GrowthStage.germinate,
      stageChangedAt: now,
    );
    expect(justPlanted.progressFor(radish, now), closeTo(0, 0.01));

    final midGerminate = GardenPlant(
      id: 'r2',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(hours: 36)),
      lastWateredAt: now.subtract(const Duration(hours: 36)),
      stage: GrowthStage.germinate,
      stageChangedAt: now.subtract(const Duration(hours: 36)),
    );
    // 36 / 192 ≈ 18.75%
    expect(midGerminate.progressFor(radish, now), closeTo(36 / 192, 0.01));

    final justOnLight = GardenPlant(
      id: 'r3',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(hours: 72)),
      lastWateredAt: now,
      stage: GrowthStage.grow,
      stageChangedAt: now,
    );
    // full germinate credited: 72 / 192 = 37.5%
    expect(justOnLight.progressFor(radish, now), closeTo(72 / 192, 0.01));

    final midGrow = GardenPlant(
      id: 'r4',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(days: 5)),
      lastWateredAt: now,
      stage: GrowthStage.grow,
      stageChangedAt: now.subtract(const Duration(days: 2, hours: 12)),
    );
    // 72 + 60 = 132 / 192 = 68.75%
    expect(midGrow.progressFor(radish, now), closeTo(132 / 192, 0.01));

    final ready = GardenPlant(
      id: 'r5',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(days: 8)),
      lastWateredAt: now,
      stage: GrowthStage.harvest,
      stageChangedAt: now,
    );
    expect(ready.progressFor(radish, now), 1.0);
  });

  test('next phase and harvest lines above status button', () {
    final radish = plantById('radish')!;
    final now = DateTime(2026, 8, 11, 12);
    final germinating = GardenPlant(
      id: 'r',
      plantId: radish.id,
      startedAt: now,
      lastWateredAt: now,
      stage: GrowthStage.germinate,
      stageChangedAt: now,
    );

    expect(
      germinating.nextPhaseLine(radish, now),
      'Рост 13 авг',
    );
    expect(germinating.harvestLine(radish, now), 'Урожай 16 авг–19 авг');

    final growing = GardenPlant(
      id: 'g',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(days: 3)),
      lastWateredAt: now,
      stage: GrowthStage.grow,
      stageChangedAt: now,
    );
    expect(
      growing.nextPhaseLine(radish, now),
      'К срезке 14 авг',
    );
    expect(growing.harvestLine(radish, now), 'Урожай 14 авг–16 авг');

    // Progress follows stageChangedAt, not startedAt / full cycle start.
    expect(growing.progressFor(radish, now), closeTo(72 / 192, 0.01));
    final midGrow = GardenPlant(
      id: 'g2',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(days: 10)),
      lastWateredAt: now,
      stage: GrowthStage.grow,
      stageChangedAt: now.subtract(const Duration(days: 2)),
    );
    // remaining from stage start 5d, elapsed 2d → remaining 3d → (8-3)/8
    expect(midGrow.progressFor(radish, now), closeTo(5 / 8, 0.01));
  });

  test('overdue germinate uses remaining time for harvest and progress', () {
    final radish = plantById('radish')!;
    final started = DateTime(2026, 8, 7, 10);
    final now = DateTime(2026, 8, 13, 12);
    final overdue = GardenPlant(
      id: 'over',
      plantId: radish.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.germinate,
      stageChangedAt: started,
    );

    // Current stage fully past → next action today; harvest = grow only.
    expect(overdue.statusLine(radish, now), 'Прорастает. На свет сегодня');
    expect(overdue.harvestLine(radish, now), 'Урожай 16 авг–18 авг');
    expect(overdue.progressFor(radish, now), closeTo(72 / 192, 0.01));
  });

  test('due actions use catalog minimum duration', () {
    final arugula = plantById('arugula_mg')!;
    expect(arugula.cycleDaysLabel, '6–9 дн.');
    expect(arugula.germinateHoursForTiming, 48); // min 2d
    expect(arugula.growDaysLow, 4);

    final started = DateTime(2026, 8, 1, 10);
    final garden = GardenPlant(
      id: 'a',
      plantId: arugula.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.germinate,
      stageChangedAt: started,
    );
    final due = garden.dueActions(arugula).single;
    expect(due.at, started.add(const Duration(hours: 48)));
    expect(
      garden.reminderLine(arugula, due, started.add(const Duration(hours: 48))),
      'Рукола от 1 авг Пора на свет · сегодня',
    );
  });
}
