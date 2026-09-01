import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';
import '../services/planting_log_service.dart';
import '../services/tray_history_store.dart';

class GardenStore extends ChangeNotifier {
  static const _storageKey = 'garden_plants_v4';

  final List<GardenPlant> _plants = [];
  bool loaded = false;

  List<GardenPlant> get plants => List.unmodifiable(_plants);

  List<GardenPlant> needingWater(DateTime now) {
    return _plants.where((g) {
      final plant = plantById(g.plantId);
      return plant != null && g.needsWater(plant, now);
    }).toList();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey) ??
        prefs.getString('garden_plants_v3');
    _plants.clear();
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List<dynamic>;
      final now = DateTime.now();
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final garden = GardenPlant.fromJson(map);
        if (map['stage'] == null) {
          final plant = plantById(garden.plantId);
          if (plant != null) {
            garden.stage =
                GardenPlant.legacyStageFor(plant, garden.startedAt, now);
          }
        }
        _plants.add(garden);
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_plants.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  Future<void> startPlant({
    required String plantId,
    DateTime? startedAt,
    GrowthStage? stage,
    String? customName,
    int? seedGrams,
    int trayCount = 1,
  }) async {
    final now = DateTime.now();
    final start = startedAt ?? now;
    final plant = plantById(plantId);
    final resolvedStage = stage ??
        (plant != null
            ? GardenPlant.initialStageFor(plant)
            : GrowthStage.germinate);
    final name = customName?.trim();

    final garden = GardenPlant(
      id: 'gp-${now.microsecondsSinceEpoch}',
      plantId: plantId,
      startedAt: start,
      // Not marked watered today — status / filter show «Проверить воду» on grow.
      lastWateredAt: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1)),
      stage: resolvedStage,
      stageChangedAt: start,
      createdAt: now,
      customName: (name != null && name.isNotEmpty) ? name : null,
      seedGrams: seedGrams ?? plant?.seedGrams,
      trayCount: trayCount,
    );
    _plants.insert(0, garden);
    if (plant != null) {
      await TrayHistoryStore.instance.recordStart(
        garden: garden,
        plant: plant,
        stage: resolvedStage,
      );
      await PlantingLogService.instance.append(
        cycleName: garden.analyticsTitle(plant),
        action: 'старт',
        stageOrComment: PlantingLogService.stageField(resolvedStage),
      );
    }
    await _persist();
    notifyListeners();
  }

  Future<void> waterPlant(String id) async {
    final index = _plants.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _plants[index].lastWateredAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  Future<void> updateCustomName(String id, String name) async {
    final index = _plants.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final trimmed = name.trim();
    _plants[index].customName = trimmed.isEmpty ? null : trimmed;
    final garden = _plants[index];
    final plant = plantById(garden.plantId);
    if (plant != null) {
      await TrayHistoryStore.instance.syncMetadata(garden: garden, plant: plant);
    }
    await _persist();
    notifyListeners();
  }

  /// Mark all trays on light as watered today.
  Future<void> waterGrowingPlants() async {
    final now = DateTime.now();
    var changed = false;
    for (final garden in _plants) {
      if (garden.stage != GrowthStage.grow) continue;
      garden.lastWateredAt = now;
      changed = true;
    }
    if (!changed) return;
    await _persist();
    notifyListeners();
  }

  /// Apply a home-screen reminder action. Returns a snapshot for undo.
  Future<ReminderUndo?> completeReminderAction({
    required DueActionKind? kind,
    String? gardenId,
  }) async {
    if (kind == null || kind == DueActionKind.water) {
      final before = <String, DateTime>{};
      for (final garden in _plants) {
        if (garden.stage != GrowthStage.grow) continue;
        before[garden.id] = garden.lastWateredAt;
      }
      await waterGrowingPlants();
      if (before.isEmpty) return null;
      return ReminderUndo.water(before);
    }
    if (gardenId == null) return null;

    final index = _plants.indexWhere((p) => p.id == gardenId);
    if (index < 0) return null;
    final garden = _plants[index];
    final plant = plantById(garden.plantId);
    if (plant == null) return null;

    if (garden.completesNext(plant)) {
      // Same as «Собрать» on Моя грядка: remove tray (with undo snapshot).
      final snapshot = GardenPlant.fromJson(garden.toJson());
      await harvestPlant(gardenId);
      return ReminderUndo.harvest(snapshot, index);
    }

    final previousStage = garden.stage;
    final previousStageChangedAt = garden.stageChangedAt;
    final action = garden.nextActionLabel(plant).toLowerCase();
    garden.advanceStage(plant);
    await TrayHistoryStore.instance.recordAdvance(
      garden: garden,
      plant: plant,
      action: action,
      stage: garden.stage,
    );
    await PlantingLogService.instance.append(
      cycleName: garden.analyticsTitle(plant),
      action: action,
      stageOrComment: PlantingLogService.stageField(garden.stage),
    );
    await _persist();
    notifyListeners();
    return ReminderUndo.stage(
      kind: kind,
      gardenId: gardenId,
      previousStage: previousStage,
      previousStageChangedAt: previousStageChangedAt,
    );
  }

  Future<void> undoReminderAction(ReminderUndo undo) async {
    switch (undo.kind) {
      case DueActionKind.water:
        final before = undo.wateredBefore;
        if (before == null || before.isEmpty) return;
        var changed = false;
        for (final garden in _plants) {
          final prev = before[garden.id];
          if (prev == null) continue;
          garden.lastWateredAt = prev;
          changed = true;
        }
        if (!changed) return;
        await _persist();
        notifyListeners();
        return;
      case DueActionKind.harvest:
        final plant = undo.restoredPlant;
        if (plant == null) return;
        final index = (undo.insertIndex ?? 0).clamp(0, _plants.length);
        _plants.insert(index, plant);
        await TrayHistoryStore.instance.undoLastEvent(plant.id);
        await _persist();
        notifyListeners();
        return;
      case DueActionKind.sow:
      case DueActionKind.toLight:
        final id = undo.gardenId;
        final stage = undo.previousStage;
        final changedAt = undo.previousStageChangedAt;
        if (id == null || stage == null || changedAt == null) return;
        final index = _plants.indexWhere((p) => p.id == id);
        if (index < 0) return;
        _plants[index].stage = stage;
        _plants[index].stageChangedAt = changedAt;
        await TrayHistoryStore.instance.undoLastEvent(id);
        await _persist();
        notifyListeners();
        return;
    }
  }

  /// Advance to the next process step, or remove when collecting.
  Future<void> advancePlant(String id) async {
    final index = _plants.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final garden = _plants[index];
    final plant = plantById(garden.plantId);
    if (plant == null) return;
    if (garden.completesNext(plant)) {
      await harvestPlant(id);
      return;
    }
    final action = garden.nextActionLabel(plant).toLowerCase();
    garden.advanceStage(plant);
    if (garden.stage == GrowthStage.grow) {
      final wateredBaseline = DateTime.now();
      garden.lastWateredAt = DateTime(
        wateredBaseline.year,
        wateredBaseline.month,
        wateredBaseline.day,
      ).subtract(const Duration(days: 1));
    }
    await TrayHistoryStore.instance.recordAdvance(
      garden: garden,
      plant: plant,
      action: action,
      stage: garden.stage,
    );
    await PlantingLogService.instance.append(
      cycleName: garden.analyticsTitle(plant),
      action: action,
      stageOrComment: PlantingLogService.stageField(garden.stage),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> harvestPlant(String id) async {
    await _removePlant(id, action: 'собрать');
  }

  Future<ReminderUndo?> removePlant(String id) async {
    return _removePlant(id, action: 'удалить');
  }

  Future<ReminderUndo?> _removePlant(String id, {required String action}) async {
    final index = _plants.indexWhere((p) => p.id == id);
    if (index < 0) return null;
    final garden = _plants[index];
    final snapshot = GardenPlant.fromJson(garden.toJson());
    final plant = plantById(garden.plantId);
    final cycleName = plant != null
        ? garden.analyticsTitle(plant)
        : (garden.customName?.trim().isNotEmpty == true
            ? '${garden.customName!.trim()} (${garden.trayCount} шт)'
            : '${garden.plantId} (${garden.trayCount} шт)');
    final started = formatStartDate(garden.startedAt).replaceAll('.', '');
    if (plant != null) {
      await TrayHistoryStore.instance.recordClose(
        garden: garden,
        plant: plant,
        action: action,
      );
    }
    _plants.removeAt(index);
    await PlantingLogService.instance.append(
      cycleName: cycleName,
      action: action,
      stageOrComment:
          'старт=$started;лотков=${garden.trayCount};id=${garden.id}',
    );
    await _persist();
    notifyListeners();
    return ReminderUndo.harvest(snapshot, index);
  }
}

/// Snapshot of garden state before a home-reminder action, for snackbar undo.
class ReminderUndo {
  ReminderUndo._({
    required this.kind,
    this.gardenId,
    this.wateredBefore,
    this.restoredPlant,
    this.insertIndex,
    this.previousStage,
    this.previousStageChangedAt,
  });

  factory ReminderUndo.water(Map<String, DateTime> wateredBefore) =>
      ReminderUndo._(
        kind: DueActionKind.water,
        wateredBefore: wateredBefore,
      );

  factory ReminderUndo.harvest(GardenPlant plant, int index) => ReminderUndo._(
        kind: DueActionKind.harvest,
        restoredPlant: plant,
        insertIndex: index,
      );

  factory ReminderUndo.stage({
    required DueActionKind kind,
    required String gardenId,
    required GrowthStage previousStage,
    required DateTime previousStageChangedAt,
  }) =>
      ReminderUndo._(
        kind: kind,
        gardenId: gardenId,
        previousStage: previousStage,
        previousStageChangedAt: previousStageChangedAt,
      );

  final DueActionKind kind;
  final String? gardenId;
  final Map<String, DateTime>? wateredBefore;
  final GardenPlant? restoredPlant;
  final int? insertIndex;
  final GrowthStage? previousStage;
  final DateTime? previousStageChangedAt;
}
