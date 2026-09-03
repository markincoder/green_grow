import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/plants_data.dart';

/// User notes on a knowledge-base culture, keyed by catalog plant id.
class PlantNotesStore {
  static const storageKey = 'plant_notes_v1';

  static String canonicalPlantId(String plantId) =>
      plantById(plantId)?.id ?? plantId;

  static Future<String> noteFor(String plantId) async {
    final all = await _read();
    final canonical = canonicalPlantId(plantId);
    final direct = all[canonical] ?? all[plantId];
    if (direct != null) return direct;
    for (final entry in all.entries) {
      if (canonicalPlantId(entry.key) == canonical) {
        return entry.value;
      }
    }
    return '';
  }

  static Future<void> setNote(String plantId, String text) async {
    final all = await _read();
    final canonical = canonicalPlantId(plantId);
    all.removeWhere((key, _) => canonicalPlantId(key) == canonical);
    if (text.trim().isNotEmpty) {
      all[canonical] = text;
    }
    await _write(all);
  }

  static Future<Map<String, String>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _write(Map<String, String> notes) async {
    final prefs = await SharedPreferences.getInstance();
    if (notes.isEmpty) {
      await prefs.remove(storageKey);
      return;
    }
    await prefs.setString(storageKey, jsonEncode(notes));
  }
}
