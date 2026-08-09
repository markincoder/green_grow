import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';

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
    } else {
      _seedDemo();
    }
    loaded = true;
    notifyListeners();
  }

  void _seedDemo() {
    final now = DateTime.now();
    final arugula = plantById('arugula_mg')!;
    final basil = plantById('basil_mg')!;

    _plants.addAll([
      GardenPlant(
        id: 'demo-arugula-ready',
        plantId: 'arugula_mg',
        startedAt: now.subtract(arugula.cycleDuration),
        lastWateredAt: now.subtract(const Duration(days: 1)),
        stage: GrowthStage.harvest,
        stageChangedAt: now.subtract(const Duration(days: 1)),
      ),
      GardenPlant(
        id: 'demo-arugula-new',
        plantId: 'arugula_mg',
        startedAt: now,
        lastWateredAt: now,
        stage: GardenPlant.initialStageFor(arugula),
      ),
      GardenPlant(
        id: 'demo-basil',
        plantId: 'basil_mg',
        startedAt: now.subtract(
          basil.cycleDuration - const Duration(days: 3),
        ),
        lastWateredAt: now.subtract(const Duration(hours: 20)),
        stage: GrowthStage.grow,
        stageChangedAt: now.subtract(const Duration(days: 3)),
      ),
    ]);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_plants.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  Future<void> startPlant({
    required String plantId,
    DateTime? startedAt,
  }) async {
    final now = DateTime.now();
    final start = startedAt ?? now;
    final plant = plantById(plantId);
    final stage = plant != null
        ? GardenPlant.initialStageFor(plant)
        : GrowthStage.germinate;

    _plants.insert(
      0,
      GardenPlant(
        id: 'gp-${now.microsecondsSinceEpoch}',
        plantId: plantId,
        startedAt: start,
        lastWateredAt: now,
        stage: stage,
        stageChangedAt: start,
      ),
    );
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
    garden.advanceStage(plant);
    await _persist();
    notifyListeners();
  }

  Future<void> harvestPlant(String id) async {
    _plants.removeWhere((p) => p.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> removePlant(String id) => harvestPlant(id);
}
