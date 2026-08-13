import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';
import '../services/planting_log_service.dart';

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
      lastWateredAt: now,
      stage: resolvedStage,
      stageChangedAt: start,
      customName: (name != null && name.isNotEmpty) ? name : null,
      seedGrams: seedGrams ?? plant?.seedGrams,
    );
    _plants.insert(0, garden);
    if (plant != null) {
      await PlantingLogService.instance.append(
        cycleName: garden.titleWithDate(plant),
        action: 'начать',
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

  /// Apply a home-screen reminder action to garden state.
  Future<void> completeReminderAction({
    required DueActionKind? kind,
    String? gardenId,
  }) async {
    if (kind == null) {
      await waterGrowingPlants();
      return;
    }
    if (gardenId == null) return;
    await advancePlant(gardenId);
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
    await PlantingLogService.instance.append(
      cycleName: garden.titleWithDate(plant),
      action: action,
      stageOrComment: PlantingLogService.stageField(garden.stage),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> harvestPlant(String id) async {
    await _removePlant(id, action: 'собрать');
  }

  Future<void> removePlant(String id) async {
    await _removePlant(id, action: 'удалить');
  }

  Future<void> _removePlant(String id, {required String action}) async {
    final index = _plants.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final garden = _plants[index];
    final plant = plantById(garden.plantId);
    final cycleName = plant != null
        ? garden.titleWithDate(plant)
        : (garden.customName?.trim().isNotEmpty == true
            ? garden.customName!.trim()
            : garden.plantId);
    _plants.removeAt(index);
    await PlantingLogService.instance.append(
      cycleName: cycleName,
      action: action,
      stageOrComment: '',
    );
    await _persist();
    notifyListeners();
  }
}
