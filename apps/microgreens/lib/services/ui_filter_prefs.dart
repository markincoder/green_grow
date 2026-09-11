import 'package:shared_preferences/shared_preferences.dart';

import '../data/plants_data.dart';

/// Saved chip on «База знаний»: `all`, `favorites`, or a catalog tag.
class CatalogFilterPrefs {
  CatalogFilterPrefs._();

  static SharedPreferences? prefsOverride;

  static const _key = 'catalog_screen_filter_v1';
  static const all = 'all';
  static const favorites = 'favorites';

  static Future<SharedPreferences> _prefs() async =>
      prefsOverride ?? SharedPreferences.getInstance();

  static Future<String> load() async {
    final raw = (await _prefs()).getString(_key);
    if (raw == null || raw.isEmpty) return all;
    if (raw == all || raw == favorites) return raw;
    if (catalogFilterTags.contains(raw)) return raw;
    return all;
  }

  static Future<void> save(String value) async {
    await (await _prefs()).setString(_key, value);
  }
}
