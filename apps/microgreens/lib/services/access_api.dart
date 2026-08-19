import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AccessConfig {
  const AccessConfig({
    required this.trialPeriod,
    required this.paidPeriod,
    required this.siteUrl,
    this.appVersion = '',
    this.appBuild = 0,
    this.apkUrl = '',
    this.pwaUrl = '',
  });

  final int trialPeriod;
  final int paidPeriod;
  final String siteUrl;
  final String appVersion;
  final int appBuild;
  final String apkUrl;
  final String pwaUrl;
}

class AccessActivateResult {
  const AccessActivateResult._({this.expiresAt, this.error});

  final DateTime? expiresAt;
  final String? error;

  bool get ok => expiresAt != null;
}

enum AccessCheckStatus { valid, expired, missing, unavailable }

class AccessCheckResult {
  const AccessCheckResult({
    required this.status,
    this.expiresAt,
  });

  final AccessCheckStatus status;
  final DateTime? expiresAt;
}

class AccessApi {
  AccessApi({http.Client? client}) : _client = client ?? http.Client();

  static const defaultSiteUrl = String.fromEnvironment(
    'SITE_URL',
    defaultValue: 'https://agronizer.ru',
  );
  static const defaultTrialPeriod = int.fromEnvironment(
    'TRIAL_PERIOD',
    defaultValue: 7,
  );
  static const defaultPaidPeriod = int.fromEnvironment(
    'PAID_PERIOD',
    defaultValue: 12,
  );

  static const _timeout = Duration(seconds: 8);

  final http.Client _client;

  static String get baseUrl {
    const defined = String.fromEnvironment('SITE_URL', defaultValue: '');
    if (defined.isNotEmpty) {
      return defined.replaceAll(RegExp(r'/+$'), '');
    }
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return defaultSiteUrl.replaceAll(RegExp(r'/+$'), '');
  }

  Future<AccessConfig> fetchConfig() async {
    final res = await _client
        .get(Uri.parse('$baseUrl/api/config'))
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('config ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    if (data is! Map) {
      throw StateError('config shape');
    }
    final days = data['trialPeriod'];
    final months = data['paidPeriod'];
    final site = data['siteUrl']?.toString().trim();
    final appVersion = data['appVersion']?.toString().trim() ?? '';
    final appBuildRaw = data['appBuild'];
    final apk = data['apkUrl']?.toString().trim() ?? '';
    final pwa = data['pwaUrl']?.toString().trim() ?? '';
    return AccessConfig(
      trialPeriod: days is num && days > 0 ? days.round() : defaultTrialPeriod,
      paidPeriod:
          months is num && months > 0 ? months.round() : defaultPaidPeriod,
      siteUrl: (site != null && site.isNotEmpty) ? site : defaultSiteUrl,
      appVersion: appVersion,
      appBuild: appBuildRaw is num
          ? appBuildRaw.round()
          : int.tryParse('$appBuildRaw') ?? 0,
      apkUrl: apk,
      pwaUrl: pwa,
    );
  }

  Future<AccessActivateResult> activate(String code, String email) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    final mail = email.trim();
    final res = await _client
        .post(
          Uri.parse('$baseUrl/api/access/activate'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': digits,
            'email': mail,
            'slug': 'microgreens',
          }),
        )
        .timeout(_timeout);
    Map<String, dynamic> data = const {};
    try {
      final parsed = jsonDecode(res.body);
      if (parsed is Map<String, dynamic>) data = parsed;
    } catch (_) {}
    final err = data['error']?.toString();
    if (res.statusCode == 410 || err == 'expired') {
      return const AccessActivateResult._(error: 'expired');
    }
    if (err == 'mismatch') {
      return const AccessActivateResult._(error: 'mismatch');
    }
    if (res.statusCode >= 400 || data['ok'] != true) {
      return const AccessActivateResult._(error: 'invalid');
    }
    final raw = data['expiresAt']?.toString() ?? '';
    final expires = DateTime.tryParse(raw);
    if (expires == null) {
      return const AccessActivateResult._(error: 'invalid');
    }
    return AccessActivateResult._(expiresAt: expires.toUtc());
  }

  Future<AccessCheckResult> checkActivation(String code, String email) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    final mail = email.trim();
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/api/access/activate'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': digits,
              'email': mail,
              'slug': 'microgreens',
            }),
          )
          .timeout(_timeout);
      Map<String, dynamic> data = const {};
      try {
        final parsed = jsonDecode(res.body);
        if (parsed is Map<String, dynamic>) data = parsed;
      } catch (_) {}
      final err = data['error']?.toString();
      final raw = data['expiresAt']?.toString() ?? '';
      final expires = DateTime.tryParse(raw)?.toUtc();
      if (res.statusCode == 410 || err == 'expired') {
        return AccessCheckResult(
          status: AccessCheckStatus.expired,
          expiresAt: expires,
        );
      }
      if (res.statusCode >= 500) {
        return const AccessCheckResult(status: AccessCheckStatus.unavailable);
      }
      if (res.statusCode >= 400 ||
          err == 'mismatch' ||
          err == 'invalid' ||
          data['ok'] != true) {
        return const AccessCheckResult(status: AccessCheckStatus.missing);
      }
      if (expires == null) {
        return const AccessCheckResult(status: AccessCheckStatus.missing);
      }
      return AccessCheckResult(
        status: AccessCheckStatus.valid,
        expiresAt: expires,
      );
    } catch (_) {
      return const AccessCheckResult(status: AccessCheckStatus.unavailable);
    }
  }
}
