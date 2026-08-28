import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plant.dart';

class SettingsStore extends ChangeNotifier {
  static const _hourKey = 'reminder_hour';
  static const _minuteKey = 'reminder_minute';
  static const _enabledKey = 'reminders_enabled';
  static const _soakSeparateKey = 'soak_separate_enabled';
  static const _dismissedKey = 'dismissed_reminders_v1';

  bool loaded = false;
  bool enabled = true;
  bool soakSeparateEnabled = true;
  TimeOfDay reminderTime = const TimeOfDay(hour: 9, minute: 0);

  final Set<String> _dismissed = {};

  Set<String> get dismissedReminderKeys => Set.unmodifiable(_dismissed);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_enabledKey) ?? true;
    soakSeparateEnabled = prefs.getBool(_soakSeparateKey) ?? true;
    reminderTime = TimeOfDay(
      hour: prefs.getInt(_hourKey) ?? 9,
      minute: prefs.getInt(_minuteKey) ?? 0,
    );
    _dismissed
      ..clear()
      ..addAll(prefs.getStringList(_dismissedKey) ?? const []);
    _pruneStaleDismissals();
    loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    notifyListeners();
  }

  Future<void> setSoakSeparateEnabled(bool value) async {
    soakSeparateEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soakSeparateKey, value);
    notifyListeners();
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    reminderTime = time;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, time.hour);
    await prefs.setInt(_minuteKey, time.minute);
    notifyListeners();
  }

  bool isReminderDismissed(String key) => _dismissed.contains(key);

  Future<void> dismissReminder(String key) async {
    if (!_dismissed.add(key)) return;
    await _persistDismissed();
    notifyListeners();
  }

  Future<void> restoreReminder(String key) async {
    if (!_dismissed.remove(key)) return;
    await _persistDismissed();
    notifyListeners();
  }

  Future<void> dismissReminders(Iterable<String> keys) async {
    var changed = false;
    for (final key in keys) {
      changed = _dismissed.add(key) || changed;
    }
    if (!changed) return;
    await _persistDismissed();
    notifyListeners();
  }

  Future<void> clearDismissalsForGarden(String gardenId) async {
    final before = _dismissed.length;
    _dismissed.removeWhere((k) => k.startsWith('$gardenId|'));
    if (_dismissed.length == before) return;
    await _persistDismissed();
    notifyListeners();
  }

  Future<void> pruneDismissals(Set<String> activeGardenIds) async {
    final before = _dismissed.length;
    _dismissed.removeWhere((k) {
      if (k.startsWith('water|')) return false;
      final gardenId = k.split('|').first;
      return !activeGardenIds.contains(gardenId);
    });
    _pruneStaleDismissals();
    if (_dismissed.length == before) return;
    await _persistDismissed();
    notifyListeners();
  }

  Future<void> _persistDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedKey, _dismissed.toList());
  }

  /// Keep only today's day-scoped dismissals so overdue actions reappear tomorrow.
  void _pruneStaleDismissals() {
    final today = dayStamp(DateTime.now());
    _dismissed.removeWhere((k) {
      final stamp = _dayStampFromKey(k);
      if (stamp == null) {
        // Legacy permanent keys (gardenId|kind) — drop so overdue can return.
        return true;
      }
      return stamp != today;
    });
  }

  static final _dayStampRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String? _dayStampFromKey(String key) {
    final parts = key.split('|');
    if (parts.isEmpty) return null;
    final last = parts.last;
    if (_dayStampRe.hasMatch(last)) return last;
    return null;
  }

  static String dayStamp(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Day-scoped so a checkmark only silences the reminder for that calendar day.
  static String gardenActionKey(
    String gardenId,
    DueActionKind kind,
    DateTime day,
  ) =>
      '$gardenId|${kind.name}|${dayStamp(day)}';

  static String waterKey(DateTime day) => 'water|${dayStamp(day)}';

  String get reminderTimeLabel {
    final h = reminderTime.hour.toString().padLeft(2, '0');
    final m = reminderTime.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
