import 'package:web/web.dart' as web;

const _cookie = 'agronizer_access_start';

int? readAccessFirstStartBackup() {
  try {
    for (final part in web.document.cookie.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length >= 2 && kv[0] == _cookie) {
        return int.tryParse(kv[1]);
      }
    }
  } catch (_) {}
  return null;
}

void writeAccessFirstStartBackup(int millis) {
  try {
    final secure = web.window.location.protocol == 'https:';
    final extra = secure ? '; Secure' : '';
    web.document.cookie =
        '$_cookie=$millis; max-age=31536000; path=/; SameSite=Lax$extra';
  } catch (_) {}
}
