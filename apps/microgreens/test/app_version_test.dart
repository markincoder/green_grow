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

  test('normalizes flutter split-per-abi versionCode', () {
    expect(AppVersion.normalizeSplitPerAbiBuild(12), 12);
    expect(AppVersion.normalizeSplitPerAbiBuild(2012), 12); // old: abi*1000+build
    expect(AppVersion.normalizeSplitPerAbiBuild(12002), 12); // new: build*1000+abi
    expect(AppVersion.normalizeSplitPerAbiBuild(2011), 11);
    expect(
      AppVersion('1.0.11', AppVersion.normalizeSplitPerAbiBuild(2012))
          .isNewerThan(const AppVersion('1.0.11', 12)),
      isFalse,
    );
    expect(
      const AppVersion('1.0.11', 12).isNewerThan(
        AppVersion('1.0.11', AppVersion.normalizeSplitPerAbiBuild(2011)),
      ),
      isTrue,
    );
  });
}
