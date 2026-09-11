import 'package:url_launcher/url_launcher.dart';

const _defaultPackage = 'com.agronizer.greengrow';
const _defaultHttps =
    'https://www.rustore.ru/catalog/app/com.agronizer.greengrow';

/// Opens the app page in the RuStore **app** when possible (separate task),
/// otherwise in an external browser — never an in-app WebView/Custom Tab overlay
/// when a native handler exists.
Future<bool> openRuStoreListing([Uri? catalogUri]) async {
  final https = _httpsCatalog(catalogUri);
  final package = _packageFromCatalog(https) ?? _defaultPackage;
  final deepLink = Uri.parse('rustore://apps.rustore.ru/app/$package');

  // 1) Native RuStore scheme → RuStore app.
  if (await _tryLaunch(deepLink, LaunchMode.externalApplication)) {
    return true;
  }
  // 2) HTTPS with non-browser preference → RuStore if it handles App Links.
  if (await _tryLaunch(https, LaunchMode.externalNonBrowserApplication)) {
    return true;
  }
  // 3) External browser / Custom Tabs as last resort.
  return _tryLaunch(https, LaunchMode.externalApplication);
}

Uri _httpsCatalog(Uri? preferred) {
  if (preferred == null) return Uri.parse(_defaultHttps);
  final s = preferred.toString().trim();
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return preferred;
  }
  if (s.startsWith('rustore://')) {
    final pkg = _packageFromDeepLink(preferred) ?? _defaultPackage;
    return Uri.parse('https://www.rustore.ru/catalog/app/$pkg');
  }
  return Uri.parse(_defaultHttps);
}

String? _packageFromCatalog(Uri uri) {
  final parts = uri.pathSegments;
  final i = parts.indexOf('app');
  if (i >= 0 && i + 1 < parts.length) {
    final pkg = parts[i + 1].trim();
    if (pkg.isNotEmpty) return pkg;
  }
  return null;
}

String? _packageFromDeepLink(Uri uri) {
  final parts = uri.pathSegments;
  final i = parts.indexOf('app');
  if (i >= 0 && i + 1 < parts.length) {
    final pkg = parts[i + 1].trim();
    if (pkg.isNotEmpty) return pkg;
  }
  return null;
}

Future<bool> _tryLaunch(Uri uri, LaunchMode mode) async {
  try {
    return await launchUrl(uri, mode: mode);
  } catch (_) {
    return false;
  }
}
