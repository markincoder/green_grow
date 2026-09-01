import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/plant.dart';
import 'planting_log_service.dart';

/// One user action on a tray (bound to [TrayHistoryRecord.gardenId]).
class TrayHistoryEvent {
  const TrayHistoryEvent({
    required this.at,
    required this.action,
    this.stage = '',
  });

  final DateTime at;
  final String action;
  final String stage;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'action': action,
        'stage': stage,
      };

  factory TrayHistoryEvent.fromJson(Map<String, dynamic> json) =>
      TrayHistoryEvent(
        at: DateTime.parse(json['at'] as String),
        action: (json['action'] as String? ?? '').toLowerCase(),
        stage: json['stage'] as String? ?? '',
      );
}

/// Local history + analytics snapshot for one tray id.
class TrayHistoryRecord {
  TrayHistoryRecord({
    required this.gardenId,
    required this.plantId,
    required this.displayName,
    required this.startedAt,
    required this.trayCount,
    List<TrayHistoryEvent>? events,
  }) : events = events ?? [];

  final String gardenId;
  final String plantId;
  String displayName;
  final DateTime startedAt;
  int trayCount;
  final List<TrayHistoryEvent> events;

  Map<String, dynamic> toJson() => {
        'gardenId': gardenId,
        'plantId': plantId,
        'displayName': displayName,
        'startedAt': startedAt.toIso8601String(),
        'trayCount': trayCount,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory TrayHistoryRecord.fromJson(Map<String, dynamic> json) =>
      TrayHistoryRecord(
        gardenId: json['gardenId'] as String,
        plantId: json['plantId'] as String,
        displayName: json['displayName'] as String? ?? '',
        startedAt: DateTime.parse(json['startedAt'] as String),
        trayCount: (json['trayCount'] as num?)?.toInt() ?? 1,
        events: (json['events'] as List<dynamic>? ?? const [])
            .map((e) => TrayHistoryEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

String historyActionLabel(String action) {
  final a = action.trim().toLowerCase();
  if (a == 'начать') return 'старт';
  return a;
}

String formatHistoryStamp(DateTime at) {
  final d = at.day.toString().padLeft(2, '0');
  final m = at.month.toString().padLeft(2, '0');
  final h = at.hour.toString().padLeft(2, '0');
  final min = at.minute.toString().padLeft(2, '0');
  return '$d.$m.${at.year} $h:$min';
}

/// `20.08.2026 18:20 старт → замачивание`
String trayHistoryLineLabel(TrayHistoryEvent event) {
  final action = historyActionLabel(event.action);
  final stage = event.stage.trim();
  final stamp = formatHistoryStamp(event.at);
  if (stage.isEmpty || action == 'собрать' || action == 'удалить') {
    return '$stamp $action';
  }
  return '$stamp $action → $stage';
}

/// Per-tray history in SharedPreferences. [лог_посадок.txt] stays informational.
class TrayHistoryStore {
  TrayHistoryStore._();
  static final TrayHistoryStore instance = TrayHistoryStore._();

  static const _storageKey = 'tray_history_v1';

  /// Optional override for tests.
  SharedPreferences? prefsOverride;

  Future<SharedPreferences> _prefs() async =>
      prefsOverride ?? SharedPreferences.getInstance();

  Future<Map<String, TrayHistoryRecord>> _loadAll() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (key, value) => MapEntry(
          key,
          TrayHistoryRecord.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAll(Map<String, TrayHistoryRecord> all) async {
    final prefs = await _prefs();
    await prefs.setString(
      _storageKey,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<TrayHistoryRecord?> recordFor(String gardenId) async {
    final all = await _loadAll();
    return all[gardenId];
  }

  Future<List<TrayHistoryEvent>> eventsFor(String gardenId) async {
    final record = await recordFor(gardenId);
    if (record == null) return const [];
    return List.unmodifiable(record.events);
  }

  Future<void> _append({
    required GardenPlant garden,
    required Plant plant,
    required String action,
    required String stage,
    DateTime? at,
  }) async {
    final all = await _loadAll();
    final existing = all[garden.id];
    final record = existing ??
        TrayHistoryRecord(
          gardenId: garden.id,
          plantId: garden.plantId,
          displayName: garden.displayName(plant),
          startedAt: garden.startedAt,
          trayCount: garden.trayCount,
        );
    record.displayName = garden.displayName(plant);
    record.trayCount = garden.trayCount;
    record.events.add(
      TrayHistoryEvent(
        at: at ?? DateTime.now(),
        action: action.toLowerCase(),
        stage: stage,
      ),
    );
    all[garden.id] = record;
    await _saveAll(all);
  }

  Future<void> recordStart({
    required GardenPlant garden,
    required Plant plant,
    required GrowthStage stage,
    DateTime? at,
  }) async {
    await _append(
      garden: garden,
      plant: plant,
      action: 'старт',
      stage: PlantingLogService.stageField(stage),
      at: at,
    );
  }

  Future<void> recordAdvance({
    required GardenPlant garden,
    required Plant plant,
    required String action,
    required GrowthStage stage,
    DateTime? at,
  }) async {
    await _append(
      garden: garden,
      plant: plant,
      action: action,
      stage: PlantingLogService.stageField(stage),
      at: at,
    );
  }

  Future<void> recordClose({
    required GardenPlant garden,
    required Plant plant,
    required String action,
    DateTime? at,
  }) async {
    await _append(
      garden: garden,
      plant: plant,
      action: action,
      stage: '',
      at: at,
    );
  }

  /// Drop the last history event (undo of посеять / раскрыть / собрать / удалить).
  Future<void> undoLastEvent(String gardenId) async {
    final all = await _loadAll();
    final record = all[gardenId];
    if (record == null || record.events.isEmpty) return;
    record.events.removeLast();
    await _saveAll(all);
  }

  /// Update name/count snapshot without adding a history event.
  Future<void> syncMetadata({
    required GardenPlant garden,
    required Plant plant,
  }) async {
    final all = await _loadAll();
    final record = all[garden.id];
    if (record == null) return;
    record.displayName = garden.displayName(plant);
    record.trayCount = garden.trayCount;
    await _saveAll(all);
  }
}
