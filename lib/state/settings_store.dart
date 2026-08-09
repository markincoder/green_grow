import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore extends ChangeNotifier {
  static const _hourKey = 'reminder_hour';
  static const _minuteKey = 'reminder_minute';
  static const _enabledKey = 'reminders_enabled';

  bool loaded = false;
  bool enabled = true;
  TimeOfDay reminderTime = const TimeOfDay(hour: 9, minute: 0);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_enabledKey) ?? true;
    reminderTime = TimeOfDay(
      hour: prefs.getInt(_hourKey) ?? 9,
      minute: prefs.getInt(_minuteKey) ?? 0,
    );
    loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    notifyListeners();
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    reminderTime = time;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, time.hour);
    await prefs.setInt(_minuteKey, time.minute);
    notifyListeners();
  }

  String get reminderTimeLabel {
    final h = reminderTime.hour.toString().padLeft(2, '0');
    final m = reminderTime.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
