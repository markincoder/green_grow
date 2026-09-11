import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_update.dart';
import '../services/rustore_open.dart';
import '../state/access_store.dart';
import '../theme/app_theme.dart';

Future<void> showAppUpdateDialog(BuildContext context, AccessStore access) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Обнаружено обновление'),
      content: Text(_message(access)),
      actions: [
        TextButton(
          onPressed: () {
            if (kIsWeb) dismissWebAppUpdatePrompt();
            Navigator.pop(ctx);
          },
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            if (kIsWeb) {
              await applyWebAppUpdate();
              return;
            }
            await openRuStoreListing(access.updateApkUri);
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.leaf,
            foregroundColor: Colors.white,
          ),
          child: Text(kIsWeb ? 'Установить' : 'В RuStore'),
        ),
      ],
    ),
  );
}

String _message(AccessStore access) {
  final remote = access.remoteVersion?.label;
  if (remote != null && remote.isNotEmpty) {
    return 'Доступна версия $remote.';
  }
  return 'Доступна новая версия приложения.';
}
