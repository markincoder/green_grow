import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/access_api.dart';
import '../services/app_version.dart';
import 'access_backup.dart';

class AccessStore extends ChangeNotifier {
  AccessStore({
    AccessApi? api,
    DateTime Function()? clock,
    Future<AppVersion> Function()? readLocalVersion,
  })  : _api = api ?? AccessApi(),
        _clock = clock ?? _systemClock,
        _readLocalVersion = readLocalVersion ?? AppVersion.fromPlatform;

  static DateTime _systemClock() => DateTime.now().toUtc();

  static const _firstStartKey = 'access_first_start_at';
  static const _firstStartMsKey = 'access_first_start_ms';
  static const _lastSeenMsKey = 'access_last_seen_ms';
  static const _paidExpiresKey = 'access_paid_expires_at';
  static const _emailKey = 'access_email';
  static const _codeKey = 'access_code';

  /// Tests set this to skip `/api/config`.
  static bool remoteEnabled = true;

  final AccessApi _api;
  final DateTime Function() _clock;
  final Future<AppVersion> Function() _readLocalVersion;

  bool loaded = false;
  bool unlocked = false;
  int trialPeriodDays = AccessApi.defaultTrialPeriod;
  int paidPeriodMonths = AccessApi.defaultPaidPeriod;
  String siteUrl = AccessApi.defaultSiteUrl;
  String apkUrl = '';
  AppVersion? localVersion;
  AppVersion? remoteVersion;
  bool updateAvailable = false;
  DateTime? firstStartAt;
  DateTime? paidExpiresAt;
  DateTime? lastSeenAt;
  String email = '';
  String code = '';
  bool _offerActivationCode = false;
  bool _offerUpdate = false;

  bool consumeStartupActivationOffer() {
    final value = _offerActivationCode;
    _offerActivationCode = false;
    return value;
  }

  bool consumeUpdateOffer() {
    final value = _offerUpdate;
    _offerUpdate = false;
    return value;
  }

  /// Offer the update dialog again (e.g. waiting service worker on web).
  void offerUpdate({AppVersion? remote}) {
    if (remote != null) remoteVersion = remote;
    updateAvailable = true;
    _offerUpdate = true;
    notifyListeners();
  }

  Uri get buyUri {
    final base = siteUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/pay/microgreens/');
  }

  Uri get updateApkUri {
    final raw = apkUrl.trim();
    if (raw.isNotEmpty) return Uri.parse(raw);
    return Uri.parse(
      'https://www.rustore.ru/catalog/app/com.agronizer.greengrow',
    );
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

  /// Show activate/extend during trial, on the last paid day, or when locked.
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
    code = prefs.getString(_codeKey) ?? '';
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
        apkUrl = cfg.apkUrl;
        _refreshUnlocked();
        notifyListeners();
        await _checkAppUpdate(cfg);
      } catch (_) {
        /* keep defaults */
      }
    }
    await _checkActivationOnStartup();
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
    this.code = code.replaceAll(RegExp(r'\D'), '');
    // Always mirror server expiry — re-activation returns the first activation dates.
    await _persistPaidExpiry(result.expiresAt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, this.email);
    await prefs.setString(_codeKey, this.code);
    _refreshUnlocked();
    notifyListeners();
    return unlocked ? null : 'expired';
  }

  Future<void> _checkActivationOnStartup() async {
    _offerActivationCode = false;
    final hasSavedCredentials =
        email.trim().isNotEmpty && code.trim().isNotEmpty;

    if (!hasSavedCredentials) {
      return;
    }

    final check = await _api.checkActivation(code, email);
    if (check.status == AccessCheckStatus.unavailable) {
      // Offline mode or temporary server issue: keep local state and continue.
      return;
    }

    if (check.status == AccessCheckStatus.valid && check.expiresAt != null) {
      await _persistPaidExpiry(check.expiresAt);
      _refreshUnlocked();
      notifyListeners();
      return;
    }

    if (check.status == AccessCheckStatus.expired) {
      await _persistPaidExpiry(_expiredExpiry(check.expiresAt));
      _refreshUnlocked();
      _offerActivationCode = true;
      notifyListeners();
      return;
    }

    // No activation record on the server — local paid state is stale.
    await _persistPaidExpiry(null);
    _refreshUnlocked();
    notifyListeners();
  }

  Future<void> _checkAppUpdate(AccessConfig cfg) async {
    _offerUpdate = false;
    updateAvailable = false;
    remoteVersion = AppVersion.tryParse(cfg.appVersion, cfg.appBuild);
    try {
      localVersion = await _readLocalVersion();
    } catch (_) {
      localVersion = null;
    }
    final remote = remoteVersion;
    final local = localVersion;
    if (remote == null || local == null) return;
    if (!remote.isNewerThan(local)) return;
    if (cfg.apkUrl.isNotEmpty) apkUrl = cfg.apkUrl;
    updateAvailable = true;
    _offerUpdate = true;
  }

  DateTime _expiredExpiry(DateTime? serverExpiry) {
    if (serverExpiry != null) return serverExpiry.toUtc();
    final local = paidExpiresAt?.toUtc();
    if (local != null && !_effectiveNow().isBefore(local)) return local;
    return _effectiveNow().subtract(const Duration(seconds: 1));
  }

  Future<void> _persistPaidExpiry(DateTime? expires) async {
    paidExpiresAt = expires?.toUtc();
    final prefs = await SharedPreferences.getInstance();
    if (paidExpiresAt == null) {
      await prefs.remove(_paidExpiresKey);
    } else {
      await prefs.setString(_paidExpiresKey, paidExpiresAt!.toIso8601String());
    }
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
