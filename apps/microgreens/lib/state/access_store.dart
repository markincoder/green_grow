import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/access_api.dart';
import 'access_backup.dart';

class AccessStore extends ChangeNotifier {
  AccessStore({AccessApi? api, DateTime Function()? clock})
      : _api = api ?? AccessApi(),
        _clock = clock ?? _systemClock;

  static DateTime _systemClock() => DateTime.now().toUtc();

  static const _firstStartKey = 'access_first_start_at';
  static const _firstStartMsKey = 'access_first_start_ms';
  static const _lastSeenMsKey = 'access_last_seen_ms';
  static const _paidExpiresKey = 'access_paid_expires_at';
  static const _emailKey = 'access_email';

  /// Tests set this to skip `/api/config`.
  static bool remoteEnabled = true;

  final AccessApi _api;
  final DateTime Function() _clock;

  bool loaded = false;
  bool unlocked = false;
  int trialPeriodDays = AccessApi.defaultTrialPeriod;
  int paidPeriodMonths = AccessApi.defaultPaidPeriod;
  String siteUrl = AccessApi.defaultSiteUrl;
  DateTime? firstStartAt;
  DateTime? paidExpiresAt;
  DateTime? lastSeenAt;
  String email = '';

  Uri get buyUri {
    final base = siteUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/pay/microgreens/');
  }

  Uri get siteUri => Uri.parse(siteUrl);

  DateTime? get trialEndsAt {
    if (firstStartAt == null) return null;
    return firstStartAt!.toUtc().add(Duration(days: trialPeriodDays));
  }

  bool get isPaid {
    if (paidExpiresAt == null) return false;
    return _effectiveNow().isBefore(paidExpiresAt!.toUtc());
  }

  bool get isOnTrial {
    if (!unlocked || isPaid) return false;
    final end = trialEndsAt;
    return end != null && _effectiveNow().isBefore(end);
  }

  bool get paidExpired {
    if (paidExpiresAt == null) return false;
    return !_effectiveNow().isBefore(paidExpiresAt!.toUtc());
  }

  bool get isPaidLastDay {
    if (!isPaid || paidExpiresAt == null) return false;
    return _sameLocalDay(_effectiveNow(), paidExpiresAt!);
  }

  /// Show «Активировать доступ» during trial, on the last paid day, or when locked.
  bool get canActivateAccess => isOnTrial || isPaidLastDay || !unlocked;

  static bool _sameLocalDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String get siteHost {
    final host = siteUri.host;
    return host.isEmpty ? 'agronizer.ru' : host;
  }

  String get paidPeriodLabel {
    final n = paidPeriodMonths;
    if (n % 12 == 0) {
      final years = n ~/ 12;
      return '$years ${_ruPlural(years, 'год', 'года', 'лет')}';
    }
    return '$n ${_ruPlural(n, 'месяц', 'месяца', 'месяцев')}';
  }

  static String _ruPlural(int n, String one, String few, String many) {
    final abs = n.abs() % 100;
    if (abs >= 11 && abs <= 14) return many;
    final last = abs % 10;
    if (last == 1) return one;
    if (last >= 2 && last <= 4) return few;
    return many;
  }

  DateTime _now() => _clock().toUtc();

  /// Wall clock can jump back; never let that extend the trial.
  DateTime _effectiveNow() {
    final now = _now();
    if (lastSeenAt != null && lastSeenAt!.isAfter(now)) {
      return lastSeenAt!.toUtc();
    }
    return now;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    firstStartAt = _readTime(prefs.getString(_firstStartKey));
    final startMs = prefs.getInt(_firstStartMsKey);
    if (startMs != null) {
      final fromMs = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
      if (firstStartAt == null || fromMs.isBefore(firstStartAt!)) {
        firstStartAt = fromMs;
      }
    }
    final backupMs = readAccessFirstStartBackup();
    if (backupMs != null) {
      final fromCookie =
          DateTime.fromMillisecondsSinceEpoch(backupMs, isUtc: true);
      if (firstStartAt == null || fromCookie.isBefore(firstStartAt!)) {
        firstStartAt = fromCookie;
      }
    }
    if (firstStartAt == null) {
      firstStartAt = _now();
    }
    lastSeenAt = _readMs(prefs.getInt(_lastSeenMsKey));
    paidExpiresAt = _readTime(prefs.getString(_paidExpiresKey));
    email = prefs.getString(_emailKey) ?? '';
    _refreshUnlocked();
    loaded = true;
    await _persistAnchors(prefs);
    notifyListeners();

    if (remoteEnabled) {
      try {
        final cfg = await _api.fetchConfig();
        trialPeriodDays = cfg.trialPeriod;
        paidPeriodMonths = cfg.paidPeriod;
        siteUrl = cfg.siteUrl;
        _refreshUnlocked();
        notifyListeners();
      } catch (_) {
        /* keep defaults */
      }
    }
  }

  void recheck() {
    if (!loaded) return;
    final before = unlocked;
    _refreshUnlocked();
    unawaited(_persistLastSeen());
    if (before != unlocked) notifyListeners();
  }

  Future<String?> activate(String code, String email) async {
    final result = await _api.activate(code, email);
    if (!result.ok) {
      return result.error ?? 'invalid';
    }
    this.email = email.trim();
    // Always mirror server expiry — re-activation returns the first activation dates.
    paidExpiresAt = result.expiresAt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paidExpiresKey, paidExpiresAt!.toIso8601String());
    await prefs.setString(_emailKey, this.email);
    _refreshUnlocked();
    notifyListeners();
    return unlocked ? null : 'expired';
  }

  void _refreshUnlocked() {
    final now = _effectiveNow();
    if (paidExpiresAt != null && now.isBefore(paidExpiresAt!.toUtc())) {
      unlocked = true;
      return;
    }
    if (firstStartAt != null) {
      final trialEnd =
          firstStartAt!.toUtc().add(Duration(days: trialPeriodDays));
      if (now.isBefore(trialEnd)) {
        unlocked = true;
        return;
      }
    }
    unlocked = false;
  }

  Future<void> _persistAnchors(SharedPreferences prefs) async {
    if (firstStartAt != null) {
      final ms = firstStartAt!.toUtc().millisecondsSinceEpoch;
      await prefs.setString(_firstStartKey, firstStartAt!.toUtc().toIso8601String());
      await prefs.setInt(_firstStartMsKey, ms);
      writeAccessFirstStartBackup(ms);
    }
    await _persistLastSeen(prefs);
  }

  Future<void> _persistLastSeen([SharedPreferences? existing]) async {
    final now = _now();
    if (lastSeenAt == null || now.isAfter(lastSeenAt!)) {
      lastSeenAt = now;
    }
    final prefs = existing ?? await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenMsKey, lastSeenAt!.millisecondsSinceEpoch);
  }

  static DateTime? _readTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  static DateTime? _readMs(int? ms) {
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
