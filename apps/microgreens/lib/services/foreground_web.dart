import 'dart:js_interop';

import 'package:web/web.dart' as web;

void listenPageForeground(void Function() onForeground) {
  void fire(web.Event _) {
    if (web.document.visibilityState == 'visible') onForeground();
  }

  final js = fire.toJS;
  web.document.addEventListener('visibilitychange', js);
  web.window.addEventListener('focus', js);
  web.window.addEventListener('pageshow', js);
}
