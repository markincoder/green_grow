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
    expect(ready.statusLine(arugula, now), 'К срезке. Можно собирать');
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
    expect(fresh.statusLine(arugula, now), 'Прорастает. Дальше — на свет');
    expect(fresh.nextActionLabel(arugula), 'На свет');

    final soaking = GardenPlant(
      id: '3',
      plantId: pea.id,
      startedAt: now,
      lastWateredAt: now,
      stage: GrowthStage.soak,
    );
    expect(soaking.stageVerb(pea, now), 'Замачивается');
    expect(soaking.statusLine(pea, now), 'Замачивается. Дальше — посадка');
    expect(soaking.nextActionLabel(pea), 'Посадить');

    final growing = GardenPlant(
      id: '4',
      plantId: arugula.id,
      startedAt: now.subtract(const Duration(days: 3)),
      lastWateredAt: now.subtract(const Duration(days: 1)),
      stage: GrowthStage.grow,
    );
    expect(growing.stageVerb(arugula, now), 'Растет');
    expect(growing.statusLine(arugula, now), 'Растет. Проверить воду');
    expect(growing.nextActionLabel(arugula), 'Собрать');
  });

  test('whenPhrase сегодня/завтра/через N дней', () {
    expect(GardenPlant.whenPhrase(0), 'сегодня');
    expect(GardenPlant.whenPhrase(1), 'завтра');
    expect(GardenPlant.whenPhrase(2), 'через 2 дня');
    expect(GardenPlant.whenPhrase(5), 'через 5 дней');
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
    expect(garden.nextActionLabel(plant), 'Посадить');

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
    final lightDay =
        DateTime(toLight.at.year, toLight.at.month, toLight.at.day);
    expect(
      garden.notificationIfDueToday(arugula, toLight, lightDay),
      'Рукола от 4авг. Пора на свет.',
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
    final harvestDay =
        DateTime(harvest.at.year, harvest.at.month, harvest.at.day);
    expect(
      growing.notificationIfDueToday(arugula, harvest, harvestDay),
      'Рукола от 4авг. Время собирать урожай!',
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
}
