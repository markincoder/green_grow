import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';
import '../state/access_store.dart';
import '../theme/app_theme.dart';

Future<void> showAppUpdateDialog(BuildContext context, AccessStore access) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Обнаружено обновление'),
      content: Text(_message(access, auto: kIsWeb)),
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
            await launchUrl(
              access.updateApkUri,
              mode: LaunchMode.externalApplication,
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.leaf,
            foregroundColor: Colors.white,
          ),
          child: const Text('Установить'),
        ),
      ],
    ),
  );
}

String _message(AccessStore access, {required bool auto}) {
  final remote = access.remoteVersion?.label;
  final headline = (remote != null && remote.isNotEmpty)
      ? 'Доступна версия $remote.'
      : 'Доступна новая версия приложения.';
  if (auto) {
    return '$headline Установить сейчас? Страница перезагрузится.';
  }
  return '$headline Автоматически установить нельзя.\n\n'
      'Нажмите «Установить», откройте скачанный файл и подтвердите установку '
      'поверх текущей версии.';
}
