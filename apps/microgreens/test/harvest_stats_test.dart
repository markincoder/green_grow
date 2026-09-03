import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/services/harvest_stats.dart';
import 'package:green_grow/services/tray_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

TrayHistoryRecord _record({
  required String id,
  required String plantId,
  required String name,
  required int trays,
  required List<TrayHistoryEvent> events,
}) {
  return TrayHistoryRecord(
    gardenId: id,
    plantId: plantId,
    displayName: name,
    startedAt: DateTime(2026, 1, 1),
    trayCount: trays,
    events: events,
  );
}

TrayHistoryEvent _harvest(DateTime at) => TrayHistoryEvent(
      at: at,
      action: 'собрать',
    );

void main() {
  const names = {
    '10024': 'Редис',
    '10005': 'Горох',
    '10027': 'Рукола',
    '10004': 'Брокколи',
    '10001': 'Амарант',
    'pea': 'Горох',
  };

  String nameOf(String id, String fallback) => names[id] ?? fallback;
  String canonical(String id) => id == 'pea' ? '10005' : id;

  test('sums trays of the same culture and sorts by count', () {
    final rows = aggregateHarvestStats(
      records: [
        _record(
          id: 'a',
          plantId: '10024',
          name: 'Редис Санго',
          trays: 3,
          events: [_harvest(DateTime(2026, 9, 1))],
        ),
        _record(
          id: 'b',
          plantId: '10024',
          name: 'Редис',
          trays: 5,
          events: [_harvest(DateTime(2026, 9, 2))],
        ),
        _record(
          id: 'c',
          plantId: '10005',
          name: 'Горох',
          trays: 5,
          events: [_harvest(DateTime(2026, 9, 1))],
        ),
        _record(
          id: 'd',
          plantId: '10027',
          name: 'Рукола',
          trays: 4,
          events: [_harvest(DateTime(2026, 8, 20))],
        ),
        _record(
          id: 'e',
          plantId: '10004',
          name: 'Брокколи',
          trays: 2,
          events: [_harvest(DateTime(2026, 9, 1))],
        ),
        _record(
          id: 'f',
          plantId: '10001',
          name: 'Амарант',
          trays: 1,
          events: [_harvest(DateTime(2026, 9, 1))],
        ),
      ],
      range: const HarvestStatsRange(),
      nameOf: nameOf,
      canonicalId: canonical,
    );

    expect(rows.map((r) => '${r.name} ${r.trayCount}').toList(), [
      'Редис 8',
      'Горох 5',
      'Рукола 4',
      'Брокколи 2',
      'Амарант 1',
    ]);
    expect(harvestStatsTotal(rows), 20);
    expect(harvestStatsTotalLabel(20), 'Всего 20 лотков');
    expect(harvestStatsBarFraction(8, 8), 1);
    expect(harvestStatsBarFraction(4, 8), 0.5);
    expect(harvestStatsBarFraction(1, 8), 0.125);
  });

  test('aliases merge into one culture and delete is ignored', () {
    final rows = aggregateHarvestStats(
      records: [
        _record(
          id: 'old',
          plantId: 'pea',
          name: 'Горох тест',
          trays: 2,
          events: [_harvest(DateTime(2026, 8, 1))],
        ),
        _record(
          id: 'new',
          plantId: '10005',
          name: 'Горох',
          trays: 3,
          events: [_harvest(DateTime(2026, 9, 1))],
        ),
        _record(
          id: 'gone',
          plantId: '10024',
          name: 'Редис',
          trays: 4,
          events: [
            TrayHistoryEvent(at: DateTime(2026, 9, 1), action: 'удалить'),
          ],
        ),
      ],
      range: const HarvestStatsRange(),
      nameOf: nameOf,
      canonicalId: canonical,
    );

    expect(rows, hasLength(1));
    expect(rows.single.name, 'Горох');
    expect(rows.single.trayCount, 5);
  });

  test('period filters harvests by date', () {
    final records = [
      _record(
        id: 'fresh',
        plantId: '10024',
        name: 'Редис',
        trays: 3,
        events: [_harvest(DateTime(2026, 9, 1, 10))],
      ),
      _record(
        id: 'summer',
        plantId: '10005',
        name: 'Горох',
        trays: 2,
        events: [_harvest(DateTime(2026, 7, 15))],
      ),
      _record(
        id: 'old',
        plantId: '10027',
        name: 'Рукола',
        trays: 4,
        events: [_harvest(DateTime(2025, 10, 1))],
      ),
    ];
    final now = DateTime(2026, 9, 2, 12);

    List<String> names(HarvestStatsPeriod period, {HarvestStatsRange? custom}) {
      final range = custom ??
          harvestStatsRange(period: period, now: now);
      return aggregateHarvestStats(
        records: records,
        range: range,
        nameOf: nameOf,
        canonicalId: canonical,
      ).map((r) => r.name).toList();
    }

    expect(
      harvestStatsRange(period: HarvestStatsPeriod.week, now: now).from,
      DateTime(2026, 8, 27),
    );
    expect(
      harvestStatsRange(period: HarvestStatsPeriod.month, now: now).from,
      DateTime(2026, 8, 4),
    );

    expect(names(HarvestStatsPeriod.week), ['Редис']);
    expect(names(HarvestStatsPeriod.month), ['Редис']);
    expect(names(HarvestStatsPeriod.all), ['Рукола', 'Редис', 'Горох']);
    expect(
      names(
        HarvestStatsPeriod.custom,
        custom: HarvestStatsRange(
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 9, 2),
        ),
      ),
      ['Редис', 'Горох'],
    );
    expect(firstHarvestDay(records), DateTime(2025, 10, 1));
    expect(formatHarvestFilterDate(DateTime(2026, 9, 1)), '01.09.2026');
  });

  test('tray word agrees with the count', () {
    expect(harvestStatsTraysWord(1), 'лоток');
    expect(harvestStatsTraysWord(2), 'лотка');
    expect(harvestStatsTraysWord(4), 'лотка');
    expect(harvestStatsTraysWord(5), 'лотков');
    expect(harvestStatsTraysWord(14), 'лотков');
    expect(harvestStatsTraysWord(21), 'лоток');
    expect(harvestStatsTotalLabel(14), 'Всего 14 лотков');
  });

  test('bar fraction is relative to the leader', () {
    expect(harvestStatsBarFraction(0, 8), 0);
    expect(harvestStatsBarFraction(24, 24), 1);
    expect(harvestStatsBarFraction(12, 24), 0.5);
    expect(harvestStatsBarFraction(1, 24), 1 / 24);
  });

  test('bar colors differ for neighboring cultures', () {
    expect(harvestStatsBarColor(0), isNot(harvestStatsBarColor(1)));
    expect(harvestStatsBarColor(1), isNot(harvestStatsBarColor(2)));
    expect(harvestStatsBarColor(12), harvestStatsBarColor(0));
  });

  test('prefs persist period and custom dates', () async {
    SharedPreferences.setMockInitialValues({});
    HarvestStatsPrefs.prefsOverride = await SharedPreferences.getInstance();

    expect(await HarvestStatsPrefs.loadPeriod(), HarvestStatsPeriod.all);

    await HarvestStatsPrefs.savePeriod(HarvestStatsPeriod.week);
    expect(await HarvestStatsPrefs.loadPeriod(), HarvestStatsPeriod.custom);

    await HarvestStatsPrefs.savePeriod(HarvestStatsPeriod.custom);
    await HarvestStatsPrefs.saveCustomRange(
      DateTime(2026, 8, 1),
      DateTime(2026, 9, 2),
    );

    expect(await HarvestStatsPrefs.loadPeriod(), HarvestStatsPeriod.custom);
    final range = await HarvestStatsPrefs.loadCustomRange();
    expect(range.$1, DateTime(2026, 8, 1));
    expect(range.$2, DateTime(2026, 9, 2));

    HarvestStatsPrefs.prefsOverride = null;
  });
}
