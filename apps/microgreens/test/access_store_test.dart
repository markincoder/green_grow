import 'package:flutter_test/flutter_test.dart';
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
}
