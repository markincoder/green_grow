import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/data/plants_data.dart';
import 'package:green_grow/models/plant.dart';
import 'package:green_grow/widgets/common_widgets.dart';

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
    expect(ready.statusLine(arugula, now), 'Собрать');
    expect(ready.nextActionLabel(arugula), 'Собрать');

    final dated = GardenPlant(
      id: '1a',
      plantId: arugula.id,
      startedAt: DateTime(2026, 8, 4),
      lastWateredAt: DateTime(2026, 8, 6),
      stage: GrowthStage.germinate,
    );
    expect(dated.titleWithDate(arugula), 'Рукола от 4 авг');
    expect(
      addedToGardenMessage('Горох', DateTime(2026, 8, 8)),
      'Горох от 8 авг - на Моей грядке',
    );

    final fresh = GardenPlant(
      id: '2',
      plantId: arugula.id,
      startedAt: now,
      lastWateredAt: now,
      stage: GrowthStage.germinate,
    );
    expect(fresh.titleWithDate(arugula), 'Рукола от 7 авг');
    expect(fresh.stageVerb(arugula, now), 'Прорастает');
    expect(fresh.statusLine(arugula, now), 'Прорастает. Раскрыть 9 авг');
    expect(fresh.nextActionLabel(arugula), 'Раскрыть');

    final soaking = GardenPlant(
      id: '3',
      plantId: pea.id,
      startedAt: now,
      lastWateredAt: now,
      stage: GrowthStage.soak,
    );
    expect(soaking.stageVerb(pea, now), 'Замачивается');
    expect(soaking.statusLine(pea, now), 'прошло 0ч | посеять сегодня в 23ч');
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
      'Растет. Собрать 10 авг. Проверить воду',
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
    expect(growingWatered.statusLine(arugula, now), 'Растет. Собрать 10 авг');
  });

  test('whenPhrase uses lowercase сегодня/завтра and later dates', () {
    final now = DateTime(2026, 8, 11);
    expect(GardenPlant.whenPhrase(0, now), 'сегодня');
    expect(GardenPlant.whenPhrase(1, now), 'завтра');
    expect(GardenPlant.whenPhrase(2, now), '13 авг');
    expect(GardenPlant.whenPhrase(5, now), '16 авг');
    expect(GardenPlant.daysRangePhrase(0, 1, now), 'сегодня–завтра');
    expect(GardenPlant.daysRangePhrase(0, 2, now), 'сегодня–13 авг');
    expect(GardenPlant.daysRangePhrase(5, 8, now), '16 авг–19 авг');
  });

  test('soak sow time ceils start to next hour then adds catalog min', () {
    expect(
      GardenPlant.ceilToHour(DateTime(2026, 8, 17, 7, 33)),
      DateTime(2026, 8, 17, 8),
    );
    expect(
      GardenPlant.ceilToHour(DateTime(2026, 8, 17, 8)),
      DateTime(2026, 8, 17, 8),
    );
    final pea = plantById('pea')!;
    final started = DateTime(2026, 8, 17, 7, 33);
    final garden = GardenPlant(
      id: 'p',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.soak,
      stageChangedAt: started,
    );
    expect(garden.soakReminderAt(pea), DateTime(2026, 8, 17, 16));
    expect(
      garden.soakActionLabel(pea, DateTime(2026, 8, 17, 11, 33)),
      'прошло 4ч | посеять сегодня в 16ч',
    );
    expect(
      garden.statusLine(pea, DateTime(2026, 8, 17, 11, 33)),
      'прошло 4ч | посеять сегодня в 16ч',
    );
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
    expect(garden.nextActionLabel(plant), 'Раскрыть');

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
      'Рукола от 4 авг\nраскрыть',
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
    expect(harvest.at, started.add(arugula.cycleDurationMin));
    final harvestDay =
        DateTime(harvest.at.year, harvest.at.month, harvest.at.day);
    expect(
      growing.notificationIfDueToday(arugula, harvest, harvestDay),
      'Рукола от 4 авг\nсобрать',
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

  test('status highlight only when action date is today', () {
    final arugula = plantById('arugula_mg')!;
    final started = DateTime(2026, 8, 4, 10);
    final growing = GardenPlant(
      id: 'g1',
      plantId: arugula.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.grow,
      stageChangedAt: started,
    );

    final harvestDay = DateTime(
      growing.harvestAtMin(arugula).year,
      growing.harvestAtMin(arugula).month,
      growing.harvestAtMin(arugula).day,
    );
    final dayBefore = harvestDay.subtract(const Duration(days: 1));

    expect(growing.completesNext(arugula), isTrue);
    expect(growing.isStatusActionDueToday(arugula, dayBefore), isFalse);
    expect(growing.isStatusActionDueToday(arugula, harvestDay), isTrue);

    final ready = GardenPlant(
      id: 'g2',
      plantId: arugula.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.harvest,
    );
    expect(ready.isStatusActionDueToday(arugula, dayBefore), isTrue);
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
    // 5d elapsed / 8d cycle
    expect(midGrow.progressFor(radish, now), closeTo(120 / 192, 0.01));

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
      'Собрать 14 авг',
    );
    expect(growing.harvestLine(radish, now), 'Урожай 13 авг–16 авг');

    // Progress follows startedAt / full cycle, not the selected stage clock.
    expect(growing.progressFor(radish, now), closeTo(72 / 192, 0.01));
    final midGrow = GardenPlant(
      id: 'g2',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(days: 10)),
      lastWateredAt: now,
      stage: GrowthStage.grow,
      stageChangedAt: now.subtract(const Duration(days: 2)),
    );
    expect(midGrow.progressFor(radish, now), 1.0);
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

    expect(overdue.statusLine(radish, now), 'Прорастает. Раскрыть сегодня');
    // Harvest is always start + catalog cycle, even if this stage is overdue.
    expect(overdue.harvestLine(radish, now), 'Урожай сегодня–15 авг');
    expect(overdue.progressFor(radish, now), closeTo(146 / 192, 0.01));
  });

  test('harvest dates follow start date, not selected stage', () {
    final pea = plantById('pea')!;
    final now = DateTime(2026, 8, 17, 12);
    final started = DateTime(2026, 8, 10, 12);

    GardenPlant tray(GrowthStage stage) => GardenPlant(
          id: stage.name,
          plantId: pea.id,
          startedAt: started,
          lastWateredAt: started,
          stage: stage,
          stageChangedAt: now,
        );

    final soaking = tray(GrowthStage.soak);
    final growing = tray(GrowthStage.grow);
    expect(soaking.harvestAtMin(pea, now), growing.harvestAtMin(pea, now));
    expect(soaking.harvestAt(pea, now), growing.harvestAt(pea, now));
    expect(soaking.harvestAtMin(pea, now), started.add(pea.cycleDurationMin));
    expect(soaking.harvestAt(pea, now), started.add(pea.cycleDuration));
    expect(soaking.harvestLine(pea, now), growing.harvestLine(pea, now));
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
      garden.reminderLine(arugula, due),
      'Рукола от 1 авг\nраскрыть',
    );
  });
}
