import 'package:package_info_plus/package_info_plus.dart';

/// App identity from `pubspec.yaml` `version: x.y.z+build`.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.name, [this.build = 0]);

  final String name;
  final int build;

  static AppVersion? tryParse(String? name, [Object? buildRaw]) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return null;
    var build = 0;
    if (buildRaw is int) {
      build = buildRaw;
    } else if (buildRaw != null) {
      build = int.tryParse(buildRaw.toString().trim()) ?? 0;
    }
    return AppVersion(n, build);
  }

  static Future<AppVersion> fromPlatform() async {
    final info = await PackageInfo.fromPlatform();
    final parsed = tryParse(info.version, info.buildNumber);
    if (parsed == null) return const AppVersion('0.0.0');
    // `flutter build apk --split-per-abi` rewrites Android versionCode, so
    // PackageInfo.buildNumber is not the pubspec `+build` (e.g. 2012 / 12002).
    return AppVersion(parsed.name, normalizeSplitPerAbiBuild(parsed.build));
  }

  /// Undo Flutter ABI versionCode encoding so we can compare with `version.json`.
  ///
  /// Old scheme: `abi * 1000 + build` (arm64 → 2xxx).
  /// New scheme: `build * 1000 + abi` (arm64 → xxx002).
  static int normalizeSplitPerAbiBuild(int code) {
    if (code < 1000) return code;
    const abiTags = {1, 2, 4};
    final mod = code % 1000;
    final div = code ~/ 1000;
    if (abiTags.contains(mod)) return div;
    if (abiTags.contains(div)) return mod;
    return code;
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  String get label => build > 0 ? '$name+$build' : name;

  @override
  int compareTo(AppVersion other) {
    final left = _parts(name);
    final right = _parts(other.name);
    final len = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < len; i++) {
      final a = i < left.length ? left[i] : 0;
      final b = i < right.length ? right[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return build.compareTo(other.build);
  }

  static List<int> _parts(String version) {
    return version
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList(growable: false);
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && other.name == name && other.build == build;

  @override
  int get hashCode => Object.hash(name, build);

  @override
  String toString() => label;
}
