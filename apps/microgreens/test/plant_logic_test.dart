import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/data/plants_data.dart';
import 'package:green_grow/models/plant.dart';
import 'package:green_grow/widgets/common_widgets.dart';

void main() {
  test('catalog has microgreens from cultivation table', () {
    expect(plantsCatalog.length, greaterThanOrEqualTo(32));
    final radish = plantById('10024')!;
    expect(plantById('radish')!.id, radish.id);
    expect(radish.needsSoak, isFalse);
    expect(radish.seedGramsMin, 6);
    expect(radish.seedGramsMax, 8);
    expect(radish.seedGramsLabel, '6–8 г');
    expect(radish.germinateHoursMax, 96);
    expect(radish.growDays, 6);
    expect(radish.images, [
      'assets/plants/redis1.jpg',
      'assets/plants/redis2.jpg',
      'assets/plants/redis3.jpg',
    ]);
    expect(radish.listAvatar, 'assets/plants/redis1.jpg');
    expect(radish.bedAvatar, 'assets/plants/redis2.jpg');
    expect(
      radish.cardPhotos,
      [
        'assets/plants/redis1.jpg',
        'assets/plants/redis2.jpg',
        'assets/plants/redis3.jpg',
      ],
    );

    final basil = plantById('10002')!;
    expect(basil.images, [
      'assets/plants/bazilik1.jpg',
      'assets/plants/bazilik2.jpg',
      'assets/plants/bazilik3.jpg',
    ]);
    expect(basil.bedAvatar, 'assets/plants/bazilik2.jpg');
    expect(
      basil.cardPhotos,
      [
        'assets/plants/bazilik1.jpg',
        'assets/plants/bazilik2.jpg',
        'assets/plants/bazilik3.jpg',
      ],
    );

    final broccoli = plantById('10004')!;
    expect(broccoli.images, ['assets/plants/brokkoli1.jpg']);
    expect(broccoli.bedAvatar, Plant.defaultBedPhoto);
    expect(
      broccoli.cardPhotos,
      ['assets/plants/brokkoli1.jpg'],
    );

    final pea = plantById('10005')!;
    expect(pea.needsSoak, isTrue);
    expect(pea.soakHoursMin, 8);
    expect(pea.pressKind, PressKind.weight);
    expect(pea.pressKgMin, 1.5);
    expect(pea.pressKgMax, 2);
    expect(pea.seedGrams, 35);

    final sunflower = plantById('10023')!;
    expect(sunflower.needsPress, isTrue);
    expect(sunflower.pressKgMin, 1.5);
    expect(sunflower.pressLabel, '1.5–2 кг');

    final amaranth = plantById('10001')!;
    expect(amaranth.hasGerminateStage, isTrue);
    expect(amaranth.pressKind, PressKind.weight);
    expect(amaranth.pressLabel, '0.5–1 кг');
    expect(amaranth.hasGrowStage, isTrue);
    expect(GardenPlant.initialStageFor(amaranth), GrowthStage.germinate);

    final corn = plantById('10015')!;
    expect(corn.needsSoak, isTrue);
    expect(corn.hasGrowStage, isTrue);
    expect(corn.feature, contains('темноте'));

    expect(plantById('10007')!.name, 'Дайкон');
    expect(plantById('10028')!.name, 'Свекла');
    expect(plantById('10032')!.name, 'Салат');
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
    expect(fresh.statusLine(arugula, now), 'Прорастает. Раскрыть 10 авг');
    expect(fresh.nextActionLabel(arugula), 'Раскрыть');

    final soaking = GardenPlant(
      id: '3',
      plantId: pea.id,
      startedAt: now,
      lastWateredAt: now,
      stage: GrowthStage.soak,
    );
    expect(soaking.stageVerb(pea, now), 'Замачивается');
    expect(soaking.statusLine(pea, now), 'Замачивается. посеять сегодня с 23:00');
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
      'Растет. Собрать 12 авг. Проверить воду',
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
    expect(growingWatered.statusLine(arugula, now), 'Растет. Собрать 12 авг');
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
      'Прошло 4ч - посеять сегодня с 16:00',
    );
    expect(
      garden.statusLine(pea, DateTime(2026, 8, 17, 11, 33)),
      'Замачивается. Прошло 4ч - посеять сегодня с 16:00',
    );
    expect(
      garden.soakActionLabel(pea, DateTime(2026, 8, 17, 16, 1)),
      'посеять',
    );
    expect(
      garden.statusLine(pea, DateTime(2026, 8, 17, 16, 1)),
      'Замачивается. Посеять',
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
    expect(toLight.at, started.add(const Duration(hours: 72)));
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
    expect(harvest.at, started.add(Duration(days: arugula.growDaysLow)));
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

    // New catalog: every culture has a dark germinate stage.
    expect(
      plantsCatalog.every((p) => p.hasGerminateStage),
      isTrue,
    );
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
    expect(
      corn.startableStages,
      [GrowthStage.soak, GrowthStage.germinate, GrowthStage.grow],
    );
  });

  test('progress weights stages by real duration', () {
    final radish = plantById('10024')!;
    // germinate 96h + grow 6d = 240h total
    expect(radish.cycleDuration.inHours, 240);

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
    expect(midGerminate.progressFor(radish, now), closeTo(36 / 240, 0.01));

    final justOnLight = GardenPlant(
      id: 'r3',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(hours: 72)),
      lastWateredAt: now,
      stage: GrowthStage.grow,
      stageChangedAt: now,
    );
    expect(justOnLight.progressFor(radish, now), closeTo(72 / 240, 0.01));

    final midGrow = GardenPlant(
      id: 'r4',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(days: 5)),
      lastWateredAt: now,
      stage: GrowthStage.grow,
      stageChangedAt: now.subtract(const Duration(days: 2, hours: 12)),
    );
    expect(midGrow.progressFor(radish, now), closeTo(120 / 240, 0.01));

    final ready = GardenPlant(
      id: 'r5',
      plantId: radish.id,
      startedAt: now.subtract(const Duration(days: 9)),
      lastWateredAt: now,
      stage: GrowthStage.harvest,
      stageChangedAt: now,
    );
    expect(ready.progressFor(radish, now), 1.0);
  });

  test('next phase and harvest lines above status button', () {
    final radish = plantById('10024')!;
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
      'Рост 14 авг',
    );
    expect(germinating.harvestLine(radish, now), 'Урожай 19 авг–21 авг');

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
      'Собрать 16 авг',
    );
    expect(growing.harvestLine(radish, now), 'Урожай 16 авг–17 авг');

    // Progress follows startedAt / full cycle, not the selected stage clock.
    expect(growing.progressFor(radish, now), closeTo(72 / 240, 0.01));
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
    final radish = plantById('10024')!;
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
    expect(overdue.harvestLine(radish, now), 'Урожай 15 авг–17 авг');
    expect(overdue.progressFor(radish, now), closeTo(146 / 240, 0.01));
  });

  test('harvest dates use remaining stage mins after each advance', () {
    final pea = plantById('pea')!;
    final started = DateTime(2026, 8, 10, 12);

    final soaking = GardenPlant(
      id: 'soak',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.soak,
      stageChangedAt: started,
    );
    expect(soaking.harvestAtMin(pea), started.add(pea.cycleDurationMin));
    expect(soaking.harvestAt(pea), started.add(pea.cycleDuration));

    final onTime = GardenPlant(
      id: 'germ-on-time',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.germinate,
      stageChangedAt: started.add(Duration(hours: pea.soakHoursForTiming)),
    );
    expect(onTime.harvestAtMin(pea), soaking.harvestAtMin(pea));

    final delayedSow = DateTime(2026, 8, 17, 12);
    final growing = GardenPlant(
      id: 'grow',
      plantId: pea.id,
      startedAt: started,
      lastWateredAt: started,
      stage: GrowthStage.grow,
      stageChangedAt: delayedSow,
    );
    expect(
      growing.harvestAtMin(pea),
      delayedSow.add(Duration(hours: pea.stageDurationHoursMin(GrowthStage.grow))),
    );
    expect(
      growing.harvestAt(pea),
      delayedSow.add(Duration(hours: pea.stageDurationHours(GrowthStage.grow))),
    );
    expect(growing.harvestAtMin(pea).isAfter(soaking.harvestAtMin(pea)), isTrue);
    expect(growing.harvestLine(pea, delayedSow), isNot(soaking.harvestLine(pea, delayedSow)));
  });

  test('due actions use catalog minimum duration', () {
    final arugula = plantById('arugula_mg')!;
    expect(arugula.cycleDaysLabel, '8–10 дн.');
    expect(arugula.germinateHoursForTiming, 72); // min 3d
    expect(arugula.growDaysLow, 5);

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
    expect(due.at, started.add(const Duration(hours: 72)));
    expect(
      garden.reminderLine(arugula, due),
      'Рукола от 1 авг\nраскрыть',
    );
  });
}
