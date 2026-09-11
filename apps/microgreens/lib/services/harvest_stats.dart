import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tray_history_store.dart';

/// Window for the «Мой урожай» table.
enum HarvestStatsPeriod { all, week, month, custom }

String harvestStatsPeriodLabel(HarvestStatsPeriod period) => switch (period) {
      HarvestStatsPeriod.all => 'За все время',
      HarvestStatsPeriod.week => 'За неделю',
      HarvestStatsPeriod.month => 'За месяц',
      HarvestStatsPeriod.custom => 'За период...',
    };

class HarvestStatsRange {
  const HarvestStatsRange({this.from, this.to});

  final DateTime? from;
  final DateTime? to;
}

DateTime harvestStatsDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Inclusive calendar range for [period]. [all] has no bounds.
HarvestStatsRange harvestStatsRange({
  required HarvestStatsPeriod period,
  required DateTime now,
  DateTime? customFrom,
  DateTime? customTo,
}) {
  final today = harvestStatsDay(now);
  return switch (period) {
    HarvestStatsPeriod.all => const HarvestStatsRange(),
    HarvestStatsPeriod.week => HarvestStatsRange(
        from: today.subtract(const Duration(days: 6)),
        to: today,
      ),
    HarvestStatsPeriod.month => HarvestStatsRange(
        from: today.subtract(const Duration(days: 29)),
        to: today,
      ),
    HarvestStatsPeriod.custom => HarvestStatsRange(
        from: customFrom == null ? null : harvestStatsDay(customFrom),
        to: harvestStatsDay(customTo ?? today),
      ),
  };
}

bool harvestStatsInRange(DateTime at, HarvestStatsRange range) {
  final day = harvestStatsDay(at);
  final from = range.from;
  final to = range.to;
  if (from != null && day.isBefore(harvestStatsDay(from))) return false;
  if (to != null && day.isAfter(harvestStatsDay(to))) return false;
  return true;
}

DateTime? firstHarvestDay(Iterable<TrayHistoryRecord> records) {
  DateTime? first;
  for (final record in records) {
    for (final event in record.events) {
      if (event.action != 'собрать') continue;
      final day = harvestStatsDay(event.at);
      if (first == null || day.isBefore(first)) first = day;
    }
  }
  return first;
}

String formatHarvestFilterDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day.$month.${d.year}';
}

class HarvestStatRow {
  const HarvestStatRow({
    required this.plantId,
    required this.name,
    required this.trayCount,
  });

  final String plantId;
  final String name;
  final int trayCount;
}

/// One row per culture: tray counts from «собрать» inside [range].
List<HarvestStatRow> aggregateHarvestStats({
  required Iterable<TrayHistoryRecord> records,
  required HarvestStatsRange range,
  required String Function(String plantId, String fallbackName) nameOf,
  String Function(String plantId)? canonicalId,
}) {
  final counts = <String, int>{};
  final names = <String, String>{};

  for (final record in records) {
    final id = canonicalId?.call(record.plantId) ?? record.plantId;
    var harvested = 0;
    for (final event in record.events) {
      if (event.action != 'собрать') continue;
      if (!harvestStatsInRange(event.at, range)) continue;
      harvested += record.trayCount;
    }
    if (harvested <= 0) continue;
    counts[id] = (counts[id] ?? 0) + harvested;
    names.putIfAbsent(id, () => nameOf(id, record.displayName));
  }

  final rows = [
    for (final entry in counts.entries)
      HarvestStatRow(
        plantId: entry.key,
        name: names[entry.key] ?? entry.key,
        trayCount: entry.value,
      ),
  ];
  rows.sort((a, b) {
    final byCount = b.trayCount.compareTo(a.trayCount);
    if (byCount != 0) return byCount;
    return _nameKey(a.name).compareTo(_nameKey(b.name));
  });
  return rows;
}

int harvestStatsTotal(Iterable<HarvestStatRow> rows) =>
    rows.fold<int>(0, (sum, row) => sum + row.trayCount);

String harvestStatsTotalLabel(int total) =>
    'Все культуры: $total ${harvestStatsTraysWord(total)}';

String harvestStatsTraysWord(int count) {
  final n = count.abs() % 100;
  final d = n % 10;
  if (n > 10 && n < 20) return 'лотков';
  if (d > 1 && d < 5) return 'лотка';
  if (d == 1) return 'лоток';
  return 'лотков';
}

/// Column height/width 0…1 relative to the culture with the most trays.
double harvestStatsBarFraction(int count, int maxCount) {
  if (count <= 0 || maxCount <= 0) return 0;
  return (count / maxCount).clamp(0.0, 1.0);
}

/// Distinct bar colors; wraps if there are more cultures than the palette.
Color harvestStatsBarColor(int index) {
  const palette = <int>[
    0xFF2D6A4F, // leaf
    0xFF3D7EA6, // water
    0xFFE9B44C, // sun
    0xFF52B788, // sprout
    0xFF6B4F3A, // soil
    0xFF7B2D8E, // purple
    0xFFD96C4F, // coral
    0xFF40916C, // meadow
    0xFF2A6F97, // steel
    0xFFC44536, // brick
    0xFF5C4D7A, // violet
    0xFF8AAA79, // sage
  ];
  return Color(palette[index % palette.length]);
}

String _nameKey(String name) => name.toLowerCase().replaceAll('ё', 'е');

/// Saved filter chip + custom from/to.
class HarvestStatsPrefs {
  HarvestStatsPrefs._();

  static SharedPreferences? prefsOverride;

  static const _periodKey = 'harvest_stats_period_v1';
  static const _fromKey = 'harvest_stats_from_v1';
  static const _toKey = 'harvest_stats_to_v1';

  static Future<SharedPreferences> _prefs() async =>
      prefsOverride ?? SharedPreferences.getInstance();

  static Future<HarvestStatsPeriod> loadPeriod() async {
    final raw = (await _prefs()).getString(_periodKey);
    for (final period in HarvestStatsPeriod.values) {
      if (period.name != raw) continue;
      if (period == HarvestStatsPeriod.week ||
          period == HarvestStatsPeriod.month) {
        return HarvestStatsPeriod.custom;
      }
      return period;
    }
    return HarvestStatsPeriod.all;
  }

  static Future<void> savePeriod(HarvestStatsPeriod period) async {
    await (await _prefs()).setString(_periodKey, period.name);
  }

  static Future<(DateTime?, DateTime?)> loadCustomRange() async {
    final prefs = await _prefs();
    return (
      _parseDay(prefs.getString(_fromKey)),
      _parseDay(prefs.getString(_toKey)),
    );
  }

  static Future<void> saveCustomRange(DateTime from, DateTime to) async {
    final prefs = await _prefs();
    await prefs.setString(_fromKey, harvestStatsDay(from).toIso8601String());
    await prefs.setString(_toKey, harvestStatsDay(to).toIso8601String());
  }

  static DateTime? _parseDay(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return harvestStatsDay(parsed);
  }
}
