import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesStore extends ChangeNotifier {
  static const _storageKey = 'favorite_plant_ids_v1';

  final Set<String> _ids = {};
  bool loaded = false;

  Set<String> get ids => Set.unmodifiable(_ids);

  bool isFavorite(String plantId) => _ids.contains(plantId);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _ids
      ..clear()
      ..addAll(prefs.getStringList(_storageKey) ?? const []);
    loaded = true;
    notifyListeners();
  }

  Future<void> toggle(String plantId) async {
    if (!_ids.add(plantId)) {
      _ids.remove(plantId);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _ids.toList());
  }
}
