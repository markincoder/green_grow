import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/services/app_version.dart';

void main() {
  test('compares name then build number', () {
    expect(const AppVersion('1.0.5').isNewerThan(const AppVersion('1.0.4', 9)), isTrue);
    expect(const AppVersion('1.0.4', 6).isNewerThan(const AppVersion('1.0.4', 5)), isTrue);
    expect(const AppVersion('1.0.4', 5).isNewerThan(const AppVersion('1.0.4', 5)), isFalse);
    expect(const AppVersion('1.0.3', 99).isNewerThan(const AppVersion('1.0.4')), isFalse);
  });

  test('parses pubspec-style values', () {
    expect(AppVersion.tryParse('1.0.4', '5'), const AppVersion('1.0.4', 5));
    expect(AppVersion.tryParse('1.0.4', 5), const AppVersion('1.0.4', 5));
    expect(AppVersion.tryParse(''), isNull);
    expect(AppVersion.tryParse(null), isNull);
  });
}
