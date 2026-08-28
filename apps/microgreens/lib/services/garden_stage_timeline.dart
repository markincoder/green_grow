import 'package:flutter/foundation.dart';

import '../models/plant.dart';
import 'planting_log_service.dart';

class PlantingLogEntry {
  const PlantingLogEntry({
    required this.at,
    required this.cycleName,
    required this.action,
    required this.stageOrComment,
  });

  final DateTime at;
  final String cycleName;
  final String action;
  final String stageOrComment;
}

class GardenStagePeriod {
  const GardenStagePeriod({
    required this.stage,
    required this.start,
    this.end,
  });

  final GrowthStage stage;
  final DateTime start;
  final DateTime? end;

  String durationLabel(DateTime now) {
    final endAt = end ?? now;
    final minutes = endAt.difference(start).inMinutes;
    if (minutes < 60) return '${minutes.clamp(1, 9999)} мин';
    final hours = (minutes / 60).round();
    final sameDay = _sameCalendarDay(start, endAt);
    if (sameDay && hours < 24) return '$hoursч';
    final days = (minutes / (60 * 24)).round().clamp(1, 9999);
    return '$days дн';
  }

  String rangeLabel(DateTime now) {
    final endAt = end ?? now;
    final endIsToday = end == null && _sameCalendarDay(endAt, now);
    final startDay = _dayLabel(start);
    final endDay = endIsToday ? 'сегодня' : _dayLabel(endAt);

    if (_sameCalendarDay(start, endAt)) {
      return '$startDay ${_timeLabel(start)}-$startDay ${_timeLabel(endAt)}';
    }
    if (endIsToday) return '$startDay-$endDay';
    return '$startDay-$endDay';
  }

  static String _dayLabel(DateTime d) =>
      formatStartDate(d).replaceAll('.', '');

  static String _timeLabel(DateTime d) =>
      '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

@visibleForTesting
GrowthStage? parseLogStageField(String field) {
  final s = field.trim().toLowerCase();
  if (s.isEmpty) return null;
  return switch (s) {
    'замачивание' => GrowthStage.soak,
    'проращивание' => GrowthStage.germinate,
    'рост' => GrowthStage.grow,
    'собрать' => GrowthStage.harvest,
    _ => null,
  };
}

PlantingLogEntry? parsePlantingLogLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(';');
  if (parts.length < 3) return null;
  final stamp = parts[0].trim();
  final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2})$').firstMatch(stamp);
  if (match == null) return null;
  final at = DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
  );
  return PlantingLogEntry(
    at: at,
    cycleName: parts[1].trim(),
    action: parts[2].trim().toLowerCase(),
    stageOrComment: parts.length > 3 ? parts[3].trim() : '',
  );
}

bool matchesGardenCycle(PlantingLogEntry entry, GardenPlant garden) =>
    entry.cycleName.endsWith(garden.cycleDateSuffix());

@visibleForTesting
List<GardenStagePeriod> buildGardenStagePeriods({
  required List<PlantingLogEntry> entries,
  required GardenPlant garden,
  required Plant plant,
  required DateTime now,
}) {
  final allowed = garden
      .processStages(plant)
      .where((s) => s != GrowthStage.harvest)
      .toSet();
  if (allowed.isEmpty) return const [];

  final relevant = entries
      .where((e) => matchesGardenCycle(e, garden))
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));

  if (relevant.isEmpty) {
    if (!allowed.contains(garden.stage)) return const [];
    return [
      GardenStagePeriod(
        stage: garden.stage,
        start: garden.stageChangedAt,
      ),
    ];
  }

  final periods = <GardenStagePeriod>[];
  GrowthStage? openStage;
  DateTime? openStart;

  void closeAt(DateTime end) {
    final stage = openStage;
    final start = openStart;
    if (stage == null || start == null) return;
    if (allowed.contains(stage)) {
      periods.add(GardenStagePeriod(
        stage: stage,
        start: start,
        end: end,
      ));
    }
    openStage = null;
    openStart = null;
  }

  for (final entry in relevant) {
    final stage = parseLogStageField(entry.stageOrComment);
    if (entry.action == 'начать') {
      if (stage != null) {
        closeAt(entry.at);
        openStage = stage;
        openStart = entry.at;
      }
      continue;
    }
    if (entry.action == 'собрать' || entry.action == 'удалить') {
      closeAt(entry.at);
      continue;
    }
    if (stage != null && stage != openStage) {
      closeAt(entry.at);
      openStage = stage;
      openStart = entry.at;
    }
  }

  final open = openStage;
  final start = openStart;
  if (open != null && start != null && allowed.contains(open)) {
    periods.add(GardenStagePeriod(
      stage: open,
      start: start,
    ));
  }

  return periods;
}

Future<List<GardenStagePeriod>> loadGardenStagePeriods({
  required GardenPlant garden,
  required Plant plant,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final file = await PlantingLogService.instance.logFile();
  if (file == null || !await file.exists()) {
    return buildGardenStagePeriods(
      entries: const [],
      garden: garden,
      plant: plant,
      now: at,
    );
  }
  try {
    final text = await file.readAsString();
    final entries = text
        .split('\n')
        .map(parsePlantingLogLine)
        .whereType<PlantingLogEntry>()
        .toList();
    return buildGardenStagePeriods(
      entries: entries,
      garden: garden,
      plant: plant,
      now: at,
    );
  } catch (_) {
    return buildGardenStagePeriods(
      entries: const [],
      garden: garden,
      plant: plant,
      now: at,
    );
  }
}

String gardenStageTitle(GrowthStage stage) => switch (stage) {
      GrowthStage.soak => 'Замачивание',
      GrowthStage.germinate => 'Проращивание',
      GrowthStage.grow => 'Рост',
      GrowthStage.harvest => 'Собрать',
    };
