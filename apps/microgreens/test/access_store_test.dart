import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/services/access_api.dart';
import 'package:green_grow/services/app_version.dart';
import 'package:green_grow/state/access_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AccessStore.remoteEnabled = false;
  });

  test('first start unlocks trial', () async {
    SharedPreferences.setMockInitialValues({});
    final access = AccessStore();
    await access.load();
    expect(access.firstStartAt, isNotNull);
    expect(access.unlocked, isTrue);
    expect(access.isOnTrial, isTrue);
    expect(access.isPaid, isFalse);
    expect(access.trialEndsAt, isNotNull);
  });

  test('expired trial locks the app', () async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 8));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
    });
    final access = AccessStore();
    await access.load();
    expect(access.unlocked, isFalse);
  });

  test('paid period unlocks after trial', () async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final paid = DateTime.now().toUtc().add(const Duration(days: 10));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_paid_expires_at': paid.toIso8601String(),
    });
    final access = AccessStore();
    await access.load();
    expect(access.unlocked, isTrue);
    expect(access.isPaid, isTrue);
    expect(access.isOnTrial, isFalse);
    expect(access.canActivateAccess, isFalse);
  });

  test('expired paid period locks again', () async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 400));
    final paid = DateTime.now().toUtc().subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_paid_expires_at': paid.toIso8601String(),
    });
    final access = AccessStore();
    await access.load();
    expect(access.unlocked, isFalse);
    expect(access.isPaid, isFalse);
    expect(access.paidExpired, isTrue);
    expect(access.canActivateAccess, isTrue);
  });

  test('activate offered on last paid day', () async {
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': DateTime.utc(2026, 7, 1).toIso8601String(),
      'access_paid_expires_at': DateTime.utc(2026, 8, 20, 18).toIso8601String(),
    });
    final lastDay = AccessStore(clock: () => DateTime.utc(2026, 8, 20, 12));
    await lastDay.load();
    expect(lastDay.isPaid, isTrue);
    expect(lastDay.isPaidLastDay, isTrue);
    expect(lastDay.canActivateAccess, isTrue);

    SharedPreferences.setMockInitialValues({
      'access_first_start_at': DateTime.utc(2026, 7, 1).toIso8601String(),
      'access_paid_expires_at': DateTime.utc(2026, 8, 20, 18).toIso8601String(),
    });
    final earlier = AccessStore(clock: () => DateTime.utc(2026, 8, 19, 12));
    await earlier.load();
    expect(earlier.isPaid, isTrue);
    expect(earlier.isPaidLastDay, isFalse);
    expect(earlier.canActivateAccess, isFalse);
  });

  test('jumping device clock past trial locks the app', () async {
    var now = DateTime.utc(2026, 8, 13, 12);
    SharedPreferences.setMockInitialValues({});
    final access = AccessStore(clock: () => now);
    await access.load();
    expect(access.unlocked, isTrue);

    now = DateTime.utc(2026, 8, 27, 12);
    access.recheck();
    expect(access.unlocked, isFalse);
  });

  test('clock rollback does not extend trial', () async {
    var now = DateTime.utc(2026, 8, 13, 12);
    SharedPreferences.setMockInitialValues({});
    final access = AccessStore(clock: () => now);
    await access.load();

    now = DateTime.utc(2026, 8, 22, 12);
    access.recheck();
    expect(access.unlocked, isFalse);

    now = DateTime.utc(2026, 8, 14, 12);
    access.recheck();
    expect(access.unlocked, isFalse);
  });

  test('missing local code does not prompt to buy', () async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 30));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_email': 'user@example.com',
    });
    final access = AccessStore();
    await access.load();
    expect(access.consumeStartupActivationOffer(), isFalse);
    expect(access.isOnTrial, isFalse);
  });

  test('offline startup check keeps access and shows no prompt', () async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final paid = DateTime.now().toUtc().add(const Duration(days: 10));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_paid_expires_at': paid.toIso8601String(),
      'access_email': 'user@example.com',
      'access_code': '123456',
    });
    final access = AccessStore(api: _FakeAccessApi.unavailable());
    await access.load();
    expect(access.isPaid, isTrue);
    expect(access.consumeStartupActivationOffer(), isFalse);
  });

  test('expired server activation syncs local expiry and offers code', () async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final localPaid = DateTime.now().toUtc().add(const Duration(days: 10));
    final serverExpired = DateTime.now().toUtc().subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_paid_expires_at': localPaid.toIso8601String(),
      'access_email': 'user@example.com',
      'access_code': '123456',
    });
    final access = AccessStore(
      api: _FakeAccessApi.expired(expiresAt: serverExpired),
    );
    await access.load();
    expect(access.isPaid, isFalse);
    expect(access.paidExpired, isTrue);
    expect(access.paidExpiresAt, serverExpired);
    expect(access.isOnTrial, isTrue);
    expect(access.canActivateAccess, isTrue);
    expect(access.consumeStartupActivationOffer(), isTrue);
  });

  test('missing server activation falls back to trial', () async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final localPaid = DateTime.now().toUtc().add(const Duration(days: 10));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_paid_expires_at': localPaid.toIso8601String(),
      'access_email': 'user@example.com',
      'access_code': '123456',
    });
    final access = AccessStore(api: _FakeAccessApi.missing());
    await access.load();
    expect(access.isPaid, isFalse);
    expect(access.paidExpiresAt, isNull);
    expect(access.isOnTrial, isTrue);
    expect(access.consumeStartupActivationOffer(), isFalse);
  });

  test('valid server activation syncs expiry into local storage', () async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final localPaid = DateTime.now().toUtc().add(const Duration(days: 2));
    final serverPaid = DateTime.now().toUtc().add(const Duration(days: 40));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_paid_expires_at': localPaid.toIso8601String(),
      'access_email': 'user@example.com',
      'access_code': '123456',
    });
    final access = AccessStore(api: _FakeAccessApi.valid(serverPaid));
    await access.load();
    expect(access.isPaid, isTrue);
    expect(access.paidExpiresAt, serverPaid);
    expect(access.consumeStartupActivationOffer(), isFalse);
  });

  test('newer published version offers an update after config fetch', () async {
    AccessStore.remoteEnabled = true;
    SharedPreferences.setMockInitialValues({});
    final api = _FakeAccessApi.missing()
      ..config = const AccessConfig(
        trialPeriod: 7,
        paidPeriod: 12,
        siteUrl: 'https://agronizer.ru',
        appVersion: '1.0.5',
        appBuild: 6,
        apkUrl: 'https://agronizer.ru/apps/microgreens/microgreens.apk',
      );
    final access = AccessStore(
      api: api,
      readLocalVersion: () async => const AppVersion('1.0.4', 5),
    );
    await access.load();
    expect(access.updateAvailable, isTrue);
    expect(access.remoteVersion, const AppVersion('1.0.5', 6));
    expect(access.consumeUpdateOffer(), isTrue);
    expect(access.consumeUpdateOffer(), isFalse);
  });

  test('same published version does not offer an update', () async {
    AccessStore.remoteEnabled = true;
    SharedPreferences.setMockInitialValues({});
    final api = _FakeAccessApi.missing()
      ..config = const AccessConfig(
        trialPeriod: 7,
        paidPeriod: 12,
        siteUrl: 'https://agronizer.ru',
        appVersion: '1.0.4',
        appBuild: 5,
      );
    final access = AccessStore(
      api: api,
      readLocalVersion: () async => const AppVersion('1.0.4', 5),
    );
    await access.load();
    expect(access.updateAvailable, isFalse);
    expect(access.consumeUpdateOffer(), isFalse);
  });
}

class _FakeAccessApi extends AccessApi {
  _FakeAccessApi(this._status, [this._expiresAt]);

  final AccessCheckStatus _status;
  final DateTime? _expiresAt;
  AccessConfig? config;

  factory _FakeAccessApi.unavailable() =>
      _FakeAccessApi(AccessCheckStatus.unavailable);
  factory _FakeAccessApi.expired({DateTime? expiresAt}) =>
      _FakeAccessApi(AccessCheckStatus.expired, expiresAt);
  factory _FakeAccessApi.missing() =>
      _FakeAccessApi(AccessCheckStatus.missing);
  factory _FakeAccessApi.valid(DateTime expiresAt) =>
      _FakeAccessApi(AccessCheckStatus.valid, expiresAt);

  @override
  Future<AccessConfig> fetchConfig() async {
    final cfg = config;
    if (cfg == null) throw StateError('no config');
    return cfg;
  }

  @override
  Future<AccessCheckResult> checkActivation(String code, String email) async {
    return AccessCheckResult(status: _status, expiresAt: _expiresAt);
  }
}
